# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

.text

.globl  bf16_from_f32_asm
.type   bf16_from_f32_asm, @function
.align  2
bf16_from_f32_asm:
    lui     t0, 0x7F800         # t0 = 0x7F800000
    and     a1, a0, t0          # a1 = f32bits & 0x7F800000 (keep exp field)
    beq     a1, t0, 1f          # if exp == 0xFF, skip rounding
    srli    a1, a0, 16          # a1 = f32bits >> 16
    andi    a1, a1, 1           # a1 = (f32bits >> 16) + 1
    li      t0, 0x7FFF          # lui + addi (2 instructions)
    add     a0, a0, t0          # a0 = f32bits + 0x7FFF
    add     a0, a0, a1          # a0 = f32bits + 0x7FFF + (f32bits >> 16) + 1
1:
    srli    a0, a0, 16          # return f32bits >> 16
    ret
.size   bf16_from_f32_asm, .-bf16_from_f32_asm


.globl  bf16_mul_asm
.type   bf16_mul_asm, @function
.align  2
bf16_mul_asm:
    xor     a2, a0, a1
    li      t0, 0x8000
    and     a2, a2, t0          # a2 = sign = (a ^ b) & 0x8000
    li      t0, 0xFF
    srli    a3, a0, 7           # a3 = a >> 7
    and     a3, a3, t0          # a3 = exp_a = (a >> 7) & 0xFF
    andi    a4, a0, 0x7F        # a4 = frac_a = a & 0x7F
    bne     a3, t0, .Lmul_exp_b # exp_a != 0xFF
.Lmul_exp_a:
    beqz    a4, 1f              # frac_a == 0
    ret                         # a is NaN, return a
1:  # a is Inf
    li      t1, 0x7FFF
    and     a1, a1, t1          # a1 = (b & 0x7FFF)
    bnez    a1, 1f
    li      a0, 0x7FC0          # return quiet NaN
    ret
1:  # (b & 0x7FFF) != 0
    li      t0, 0x7F80
    or      a0, a2, t0          # return (sign | 0x7F80) (Inf)
    ret
.Lmul_exp_b:
    srli    a5, a1, 7
    and     a5, a5, t0                  # a5 = exp_b = (b >> 7) & 0xFF
    andi    a6, a1, 0x7F                # a6 = frac_b = b & 0x7F
    bne     a5, t0, .Lmul_check_zeros   # exp_b != 0xFF
    beqz    a6, 1f                      # frac_b == 0
    mv      a0, a1                      # b is NaN
    ret                                 # return b
1:  # b is Inf
    li      t1, 0x7FFF
    and     a0, a0, t1
    bnez    a0, 1f
    li      a0, 0x7FC0
    ret
1:     
    li      t0, 0x7F80
    or      a0, a2, t0
    ret
.Lmul_check_zeros:
    li      t1, 0x7FFF
    and     t2, a0, t1
    bnez    t2, .Lmul_a_not_zero
    mv      a0, a2                  # a is 0, return sign
    ret
.Lmul_a_not_zero:
    and     t2, a1, t1
    bnez    t2, .Lmul_b_not_zero
    mv      a0, a2                  # b is 0, return sign
    ret
.Lmul_b_not_zero:
.Lmul_ea:   # a3 = ea, a4 = sig_a
    bnez    a3, .Lmul_ea_not_zero
    li      a3, 1
    andi    t1, a4, 0x80        # t1 = sig_a & 0x80
.Lmul_sig_a_loop:
    bnez    t1, .Lmul_eb
    slli    a4, a4, 1           # sig_a <<= 1
    addi    a3, a3, -1          # ea -= 1
    andi    t1, a4, 0x80        # t1 = sig_a & 0x80
    j       .Lmul_sig_a_loop
.Lmul_ea_not_zero:
    ori     a4, a4, 0x80
.Lmul_eb:   # a5 = eb, a6 = sig_b
    bnez    a5, .Lmul_eb_not_zero
    li      a5, 1
    andi    t1, a6, 0x80        # t1 = sig_b & 0x80
.Lmul_sig_b_loop:
    bnez    t1, .Lmul_eb_done
    slli    a6, a6, 1
    addi    a5, a5, -1
    andi    t1, a6, 0x80        # t1 = sig_b & 0x80
    j       .Lmul_sig_b_loop
.Lmul_eb_not_zero:
    ori     a6, a6, 0x80
.Lmul_eb_done:
    add     a3, a3, a5          # a3 = ea + eb
    addi    a3, a3, -127        # a3 = exp = ea + eb -127

    # atp, we're about to call subroutine
    # so stack is allocated until now
    addi    sp, sp, -16
    sw      ra, 0(sp)

    mv      a0, a4
    mv      a1, a6
    sw      a2, 4(sp)
    sw      a3, 8(sp)
    jal     __mulsi3            # a0 = prod = sig_a * sig_b
    lw      a2, 4(sp)
    lw      a3, 8(sp)

    li      t0, 0x8000
    and     t0, a0, t0              # t0 = prod & 0x8000
    beqz    t0, .Lmul_prod_in_1_2   # (prod & 0x8000) == 0
