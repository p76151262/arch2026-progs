#include "rubik.h"
#include <stddef.h>
#include "lut.h"

enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    STATES = PERMUTATIONS * ORIENTATIONS,
    MOVES = 9
};

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

typedef struct {
    uint16_t first;
    uint16_t second;
} u16_pair_t;

static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};
static const uint8_t move_name_len[MOVES] = {2, 3, 3, 2, 3, 3, 2, 3, 3};
static const uint16_t o_tenary_lut[6][3] = {
    {0, 243, 486}, {0, 81, 162}, {0, 27, 54}, {0, 9, 18}, {0, 3, 6}, {0, 1, 2}};
static const uint16_t p_fact_lut[7][7] = {
    {0, 720, 1440, 2160, 2880, 3600, 4320},
    {0, 120, 240, 360, 480, 600, 720},
    {0, 24, 48, 72, 96, 120, 144},
    {0, 6, 12, 18, 24, 30, 36},
    {0, 2, 4, 6, 8, 10, 12},
    {0, 1, 2, 3, 4, 5, 6},
    {0, 1, 2, 3, 4, 5, 6},
};

static u16_pair_t rank_state(const state_t *state)
{
    uint16_t p = 0, o = 0;
    for (uint8_t i = 0; i < CUBIES; i++) {
        uint8_t smaller = 0;  // Lehmer code
        for (uint8_t j = (uint8_t) (i + 1U); j < CUBIES; j++)
            smaller += (state->p[j] < state->p[i]);
        p += p_fact_lut[i][smaller];
    }

    // o = state->o[0] * 243 + state->o[1] * 81 + state->o[2] * 27 + state->o[3]
    // * 9 + state->o[4] * 3 + state->o[5] * 1;
    o = o_tenary_lut[0][state->o[0]] + o_tenary_lut[1][state->o[1]] +
        o_tenary_lut[2][state->o[2]] + o_tenary_lut[3][state->o[3]] +
        o_tenary_lut[4][state->o[4]] + o_tenary_lut[5][state->o[5]];

    u16_pair_t result = {p, o};

    return result;
}

static int valid(const state_t *state)
{
    uint8_t sum = 0;
    for (uint8_t i = 0; i < CUBIES; i++) {
        if (state->p[i] >= CUBIES || state->o[i] >= 3)
            return 0;
        for (uint8_t j = 0; j < i; j++) {
            if (state->p[j] == state->p[i])
                return 0;
        }
        sum = (uint8_t) (sum + state->o[i]);
    }

    // sum % 3 == 0
    while (sum >= 3) {
        sum -= 3;
    }

    return sum == 0;
}

static int parse_state(const char *input, state_t *state)
{
    for (int i = 0; i < 14; i++) {
        int limit = i < 7 ? 7 : 3;
        if (input[i] < '1' || input[i] > '0' + limit)
            return 0;

        *(((uint8_t *) state) + i) = (uint8_t) (input[i] - '1');
    }
    return input[14] == '\0' && valid(state);
}

static int iterative_dfs(uint16_t start_p,
                         uint16_t start_o,
                         uint8_t bound,
                         uint8_t *solution_path)
{
    if (start_p == 0 && start_o == 0)
        return 1;

    uint16_t p_stk[12];
    uint16_t o_stk[12];
    uint8_t face_stk[12];
    uint8_t turn_stk[12];

    p_stk[0] = start_p;
    o_stk[0] = start_o;
    int8_t depth = 0;
    uint8_t last_face = 0xFF;

enter_level:;
    uint8_t face = 0;
face_loop:
    if (face == last_face)  // pruning 2
        goto next_face;
    uint16_t next_p = p_stk[depth];
    uint16_t next_o = o_stk[depth];

    uint8_t turn = 0;
turn_loop:
    next_p = next_rank_p[face][next_p];
    next_o = next_rank_o[face][next_o];

    uint8_t h = h_p[next_p] > h_o[next_o] ? h_p[next_p] : h_o[next_o];
    if (depth + 1 + h <= bound) {  // pruning 1: go into next level or not
        face_stk[depth] = face;
        turn_stk[depth] = turn;

        // next_p and next_o would be updated until both reaches 0
        if (next_p == 0 && next_o == 0) {  // solution found
            for (int8_t i = 0; i <= depth; i++)
                solution_path[i] =
                    (face_stk[i] << 1) + face_stk[i] + turn_stk[i];
            return 1;
        }

        // solution not found yet
        // the next_* values calculated at depth d is the start_* values
        // for the depth d+1, and that are stored in *_stk[d+1]
        // *_stk[d] are not toched by depth d
        depth++;
        p_stk[depth] = next_p;
        o_stk[depth] = next_o;
        last_face = face;
        goto enter_level;
    }

resume_turn:
    if (++turn <= 2)
        goto turn_loop;

next_face:
    if (++face <= 2)
        goto face_loop;

    // 3 faces are exhausted, backtrack 1 level up
    if (--depth < 0)
        return 0;  // nothing to backtrack (root node)

    // resume values from stack for backtrack
    face = face_stk[depth];
    turn = turn_stk[depth];
    next_p = p_stk[depth + 1];  // retrieve next_* from *_stk[d+1]
    next_o = o_stk[depth + 1];
    last_face = depth > 0 ? face_stk[depth - 1] : 0xFF;
    goto resume_turn;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    state_t parsed_state;
    uint8_t solution_path[11] = {0};

    if (cap == 0) {
        return -2;
    }

    if (!parse_state(state, &parsed_state)) {
        return -1;
    }

    const u16_pair_t rank = rank_state(&parsed_state);
    const uint16_t start_p = rank.first;
    const uint16_t start_o = rank.second;

    uint8_t start_bound =
        h_p[start_p] > h_o[start_o] ? h_p[start_p] : h_o[start_o];

    for (uint8_t bound = start_bound; bound <= 11; bound++) {
        if (iterative_dfs(start_p, start_o, bound,
                          solution_path)) {  // solution found under bound
            if (bound == 0) {
                if (cap == 0) {
                    return -2;
                }

                out[0] = '\0';
                return 0;
            }

            char temp[33];
            size_t str_len = 0;  // including the terminator '\0'
            for (int8_t i = 0; i < bound; i++) {
                const uint8_t move_id = solution_path[i];
                const char *move_str = move_names[move_id];
                const uint8_t move_str_len = move_name_len[move_id];

                temp[str_len++] = move_str[0];
                if (move_str_len == 3) {
                    temp[str_len++] = move_str[1];
                }
                temp[str_len++] = ' ';
            }
            temp[str_len - 1] = '\0';

            // buffer size too small
            if (str_len > cap) {
                if (cap >= 1)
                    out[0] = '\0';

                return -2;
            }

            for (size_t i = 0; i < str_len; i++) {
                out[i] = temp[i];
            }

            return bound;
        }
    }

    return -1;
}
