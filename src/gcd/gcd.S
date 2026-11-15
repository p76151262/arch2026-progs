# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

# gcd_u32_asm: binary GCD, hand-written RV32I.
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b) a in a0, b in a1, result in a0
.globl  gcd_u32_asm
.type   gcd_u32_asm, @function
.align  2
gcd_u32_asm:
    bnez    a0, 1f
    mv      a0, a1          # if a == 0, return b
    ret
1:
    bnez    a1, 1f
    ret                     # if b == 0, return a
1:
    li      a2, 0           # a2 = k = 0
    or      t0, a0, a1      # t0 = a | b
.Lk_loop:
    andi    t1, t0, 1
    bnez    t1, .Lk_done
    srli    t0, t0, 1
    addi    a2, a2, 1
    j       .Lk_loop
.Lk_done:

    srl     a0, a0, a2      # a0 = a >> k
    srl     a1, a1, a2      # a1 = b >> k

    # strip trailing zeros from a
    andi    t0, a0, 1       # t0 = a & 1
    bnez    t0, .La_odd     # if (a & 1) != 0, a is odd
.La_odd_loop:
    srli    a0, a0, 1
    andi    t0, a0, 1
    beqz    t0, .La_odd_loop
.La_odd:

    # strip trailing zeros from b
    andi    t0, a1, 1       # t0 = b & 1
    bnez    t0, .Lb_odd     # if (b & 1) != 0, b is odd
.Lb_odd_loop:
    srli    a1, a1, 1
    andi    t0, a1, 1
    beqz    t0, .Lb_odd_loop
.Lb_odd:

.Lmain_loop:
    beq     a0, a1, .Ldone  # if (a0 == a1), end loop
    bltu    a0, a1, 1f
    # (a0 > a1)
    sub     a0, a0, a1
    j       .Lshift_a
1:
    # a0 < a1
    sub     t0, a1, a0
    mv      a1, a0          # a1 = min(a0, a1)
    mv      a0, t0          # a0 = |a0 - a1|
.Lshift_a:
    srli    a0, a0, 1       # a >>= 1
    andi    t0, a0, 1       # t0 = a & 1
    beqz    t0, .Lshift_a   # if (a & 1) == 0, a is still even
    j       .Lmain_loop

.Ldone:
    sll     a0, a0, a2      # return a >> k
    ret
.size   gcd_u32_asm, .-gcd_u32_asm


# count trailing zeros
.type   ctz_u32_asm, @function
.align  2
ctz_u32_asm:
    bnez    a0, 1f
    li      a0, 32
    ret
1:
    li      a6, 0           # a6 = n = 0

    # check 16 bits (0xFFFF doesn't fit in 12-bit imm, slli 16 discards high 16 bits)
    slli    a7, a0, 16      # a7 = x << 16
    bnez    a7, 1f          # if (x & 0xFFFF) != 0, skip
    addi    a6, a6, 16      # n += 16
    srli    a0, a0, 16      # x >>= 16
1:
    andi    a7, a0, 0xFF    # test low 8 bits
    bnez    a7, 1f          # if (x & 0xFF) != 0, skip
    addi    a6, a6, 8       # n += 8
    srli    a0, a0, 8       # x >>= 8
1:
    andi    a7, a0, 0xF
    bnez    a7, 1f
    addi    a6, a6, 4
    srli    a0, a0, 4
1:
    andi    a7, a0, 0x3
    bnez    a7, 1f
    addi    a6, a6, 2
    srli    a0, a0, 2
1:
    andi    a7, a0, 1
    bnez    a7, 1f
    addi    a6, a6, 1
1:
    mv      a0, a6          # return n
    ret
.size   ctz_u32_asm, .-ctz_u32_asm
