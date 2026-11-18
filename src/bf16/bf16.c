#include "bf16.h"
#include <stdint.h>
#include <sys/types.h>

/*
fp32 format:
bit 31 | bit 30-23 (8 bits) | bit 22-0 (23 bits)
sign   | exponent           | mantissa

fp32 values (e = 8):
value           exponent        mantissa
0               0               0
denormalized    0               non-zero
normalized      1 to 2^e-2      non-zero
Inf             2^e - 1         0
NaN             2^e - 1         non-zero

bf16 format:
bit 15 | bit 14-7 (8 bits) | bit 6-0 (7 bits)
sign   | exponent          | mantissa

bf16 values (e = 8):
value           exponent        mantissa
0               0               0
denormalized    0               non-zero
normalized      1 to 2^e-2      non-zero
Inf             2^e - 1         0
NaN             2^e - 1         non-zero
*/

// 0111 1111 1100 0000
#ifndef BF16_QUIET_NAN
#define BF16_QUIET_NAN 0x7FC0
#endif

#ifndef BF16_POSITIVE_INF
#define BF16_POSITIVE_INF 0x7F80
#endif

uint16_t bf16_from_f32(uint32_t f32bits)
{
    // If fp32's bit 30-23 are all set -> Inf or NaN.
    // While IEEE 754 fp32 NaN may be incorrectly transformed to
    // bf16 Inf (which differs from standard implementation),
    // it is required by the bf16.h specification.
    if ((f32bits & 0x7F800000) == 0x7F800000)
        return (uint16_t) (f32bits >> 16);

    /*
    Low 16 bits of fp32 would be discarded.
    Round to nearest, ties to even.

    Add 0x7FFF, plus bit 16, keep high 16 bits.
    Consider lo = f32bits & 0xFFFF, hi = f32bits >> 16
    0x8000 (half of 0x10000) + 0x7FFF = 0xFFFF
    if lo < 0x8000, lo + 0x7FFF + 1 < 0x10000, no carry to hi
    if lo > 0x8000, lo + 0x7FFF > 0xFFFF, carry to hi
    if lo == 0x8000 (tie),
        if (hi & 1) == 0 (even), 0x8000 + 0x7FFF + 0 = 0xFFFF
        no carry to hi, remains as even

        if (hi & 1) == 1 (odd),  0x8000 + 0x7FFF + 1 = 0x10000
        carry to hi, becomes even
    */
    f32bits += 0x7FFF + ((f32bits >> 16) & 1);

    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint16_t sign = (a ^ b) & 0x8000;

    uint8_t exp_a = (a >> 7) & 0xFF;
    uint8_t frac_a = a & 0x7F;

    if (exp_a == 0xFF) {
        if (frac_a)  // a is NaN
            return a;

        // otherwise, a is Inf
        if ((b & 0x7FFF) == 0) {  // b == ±0, Inf times 0 == NaN
            return BF16_QUIET_NAN;
        }

        return sign | BF16_POSITIVE_INF;  // ±Inf
    }

    uint8_t exp_b = (b >> 7) & 0xFF;
    uint8_t frac_b = b & 0x7F;

    if (exp_b == 0xFF) {
        if (frac_b)  // b is NaN
            return b;

        // otherwise, b is Inf
        if ((a & 0x7FFF) == 0) {  // a == ±0, Inf times 0 == NaN
            return BF16_QUIET_NAN;
        }

        return sign | BF16_POSITIVE_INF;  // ±Inf
    }

    // a, b are finites, one or both zero
    if ((a & 0x7FFF) == 0 || (b & 0x7FFF) == 0)
        return sign;

    int32_t ea = exp_a;
    uint32_t sig_a = frac_a;
    if (ea == 0) {  // a is denormalized, normalize it first
        ea = 1;     // by IEEE 754, denormalized number base exp is 1
        while ((sig_a & 0x80) == 0) {  // bit 8 not set
            sig_a <<= 1;               // sig times 2
            ea--;                      // exp minus 1, align w/ the times 2
        }
    } else {  // a is normalized, put in the implicit 1 directly
        sig_a |= 0x80;
    }

    int32_t eb = exp_b;
    uint32_t sig_b = frac_b;
    if (eb == 0) {  // b is denormalized, normalize it first
        eb = 1;
        while ((sig_b & 0x80) == 0) {  // bit 8 not set
            sig_b <<= 1;               // sig times 2
            eb--;                      // exp minus 1, align w/ the times 2
        }
    } else {  // b is normalized, put in the implicit 1 directly
        sig_b |= 0x80;
    }

    /*
    sig_a and sig_b are normalized to [128, 255] or [1.0, 2.0) x 2^7
    prod = [128 x 128, 255 x 255] = [0x4000, 0xFE01]
    */

    int32_t exp = ea + eb - 127;
    uint32_t prod = sig_a * sig_b;  // __mulsi3

    if (prod & 0x8000) {
        // prod is in [2.0, 4.0)
        // bit 15 is set, the point is between bit 15 and 14
        // move bit 15 to bit 7
        prod >>= 8;
        exp++;
    } else {
        // prod is in [1.0, 2.0)
        prod >>= 7;
    }

    // Truncation
    uint32_t frac = prod & 0x7F;

    // Handle overflow & underflow
    if (exp >= 0xFF) {  // overlowed to Inf
        return sign | BF16_POSITIVE_INF;
    }

    if (exp <= 0) {      // underflowed to denormalized
        if (exp < -6) {  // 0
            return sign;
        }

        // -6 <= exp <= 0
        return sign | (frac >> (1 - exp));
    }

    // no overflow or underflow
    return sign | ((uint16_t) exp << 7) | frac;
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint16_t sign = a & 0x8000;
    uint16_t exp = (a >> 7) & 0xFF;
    uint16_t frac = a & 0x7F;

    if (exp == 0xFF) {  // NaN or Inf
        if (frac != 0)  // NaN
            return a;   // return unchanged NaN

        if (sign == 0)  // +InF
            return BF16_POSITIVE_INF;

        // -InF
        return BF16_QUIET_NAN;
    }

    if ((a & 0x7FFF) == 0)  // ±0
        return 0x0000;

    if (sign != 0)  // negtive normal/denormal
        return BF16_QUIET_NAN;

    if (exp == 0)  // positive denormal
        return 0x0000;

    // a must be a positive normal atp

    /*
    a = (m/128) * 2^e, where e = exp - 127
    sart(a) = sqrt(m/128) * 2^(e/2)
    if e is odd, give 1 e to m beforehand
    2^e * m = 2^(e-1) * (2m)

    After adjusting, m in [128, 510],
    corresponde to real number [1.0, 4.0), after sqrt,
    the real number is in [1.0, 2.0)
    */
    int32_t e = (int32_t) exp - 127;
    uint32_t m = 0x80 | frac;
    if (e & 1) {  // e is odd
        e -= 1;
        m <<= 1;
    }
    e >>= 1;  // e / 2
    int32_t res_exp = e + 127;

    if (res_exp >= 0xFF)
        return BF16_POSITIVE_INF;
    if (res_exp <= 0)
        return 0x0000;

    /*
    Find the max mid that satisfies
    mid/128 <= sqrt(m/128)
    floor(mid^2 / 128) <= m
    which means: mid^2 < 128*(m + 1)
    Since integer math: mid^2 <= 128*m + 127 = (m << 7) | 127
    */
    uint32_t n = (m << 7) | 127u;  // term: (m << 7) | 127
    uint32_t res = 0;              // 2Pb
    uint32_t bit = 1u << 14;       // b^2

    while (bit != 0) {
        uint32_t t = res + bit;  // 2Pb + b^2
        res >>= 1;
        if (n >= t) {  // n >= res + bit
            n -= t;    // n = n - (P + b)^2
            res += bit;
        }
        bit >>= 2;  // b_next = b / 2, so b_{next}^2 = b / 4
    }

    return (uint16_t) (((uint32_t) res_exp << 7) | (res & 0x7F));
}

#undef BF16_QUIET_NAN
#undef BF16_POSITIVE_INF