.Lmul_prod_in_2_4:
    srli    a0, a0, 8       # prod >>= 8
    addi    a3, a3, 1       # exp++
    j       .Lmul_frac
.Lmul_prod_in_1_2:
    srli    a0, a0, 7       # prod >>= 7
.Lmul_frac:
    andi    a0, a0, 0x7F    # a0 = frac = prod & 0x7F
    slti    t0, a3, 0xFF    # t0 = (exp < 0xFF)
    bnez    t0, .Lmul_exp_lt_0xFF
    li      t0, 0x7F80      # (exp >= 0xFF)
    or      a0, a2, t0      # return (sign | 0x7F80)

    lw      ra, 0(sp)
    addi    sp, sp, 16
    ret
.Lmul_exp_lt_0xFF:
    bgtz    a3, .Lmul_normal
    li      t0, -6
    blt     a3, t0, 1f
    neg     a3, a3
    addi    a3, a3, 1
    srl     a0, a0, a3
    or      a0, a2, a0

    lw      ra, 0(sp)
    addi    sp, sp, 16 
    ret
1:
    mv      a0, a2      # return sign (a2)

    lw      ra, 0(sp)
    addi    sp, sp, 16 
    ret
.Lmul_normal:
    or      a0, a0, a2
    slli    a3, a3, 7
    or      a0, a0, a3

    lw      ra, 0(sp)
    addi    sp, sp, 16 
    ret
.size   bf16_mul_asm, .-bf16_mul_asm


.macro ISQRT_STEP bit
    addi    t0, t1, \bit
    srli    t1, t1, 1
    bltu    a3, t0, 1f
    sub     a3, a3, t0
    addi    t1, t1, \bit
1:
.endm

.globl  bf16_sqrt_asm
.type   bf16_sqrt_asm, @function
.align  2
bf16_sqrt_asm:
    srli    a2, a0, 7
    andi    a2, a2, 0xFF        # a2 = exp = (a >> 7) & 0xFF
    li      t0, 0xFF
    beq     a2, t0, .Lsqrt_inf_nan
    slli    t0, a0, 17          # (a & 0x7FFF) == 0 ?
    beqz    t0, .Lsqrt_ret_zero
    slli    a1, a0, 16          # move sign bit to bit 31
    bltz    a1, .Lsqrt_ret_qnan # negative nonzero -> qNaN
    beqz    a2, .Lsqrt_ret_zero # positive denormal -> +0

    andi    a3, a0, 0x7F
    ori     a3, a3, 0x80        # m = 0x80 | frac
    addi    a2, a2, -127        # e = exp - 127
    andi    t0, a2, 1
    beqz    t0, .Lsqrt_even

    # Odd e: double m, then e = (e - 1) >> 1
    addi    a2, a2, -1
    slli    a3, a3, 1
    srai    a2, a2, 1
    addi    a2, a2, 127
    slli    a3, a3, 7
    ori     a3, a3, 127         # n = (m << 7) | 127

    # Iter 1 (bit = 0x4000) is always taken
    lui     t0, 0xFFFFC         # -16384
    add     a3, a3, t0
    lui     t1, 4               # res = 0x4000
    # Iter 2 (bit = 0x1000)
    lui     t2, 1               # 4096
    add     t0, t1, t2
    srli    t1, t1, 1
    bltu    a3, t0, .Lsqrt_steps
    sub     a3, a3, t0
    add     t1, t1, t2
    j       .Lsqrt_steps

.Lsqrt_even:
    srai    a2, a2, 1
    addi    a2, a2, 127
    slli    a3, a3, 7
    ori     a3, a3, 127

    # Iter 1 always taken, Iter 2 never taken (n < 32768 < 16384 + 20480)
    lui     t0, 0xFFFFC         # -16384
    add     a3, a3, t0
    lui     t1, 2               # res = 0x2000

.Lsqrt_steps:
    ISQRT_STEP 1024
    ISQRT_STEP 256
    ISQRT_STEP 64
    ISQRT_STEP 16
    ISQRT_STEP 4

    # Last step (bit = 1): no need to update n (a3)
    addi    t0, t1, 1
    srli    t1, t1, 1
    bltu    a3, t0, 1f
    addi    t1, t1, 1
1:
    slli    a0, a2, 7
    andi    t1, t1, 0x7F
    or      a0, a0, t1
    ret

.Lsqrt_inf_nan:
    andi    a3, a0, 0x7F
    bnez    a3, 1f              # NaN: return a0 unchanged
    slli    a1, a0, 16
    bltz    a1, .Lsqrt_ret_qnan # -Inf -> qNaN
1:
    ret                         # +Inf or NaN: return a0 unchanged
.Lsqrt_ret_zero:
    li      a0, 0
    ret
.Lsqrt_ret_qnan:
    li      a0, 0x7FC0
    ret
.size   bf16_sqrt_asm, .-bf16_sqrt_asm
