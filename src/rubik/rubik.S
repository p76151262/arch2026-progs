.section .rodata

.align 2
move_str0: .string "R"
move_str1: .string "R2"
move_str2: .string "R'"
move_str3: .string "B"
move_str4: .string "B2"
move_str5: .string "B'"
move_str6: .string "D"
move_str7: .string "D2"
move_str8: .string "D'"

.align 2
move_names:
    .word move_str0
    .word move_str1
    .word move_str2
    .word move_str3
    .word move_str4
    .word move_str5
    .word move_str6
    .word move_str7
    .word move_str8

.align 2
move_name_flag:
    .byte 0, 1, 1, 0, 1, 1, 0, 1, 1

.align 2
p_fact_lut:
    .half 0, 720, 1440, 2160, 2880, 3600, 4320, 0
    .half 0, 120, 240, 360, 480, 600, 720, 0
    .half 0, 24, 48, 72, 96, 120, 144, 0
    .half 0, 6, 12, 18, 24, 30, 36, 0
    .half 0, 2, 4, 6, 8, 10, 12, 0
    .half 0, 1, 2, 3, 4, 5, 6, 0
    .half 0, 1, 2, 3, 4, 5, 6, 0

.align 2
o_tenary_lut:
    .half 0, 243, 486 ,0
    .half 0, 81, 162, 0
    .half 0, 27, 54, 0
    .half 0, 9, 18, 0
    .half 0, 3, 6, 0
    .half 0, 1, 2, 0

.data

.align 2
state:          .zero 14
.align 2
solution_path:  .zero 11

.text

# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.
.globl  rubik_solve_asm
.type   rubik_solve_asm, @function
.align  2
rubik_solve_asm:
    addi    sp, sp, -80
    sw      s0, 52(sp)
    sw      s1, 56(sp)
    sw      s2, 60(sp)
    sw      s3, 64(sp)
    sw      s4, 68(sp)
    sw      s5, 72(sp)
    sw      ra, 76(sp)

    mv      s4, a1  # s4 = out
    mv      s5, a2  # s5 = cap

    # if cap == 0, return -2
    beqz    s5, invalid_buf

    # a0 = state_str
    # a1 = parsed state
    la      a1, state
    jal     parse_state
    # if parse failed (result == 0), return -1
    beqz    a0, invalid_state
    jal     rank_state

    mv      s0, a0   # s0 = start_p
    mv      s1, a1   # s1 = start_o

    la      t0, h_p
    add     t0, t0, s0
    lbu     s2, 0(t0)               # s2 = h_p[start_p]
    la      t0, h_o
    add     t0, t0, s1
    lbu     t0, 0(t0)               # t0 = h_o[start_o]
    bgeu    s2, t0, idfs_driver     # if h_p[start_p] > h_o[start_o], ok
    mv      s2, t0                  # otherwise, swap
idfs_driver:
    # s2 = start_bound = h = max(h_p[start_p], h_o[start_o])
    li s3, 12
idfs_driver_L0:
    bgeu s2, s3, invalid_state  # if bound <= 11, loop
    mv a0, s0
    mv a1, s1
    mv a2, s2
    jal idfs
    bnez a0, set_sol            # idfs return 1, break
    addi s2, s2, 1              # otherwise, bound++
    j idfs_driver_L0
set_sol:
    bnez    s2, set_sol_L0      # bound == 0
    bgtz    s5, set_sol_b0      # cap > 0
    li      a0, -2              # return -2
    j       rubik_solve_asm_end
set_sol_b0:
    sb      zero, 0(s4)         # out[0] = '\0'
    li      a0, 0               # return 0
    j       rubik_solve_asm_end
set_sol_L0:
    # char temp[33] loactes at sp
    mv      s0, sp              # s0 = temp
    li      t1, 0               # i = 0
    la      t2, solution_path
    la      t3, move_names
    la      t4, move_name_flag
set_sol_L1:
    bgeu    t1, s2, set_sol_L3  # i < bound
    add     t5, t2, t1          # t5 = solution_path + i
    lbu     t5, 0(t5)           # t5 = move_id = solution_path[i]
    slli    t6, t5, 2           # t6 = move_id * 4
    add     t6, t3, t6          # t6 = move_names + move_id * 4
    lw      t6, 0(t6)           # t6 = move_str = move_names[move_id]
    add     t5, t4, t5
    lbu     t5, 0(t5)           # t5 = move_str_flag
    lbu     s1, 0(t6)           # s1 = move_str[0]
    sb      s1, 0(s0)           # *temp = move_str[0]
    addi    s0, s0, 1           # temp++
    beqz    t5, set_sol_L2      # move_str_flag == 0
    lbu     s1, 1(t6)           # s1 = move_str[1]
    sb      s1, 0(s0)           # *temp = move_str[1]
    addi    s0, s0, 1           # temp++
