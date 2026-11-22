// V30MZ instruction cycle estimates fitted against WSTimingTest.
namespace core;

var cyc_tab:       i64[256] = [0; 256]; // per-opcode cycle estimates for the WS timing model (fitted against WSTimingTest)
var dbg_taken:     bool     = false; // last branch outcome, for the cycle estimator
var dbg_back:      bool     = false; // last branch jumped backward
var dbg_head:      i64      = 0; // target offset of the last taken relative branch
var xfer_flag:     bool     = false; // a control transfer already executed in the current loop iteration (the loop tail then costs +2: second prefetch flush)
var dbg_odd:       bool     = false; // last relative branch landed on an odd offset
var dbg_disp:      i64      = 0; // displacement of the last relative branch (loop span = -disp)
var dbg_shift_cnt: i64      = 0; // effective shift count of the last shift/rotate
var fault_chg:     i64      = 0; // interrupt-entry charge when the last instruction faulted (set in do_int)
var fault_base:    i64      = 0; // partial-execution cost of the faulting instruction
var cyc_in_exec:   bool     = false; // true while exec_one runs under the WS runner
var d_valid:       bool     = false; // a ModRM was decoded for the current instruction
var d_rm:          i64      = 0; // rm field of the current ModRM
// Base cycle count per opcode byte for the WS timing model: the cost
// of the register / simplest form. est_cycles adds the form-dependent
// parts (memory operands, EA premiums, branch outcome, REP counts) on
// top. All values are fitted to WSTimingTest's per-instruction pages
// (docs/testing.md#known-timing-differences). Unmeasured opcodes default to 4.
fn init_cyc() {
    for i in 256 { cyc_tab[i] = 4; }
    for i in 0x40 { cyc_tab[i] = 3; }  // ALU block; form splits applied in est_cycles
    cyc_tab[0x06] = 2; cyc_tab[0x0E] = 2; cyc_tab[0x16] = 2; cyc_tab[0x1E] = 2;
    cyc_tab[0x07] = 3; cyc_tab[0x17] = 3; cyc_tab[0x1F] = 3;
    cyc_tab[0x0F] = 1; cyc_tab[0x27] = 10; cyc_tab[0x2F] = 11; cyc_tab[0x37] = 10; cyc_tab[0x3F] = 10;
    for i in 0x10 { cyc_tab[0x40 + i] = 1; cyc_tab[0x50 + i] = 1; }
    for i in 8 { cyc_tab[0x58 + i] = 1; cyc_tab[0xB0 + i] = 1; cyc_tab[0xB8 + i] = 1; }
    cyc_tab[0x60] = 9; cyc_tab[0x61] = 9; cyc_tab[0x62] = 14;
    cyc_tab[0x63] = 1; cyc_tab[0x64] = 1; cyc_tab[0x65] = 1; cyc_tab[0x66] = 1; cyc_tab[0x67] = 1;
    cyc_tab[0x68] = 1; cyc_tab[0x6A] = 1; cyc_tab[0x6C] = 5; cyc_tab[0x6D] = 5; cyc_tab[0x6E] = 5; cyc_tab[0x6F] = 5;
    for i in 4 { cyc_tab[0x80 + i] = 3; }
    cyc_tab[0x84] = 2; cyc_tab[0x85] = 2; cyc_tab[0x86] = 5; cyc_tab[0x87] = 5;
    cyc_tab[0x88] = 1; cyc_tab[0x89] = 1; cyc_tab[0x8A] = 1; cyc_tab[0x8B] = 1;
    cyc_tab[0x8C] = 1; cyc_tab[0x8D] = 1; cyc_tab[0x8F] = 3;
    cyc_tab[0x90] = 1;
    for i in 7 { cyc_tab[0x91 + i] = 3; }
    cyc_tab[0x98] = 1; cyc_tab[0x99] = 1; cyc_tab[0x9A] = 8; cyc_tab[0x9B] = 10; cyc_tab[0x9C] = 2; cyc_tab[0x9D] = 3; cyc_tab[0x9E] = 4; cyc_tab[0x9F] = 2;
    for i in 4 { cyc_tab[0xA0 + i] = 1; }
    cyc_tab[0xA4] = 5; cyc_tab[0xA5] = 5; cyc_tab[0xA6] = 6; cyc_tab[0xA7] = 6; cyc_tab[0xA8] = 1; cyc_tab[0xA9] = 1;
    cyc_tab[0xAA] = 3; cyc_tab[0xAB] = 3; cyc_tab[0xAC] = 3; cyc_tab[0xAD] = 3; cyc_tab[0xAE] = 4; cyc_tab[0xAF] = 4;
    cyc_tab[0xC2] = 4; cyc_tab[0xC3] = 4; cyc_tab[0xC4] = 6; cyc_tab[0xC5] = 6; cyc_tab[0xC6] = 1; cyc_tab[0xC7] = 1;
    cyc_tab[0xC8] = 8; cyc_tab[0xC9] = 3; cyc_tab[0xCA] = 7; cyc_tab[0xCB] = 6; cyc_tab[0xCC] = 41; cyc_tab[0xCD] = 42; cyc_tab[0xCE] = 6; cyc_tab[0xCF] = 8;
    cyc_tab[0xD4] = 16; cyc_tab[0xD5] = 6; cyc_tab[0xD6] = 8; cyc_tab[0xD7] = 5;
    for i in 8 { cyc_tab[0xD8 + i] = 1; }
    cyc_tab[0xE4] = 7; cyc_tab[0xE5] = 7; cyc_tab[0xE6] = 7; cyc_tab[0xE7] = 7; cyc_tab[0xEC] = 5; cyc_tab[0xED] = 5; cyc_tab[0xEE] = 5; cyc_tab[0xEF] = 5;
    cyc_tab[0xE8] = 3; cyc_tab[0xE9] = 2; cyc_tab[0xEA] = 5; cyc_tab[0xEB] = 2;
    cyc_tab[0xF1] = 41; cyc_tab[0xF4] = 12; cyc_tab[0xF5] = 4; cyc_tab[0xF6] = 5; cyc_tab[0xF7] = 5; cyc_tab[0xFE] = 3; cyc_tab[0xFF] = 5;
    cyc_tab[0xF8] = 4; cyc_tab[0xF9] = 4; cyc_tab[0xFA] = 4; cyc_tab[0xFB] = 4; cyc_tab[0xFC] = 4; cyc_tab[0xFD] = 4;
}

