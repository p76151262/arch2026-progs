#include "gcd.h"
#include <stdint.h>

// count trailing zeros in binary representation
// returns # of zeros before 1st appearance of 1
static inline uint8_t ctz_u32(uint32_t x)
{
    if (x == 0)
        return 32;

    uint8_t n = 0;  // # of trailing zeros

    if ((x & 0x0000FFFF) == 0) {  // +16 trailing zeros
        n += 16;
        x >>= 16;
    }

    if ((x & 0x000000FF) == 0) {  // +8 trailing zeros
        n += 8;
        x >>= 8;
    }

    if ((x & 0x00000000F) == 0) {  // +4 trailing zeros
        n += 4;
        x >>= 4;
    }

    if ((x & 0b0011) == 0) {  // +2 trailing zeros
        n += 2;
        x >>= 2;
    }

    if ((x & 0b01) == 0) {  // +1 trailing zeros
        n += 1;
    }

    return n;
}

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    // extract common factors of 2
    // uint8_t k = ctz_u32(a | b);
    uint8_t k = 0;
    uint32_t s = a | b;
    while ((s & 1) == 0) {
        k++;
        s >>= 1;
    }

    // make a, b odd by shifting out trailing zeros
    a >>= k;
    b >>= k;

    while ((a & 1) == 0) {
        a >>= 1;
    }

    while ((b & 1) == 0) {
        b >>= 1;
    }

    while (a != b) {
        // make sure a >= b
        if (a < b) {
            uint32_t temp = a;
            a = b;
            b = temp;
        }
        a -= b;  // a is even now

        // make a odd
        while ((a & 1) == 0) {
            a >>= 1;
        }
    }

    return a << k;
}