set_sol_L2:
    li      s1, 32              # s1 = ' '
    sb      s1, 0(s0)           # *temp = ' '
    addi    s0, s0, 1           # temp++
    addi    t1, t1, 1           # i++
    j       set_sol_L1
set_sol_L3:
    sb      zero, -1(s0)        # temp[str_len - 1] = '\0'
    sub     t0, s0, sp          # t0 = str_len (including '\0')
    bleu    t0, s5, set_sol_L4  # str_len > cap
    beqz    s5, invalid_buf     # cap >= 1
    sb      zero, 0(s4)         # out[0] = '\0'
    j       invalid_buf         # return -2
set_sol_L4:
    li      t1, 0               # i == 0
    mv      s0, sp
set_sol_L5:
    bgeu    t1, t0, set_sol_L6  # i < str_len
    lbu     t2, 0(s0)           # t2 = temp[i]
    sb      t2, 0(s4)           # out[i] = temp[i]
    addi    s0, s0, 1
    addi    s4, s4, 1
    addi    t1, t1, 1           # i++
    j       set_sol_L5
set_sol_L6:
    mv      a0, s2
    j       rubik_solve_asm_end
invalid_buf:
    li  a0, -2
    j   rubik_solve_asm_end
invalid_state:
    li  a0, -1
rubik_solve_asm_end:
    lw      s0, 52(sp)
    lw      s1, 56(sp)
    lw      s2, 60(sp)
    lw      s3, 64(sp)
    lw      s4, 68(sp)
    lw      s5, 72(sp)
    lw      ra, 76(sp)
    addi    sp, sp, 80
    ret
.size   rubik_solve_asm, .-rubik_solve_asm