// Extra cost of a two-register EA ([bx+si] style forms) over a one-register
// or direct EA, per WSTimingTest's addressing page. LEA/LES/LDS/POP-mem pay
// only 1; most other ModRM ops pay 2.
fn ea_premium(op: i64) -> i64 {
    if !d_valid || d_isreg { return 0; }
    if d_rm > 3 { return 0; }
    if op >= 0xD8 && op <= 0xDF { return 0; }
    if op == 0x8D || op == 0xC4 || op == 0xC5 || op == 0x8F { return 1; }
    return 2;
}

fn cyc_alu(op: i64) -> i64 {
    let f: i64 = op & 7;
    if f >= 6 { return cyc_tab[op]; }  // PUSH/POP segment
    if f >= 4 { return 1; }  // accumulator, immediate
    if op >= 0x38 { if d_isreg { return 1; } return 2 + ea_premium(op); }  // CMP has no writeback
    if f <= 1 { if d_isreg { return 1; } return 3 + ea_premium(op); }  // r/m destination (read-modify-write)
    if d_isreg { return 1; } return 2 + ea_premium(op);  // register destination, memory source
}

fn cyc_f6f7(op: i64) -> i64 {
    if d_reg == 0 { return 2; }
    if d_reg == 1 { return 1; }
    if d_reg == 2 || d_reg == 3 { return 3; }
    if d_reg == 4 || d_reg == 5 { return 4; }
    if d_reg == 6 { if op == 0xF6 { return 16; } return 24; }
    if d_reg == 7 { if op == 0xF6 { return 18; } return 25; }
    return 5;
}

fn cyc_ff() -> i64 {
    if d_reg == 0 || d_reg == 1 { if d_isreg { return 1; } return 3; }
    if d_reg == 2 { return 4; }
    if d_reg == 3 { return 12; }
    if d_reg == 4 { return 4; }
    if d_reg == 5 { return 8; }
    if d_reg == 6 { return 2; }
    return 1;
}

fn cyc_fe() -> i64 {
    if d_reg == 0 || d_reg == 1 { if d_isreg { return 1; } return 3; }
    if d_reg == 6 { return 2; }
    if d_reg >= 2 && d_reg <= 5 { return cyc_ff(); }  // the mirrored FF transfers
    return 1;
}

fn cyc_loop(op: i64) -> i64 {
    if op == 0xE3 { return 2; }
    if !dbg_taken { return 2; }
    if dbg_back { return 6; }
    if op == 0xE2 { return 3; }
    return 4;
}