.align  2
.type   parse_state, @function
# parse_state(const char *input, state_t *state)
# a0 = input(str), a1 = parsed state
parse_state:
    li a3, 49   # a3 = '1'
    li a4, 55   # a4 = '7'
    li a5, 51   # a5 = '3'

    # permutations
    lbu t2, 0(a0)               # t2 = str[0]
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a4, invalid_input  # invalid if t2 > '7'
    addi t2, t2, -49            # t2 -= '1'
    sb t2, 0(a1)                # state[0] = t2
    lbu t2, 1(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a4, invalid_input  # invalid if t2 > '7'
    addi t2, t2, -49
    sb t2, 1(a1)
    lbu t2, 2(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a4, invalid_input  # invalid if t2 > '7'
    addi t2, t2, -49
    sb t2, 2(a1)
    lbu t2, 3(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a4, invalid_input  # invalid if t2 > '7'
    addi t2, t2, -49
    sb t2, 3(a1)
    lbu t2, 4(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a4, invalid_input  # invalid if t2 > '7'
    addi t2, t2, -49
    sb t2, 4(a1)
    lbu t2, 5(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a4, invalid_input  # invalid if t2 > '7'
    addi t2, t2, -49
    sb t2, 5(a1)
    lbu t2, 6(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a4, invalid_input  # invalid if t2 > '7'
    addi t2, t2, -49
    sb t2, 6(a1)

    # orientations
    lbu t2, 7(a0)               # t2 = str[7]
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a5, invalid_input  # invalid if t2 > '3'
    addi t2, t2, -49            # t2 -= '1'
    sb t2, 7(a1)                # state[7] = t2
    lbu t2, 8(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a5, invalid_input  # invalid if t2 > '3'
    addi t2, t2, -49
    sb t2, 8(a1)
    lbu t2, 9(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a5, invalid_input  # invalid if t2 > '3'
    addi t2, t2, -49
    sb t2, 9(a1)
    lbu t2, 10(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a5, invalid_input  # invalid if t2 > '3'
    addi t2, t2, -49
    sb t2, 10(a1)
    lbu t2, 11(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a5, invalid_input  # invalid if t2 > '3'
    addi t2, t2, -49
    sb t2, 11(a1)
    lbu t2, 12(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a5, invalid_input  # invalid if t2 > '3'
    addi t2, t2, -49
    sb t2, 12(a1)
    lbu t2, 13(a0)
    bltu t2, a3, invalid_input  # invalid if t2 < '1'
    bgtu t2, a5, invalid_input  # invalid if t2 > '3'
    addi t2, t2, -49
    sb t2, 13(a1)

    # detect invalid state, check the following conditions
    # 1. stat_str[14] is null terminater
    # 2. no duplicate p[i]
    # 3. if sum of o[i]s' is multiple of 3
    lbu a0, 14(a0)
    bnez a0, invalid_input  # str[14] != '\0'
    # a0 = i = '\0' = 0
    li t5, 7                # t5 = i's upper bound
    li t6, 3                # t6 = 3, for sum % 3
    li t2, 0                # t2 = sum = 0
parse_state_L0:
    add t0, a1, a0              # t0 = state.p + i
    lbu t1, 7(t0)               # t1 = state.o[i]
    lbu t0, 0(t0)               # t0 = state.p[i]
    li t4, 0                    # t4 = j = 0
parse_state_L1:
    bgeu t4, a0, parse_state_L2 # j < i
    add t3, a1, t4              # t3 = state.p + j
    lbu t3, 0(t3)               # t3 = state.p[j]
    beq t3, t0, invalid_input   # state.p[j] == state.p[i]
    addi t4, t4, 1              # j++
    j parse_state_L1
parse_state_L2:
    add t2, t2, t1              # sum += state.o[i]
    addi a0, a0, 1              # i++
    bltu a0, t5, parse_state_L0 # i < 7
parse_state_L3:
    bltu t2, t6, parse_state_L4 # if sum < 3, don't subtract
    addi t2, t2, -3             # sum -= 3
    j parse_state_L3
parse_state_L4:
    bnez t2, invalid_input      # sum != 0, invalid
    li  a0, 1                   # return valid
    ret
invalid_input:
    li  a0, 0
    ret
.size   parse_state, .-parse_state


.align  2
.type   rank_state, @function
# u16_pair_t rank_state(void)
# return: a0 = rank_p, a1 = rank_o
rank_state:
    la      a2, state # a2 = state
    la      a3, p_fact_lut
    la      a4, o_tenary_lut
    li      a0, 0   # a0 = p = 0
    li      a1, 0   # a1 = o = 0

    li      t0, 0   # i = 0
    li      t1, 7   # t2 = 7
rank_state_L0:
    beq     t0, t1, rank_state_L3
    li      t2, 0       # smaller = 0
    addi    t3, t0, 1   # j = i + 1
rank_state_L1:
    beq     t3, t1, rank_state_L2
    add     t4, a2, t3
    lbu     t5, 0(t4)   # t5 = state->p[j]
    add     t4, a2, t0
    lbu     t6, 0(t4)   # t6 = state->p[i]
    sltu    t5, t5, t6
    add     t2, t2, t5  # smaller += (state->p[j] < state->p[i])
    addi    t3, t3, 1   # j++
    j       rank_state_L1
rank_state_L2:
    slli t4, t0, 3
    add t4, t4, t2 # t4 = i * 8 + samller
    slli t4, t4, 1 # t4 *= 2
    add t4, t4, a3
    lhu t4, 0(t4)
    add a0, a0, t4 # p += p_fact_lut[i][smaller];
    addi t0, t0, 1 # i++
    j rank_state_L0
rank_state_L3:
    addi t0, a2, 7 # t0 = state->o
    lbu t1, 0(t0)  # t1 = state->o[0]
    slli t1, t1, 1 # t1 = state->o[0] * 2
    add t1, t1, a4 # o_tenary_lut + t1
    lhu t1, 0(t1)  # o_tenary_lut[0][state->o[0]]
    add a1, a1, t1 # o += ...

    lbu t1, 1(t0)  # t1 = state->o[1]
    slli t1, t1, 1 # t1 = state->o[1] * 2
    addi t2, a4, 8 # t2 = o_tenary_lut[1]
    add t1, t1, t2 # o_tenary_lut[1] + t1
    lhu t1, 0(t1)  # o_tenary_lut[1][state->o[1]]
    add a1, a1, t1 # o += ...

    lbu t1, 2(t0)   # t1 = state->o[2]
    slli t1, t1, 1  # t1 = state->o[2] * 2
    addi t2, a4, 16 # t2 = o_tenary_lut[2]
    add t1, t1, t2  # o_tenary_lut[2] + t1
    lhu t1, 0(t1)   # o_tenary_lut[2][state->o[2]]
    add a1, a1, t1  # o += ...

    # o_tenary_lut[3][state->o[3]]
    lbu t1, 3(t0)
    slli t1, t1, 1
    addi t2, a4, 24
    add t1, t1, t2
    lhu t1, 0(t1)
    add a1, a1, t1

    # o_tenary_lut[4][state->o[4]]
    lbu t1, 4(t0)
    slli t1, t1, 1
    addi t2, a4, 32
    add t1, t1, t2
    lhu t1, 0(t1)
    add a1, a1, t1

    # o_tenary_lut[5][state->o[5]]
    lbu t1, 5(t0)
    slli t1, t1, 1
    addi t2, a4, 40
    add t1, t1, t2
    lhu t1, 0(t1)
    add a1, a1, t1
    ret
.size   rank_state, .-rank_state


.align 2
.type idfs, @function
# a0 = start_p, a1 = start_o, a2 = bound
idfs:
    or   t0, a0, a1     # start_p == 0 && start_o == 0
    bnez t0, idfs_L0
    li   a0, 1          # already solved state, return 1
    ret
idfs_L0:
    # 0(sp) - 23(sp): p_stk
    # 24(sp) - 47(sp): o_stk
    # 48(sp) - 59(sp): face_stk
    # 60(sp) - 71(sp): turn_stk
    addi sp, sp, -80
    la t5, h_p      # t5 = h_p
    la t6, h_o      # t6 = h_o
    sh a0, 0(sp)    # p_stk[0] = start_p
    sh a1, 24(sp)   # o_stk[0] = start_o
    li a3, 0        # a3 = depth = 0
    li a0, 2        # for idfs_resume_turn & idfs_next_face
idfs_enter_level:
    sub a1, a2, a3          # a1 = bound - depth
    addi a1, a1, -1         # a1 = h_limit = bound - depth - 1
    li t0, 0                # t0 = face = 0
    li t1, 0xFF             # t1 = last_face = 0xFF
    blez a3, idfs_face_loop # branch if depth <= 0
    addi t1, a3, -1         # t1 = depth - 1
    add t1, sp, t1
    lbu t1, 48(t1)          # t1 = last_face = face_stk[depth - 1]
idfs_face_loop:
    beq t0, t1, idfs_next_face  # pruning 2: if face == last_face
    slli t3, a3, 1  # t1 = depth * 2
    add t3, sp, t3
    lhu a4, 0(t3)   # a4 = next_p = p_stk[depth]
    lhu a5, 24(t3)  # a5 = next_o = o_stk[depth]

    # calculate next_rank_*[face][0] addresses, store in a6/a7
    la a6, next_p_face_ptr
    la a7, next_o_face_ptr
    slli t2, t0, 2      # t2 = face * 4
    add a6, a6, t2      # a6 = next_p_face_ptr + face
    add a7, a7, t2      # a7 = next_o_face_ptr + face
    lw  a6, 0(a6)       # a6 = next_p_face_ptr[face]
    lw  a7, 0(a7)       # a7 = next_o_face_ptr[face]
    li t2, 0            # t2 = turn = 0
idfs_turn_loop:
    slli t3, a4, 1      # t3 = next_p * 2
    add t3, a6, t3      # t3 = &next_rank_p[face][0] + t3
    lhu a4, 0(t3)       # a4 = next_p = next_rank_p[face][next_p]
    slli t3, a5, 1      # t3 = next_o * 2
    add t3, a7, t3      # t3 = &next_rank_o[face] + t3
    lhu a5, 0(t3)       # a5 = next_o = next_rank_o[face][next_o]

    # t3 = h = max(h_p[next_p], h_o[next_o])
    add t3, t5, a4                  # t3 = h_p + next_p
    lbu t3, 0(t3)                   # t3 = h_p[next_p]
    bgtu t3, a1, idfs_resume_turn   # h_p > bound - depth - 1, pruning 1
    add t4, t6, a5                  # t4 = h_o + next_o
    lbu t4, 0(t4)                   # t4 = h_o[next_o]
    bgtu t4, a1, idfs_resume_turn   # h_o > bound - depth - 1, pruning 1

    add t3, sp, a3                  # t3 = sp + depth
    sb t0, 48(t3)                   # face_stk[depth] = face
    sb t2, 60(t3)                   # turn_stk[depth] = turn

    or t3, a4, a5           # if (next_p == 0 && next_o == 0) is ture -> solution found
    bnez t3, idfs_L1        # branch if solution not found
    addi t3, t3, 0          # i = 0
    # t6 was h_o, however, since solution found, can be safely overwritten
    la t6, solution_path
idfs_sol_loop:
    # 48(sp) - 59(sp): face_stk
    # 60(sp) - 71(sp): turn_stk
    addi t4, sp, 48 # t4 = face_stk
    add t5, t4, t3  # t5 = face_stk + i
    lbu t5, 0(t5)   # t5 = face_stk[i]
    slli t4, t5, 1  # t4 = face_stk[i] << 1
    add t4, t4, t5  # t4 = (face_stk[i] << 1) + face_stk[i]
    addi t5, sp, 60 # t5 = turn_stk
    add t5, t5, t3  # t5 = turn_stk + i
    lbu t5, 0(t5)   # t5 = turn_stk[i]
    add t4, t4, t5  # t4 = (face_stk[i] << 1) + face_stk[i] + turn_stk[i]
    add t5, t6, t3  # t5 = solution_path + i
    sb t4, 0(t5)    # solution_path[i] = t4

    addi t3, t3, 1              # i++
    bleu t3, a3, idfs_sol_loop  # i <= depth ?
    # solution_path filled
    addi sp, sp, 80
    li a0, 1                    # return 1
    ret
idfs_L1:
    # solution not found yet
    # 0(sp) - 23(sp): p_stk
    # 24(sp) - 47(sp): o_stk
    addi a3, a3, 1  # depth++
    slli t3, a3, 1  # t3 = depth * 2
    add t4, sp, t3  # t4 = sp + depth * 2 = p_stk + depth * 2
    sh a4, 0(t4)    # p_stk[depth] = next_p
    addi t4, sp, 24 # t4 = sp + 24
    add t4, t4, t3  # t4 = sp + 24 + depth * 2
    sh a5, 0(t4)    # o_stk[depth] = next_o
    j idfs_enter_level
idfs_resume_turn:
    addi t2, t2, 1              # ++turn
    bleu t2, a0, idfs_turn_loop # if turn <= 2, branch
idfs_next_face:
    addi t0, t0, 1              # ++face
    bleu t0, a0, idfs_face_loop # if face <=2, branch

    addi a3, a3, -1                     # --depth
    blt a3, zero, idfs_search_failed    # if depth < 0, return 0
    addi a1, a1, 1                      # h_limit + 1 since depth decreased by 1

    # 0(sp) - 23(sp): p_stk
    # 24(sp) - 47(sp): o_stk
    # 48(sp) - 59(sp): face_stk
    # 60(sp) - 71(sp): turn_stk
    addi t3, sp, 48 # t3 = sp + 48 = face_stk
    add t3, t3, a3  # t3 = face_stk + depth
    lbu t0, 0(t3)   # t0 = face = face_stk[depth]
    addi t3, sp, 60 # t3 = sp + 60 = turn_stk
    add t3, t3, a3  # t3 = turn_stk + depth
    lbu t2, 0(t3)   # t2 = turn = turn_stk[depth]
    addi t3, a3, 1  # t3 = depth + 1
    slli t3, t3, 1  # t3 = (depth + 1) * 2
    add t4, sp, t3  # t4 = p_stk + (depth + 1) * 2
    lhu a4, 0(t4)   # a4 = next_p = p_stkp[depth + 1]
    addi t3, t3, 24 # t3 = 24 + (depth + 1) * 2
    add t3, sp, t3  # t3 = sp + 24 + (depth + 1) * 2 = o_stk + (depth + 1) * 2
    lhu a5, 0(t3)   # a5 = next_o = o_stk[depth + 1]

    la a6, next_p_face_ptr
    la a7, next_o_face_ptr
    slli t4, t0, 2              # t4 = face * 4
    add a6, a6, t4              # a6 = next_p_face_ptr + face
    add a7, a7, t4              # a7 = next_o_face_ptr + face
    lw  a6, 0(a6)               # a6 = next_p_face_ptr[face]
    lw  a7, 0(a7)               # a7 = next_o_face_ptr[face]

    li t1, 0xFF                 # t1 = last_face = 0xFF
    blez a3, idfs_resume_turn   # if depth <= 0, b, then last_face = 0xFF
    addi t3, a3, -1
    add t3, t3, sp
    lbu t1, 48(t3)              # t1 = last_face = face_stk[depth - 1]
    j idfs_resume_turn
idfs_search_failed:
    addi sp, sp, 80
    li a0, 0
    ret
.size   idfs, .-idfs