fn rep_cost(op: i64, n: i64) -> i64 {
    if n == 0 { return 5; }
    if op == 0xA4 || op == 0xA5 { return 5 + 7 * n; }
    if op == 0xA6 || op == 0xA7 { return 5 + 10 * n; }
    if op == 0xAE || op == 0xAF { return 5 + 9 * n; }
    return 5 + 6 * n;
}

// Partial-execution cost of a faulting instruction, before the 44-cycle
// interrupt entry (fitted from WSTimingTest's exception page).
fn cyc_fault_base() -> i64 {
    if dbg_op == 0xF6 || dbg_op == 0xF7 { if d_reg == 7 { return 8; } return 5; }
    if dbg_op == 0xD4 { return 4; }
    if dbg_op == 0x62 { return 9; }
    if dbg_op == 0xCE { return 1; }
    return 0;
}

// Cycles charged for the instruction exec_one just ran, from the
// decode state it left behind (dbg_op, d_*, dbg_taken/back/odd,
// dbg_shift_cnt, rep_prefix) and CX before it ran (pre_cx, for REP
// counts). A faulting instruction costs its partial work plus the
// 44-cycle entry instead.
//
// Side effect: it updates xfer_flag, which tracks whether a control
// transfer already ran in the current loop iteration (a backward
// branch that closes such a loop pays +2 for the second prefetch
// flush). port_wr also calls it mid-instruction for OUT, which never
// touches xfer_flag; any new caller must keep that in mind.
fn est_cycles(pre_cx: i64) -> i64 {
    let op: i64 = dbg_op;
    if fault_chg > 0 { xfer_flag = true; return fault_base + fault_chg; }
    var c:         i64  = 0;
    var is_tail:   bool = false;
    var sets_xfer: bool = false;
    if rep_prefix != 0 && ((op >= 0xA4 && op <= 0xAF) || (op >= 0x6C && op <= 0x6F)) {
        var n: i64 = pre_cx - r[1]; if n < 0 { n += 65536; }
        c = rep_cost(op, n);
    }
    else if op == 0xF6 || op == 0xF7 { c = cyc_f6f7(op) + ea_premium(op); }
    else if op == 0xFF { c = cyc_ff() + ea_premium(op); if d_reg >= 2 && d_reg <= 5 { sets_xfer = true; } }
    else if op == 0xFE { c = cyc_fe() + ea_premium(op); if d_reg >= 2 && d_reg <= 5 { sets_xfer = true; } }
    else if op >= 0x70 && op <= 0x7F {
        if dbg_taken {
            sets_xfer = true;
            if dbg_back { is_tail = true; c = 5; } else { c = 2; }
            if dbg_odd { c += 1; }
        } else { c = 1; }
    }
    else if op >= 0xE0 && op <= 0xE3 {
        c = cyc_loop(op);
        if dbg_taken { sets_xfer = true; if dbg_back { is_tail = true; } }
    }
    else if (op >= 0xC0 && op <= 0xC1) || (op >= 0xD0 && op <= 0xD3) { var sc: i64 = dbg_shift_cnt; if sc > 2 { sc = 2; } c = 1 + 2 * sc + ea_premium(op); }
    else if op < 0x40 { c = cyc_alu(op); }
    else if op == 0x69 || op == 0x6B { if d_isreg { c = 3; } else { c = 4 + ea_premium(op); } }
    else if op == 0x84 || op == 0x85 { if d_isreg { c = 1; } else { c = 2 + ea_premium(op); } }
    else if op == 0x86 || op == 0x87 { if d_isreg { c = 3; } else { c = 5 + ea_premium(op); } }
    else if op == 0x8E { if d_isreg { c = 2; } else { c = 3 + ea_premium(op); } }
    else if op == 0x8F { if d_isreg { c = 1; } else { c = 3 + ea_premium(op); } }
    else if op >= 0x80 && op <= 0x83 { if d_isreg { c = 1; } else { c = 3 + ea_premium(op); } }
    else if op == 0xC4 || op == 0xC5 { if d_isreg { c = 8; } else { c = 6 + ea_premium(op); } }
    else {
        c = cyc_tab[op] + ea_premium(op);
        if (op == 0xE9 || op == 0xEB) && dbg_odd { c += 1; }
        if op == 0xE8 || op == 0xE9 || op == 0xEA || op == 0xEB || op == 0x9A || op == 0xC2 || op == 0xC3 || op == 0xCA || op == 0xCB || op == 0xCF { sets_xfer = true; }
    }
    if is_tail { if xfer_flag { c += 2; } else if op >= 0x70 && op <= 0x7F && 0 - dbg_disp <= 4 { c -= 1; } xfer_flag = false; }
    else if sets_xfer { xfer_flag = true; }
    return c;
}
