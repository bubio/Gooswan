// Versioned, deterministic whole-machine states. No host I/O.
// This fixed layout is intentionally explicit: bump STATE_VERSION whenever
// its fields change. Audio already handed to the host is never restored.
namespace core;

let STATE_VERSION: u64 = 1;
let STATE_MAGIC:   u64 = 0x3154534E41575347;
struct MachineState {
    mem:                  u8[1048576],
    r:                    u16[8],
    seg:                  u16[4],
    ip:                   u16,
    flags:                u16,
    dbg_taken:            bool,
    dbg_back:             bool,
    dbg_head:             i64,
    xfer_flag:            bool,
    dbg_odd:              bool,
    dbg_disp:             i64,
    dbg_shift_cnt:        i64,
    fault_chg:            i64,
    fault_base:           i64,
    cyc_in_exec:          bool,
    d_valid:              bool,
    d_rm:                 i64,
    seg_override:         i64,
    rep_prefix:           i64,
    cpu_v20:              bool,
    cpu_mz:               bool,
    dbg_op:               i64,
    dbg_ip:               i64,
    d_reg:                i64,
    d_isreg:              bool,
    d_regidx:             i64,
    d_addr:               i64,
    d_segbase:            i64,
    d_off:                i64,
    irq_inhibit:          i64,
    trap_inhibit:         i64,
    irq_ret_override:     i64,
    unit_cfof:            i64,
    cpu_halted:           bool,
    ws_mode:              bool,
    sram:                 u8[524288],
    sram_size:            i64,
    bk_ram:               i64,
    bk_rom0:              i64,
    bk_rom1:              i64,
    bk_linear:            i64,
    io_ports:             u8[256],
    int_cause:            i64,
    sys_ctrl1:            i64,
    last_tick:            i64,
    key_select:           i64,
    keys_state:           i64,
    ws_cycles:            i64,
    last_line:            i64,
    mapper_2003:          bool,
    bk_ram_hi:            i64,
    bk_rom0_hi:           i64,
    bk_rom1_hi:           i64,
    rom_span:             i64,
    gdma_stall:           i64,
    sdma_running:         bool,
    sdma_clock:           i64,
    sdma_source:          i64,
    sdma_counter:         i64,
    sdma_source_shadow:   i64,
    sdma_counter_shadow:  i64,
    ws_prev_keys:         i64,
    ws_total:             i64,
    ws_unsupported:       bool,
    ws_frame_carry:       i64,
    model_mono:           bool,
    model_forced:         i64,
    fb:                   u16[32256],
    spr_any_c:            i64[224],
    spr_any_on:           bool[224],
    spr_front_c:          i64[224],
    spr_front_on:         bool[224],
    spr_latch:            i64[384],
    spr_latch_n:          i64,
    spr_next:             i64[384],
    spr_next_n:           i64,
    spr_latch_valid:      bool,
    ee_data:              u8[4096],
    ee_input:             i64[2],
    ee_output:            i64[2],
    ee_wen:               bool[2],
    ee_size:              i64[2],
    ee_bits:              i64[2],
    cart_eeprom:          bool,
    ie_done:              bool,
    ie_delay:             i64,
    ie_fault:             bool,
    lfsr:                 i64,
    noise_acc:            i64,
    ch_period:            i64[4],
    ch_idx:               i64[4],
    ch_sample:            i64[4],
    sweep_ctr:            i64,
    sweep_step:           i64,
    fast_primed:          bool,
    sweep_prepaid:        i64,
    aud_acc:              i64,
    voice_lp_prev:        i64,
    voice_level:          i64,
    rtc_present:          bool,
    rtc_reg:              i64[10],
    rtc_cmd:              i64,
    rtc_index:            i64,
    rtc_remaining:        i64,
    rtc_unsupported_busy: bool,
    rtc_cycles:           i64,
    boot_image:           u8[65536],
    boot_size:            i64,
    boot_enabled:         bool,
}

fn save_state_bytes() -> u8[>..] {
    var snap: MachineState[1] = [default<MachineState>(); 1];
    snap[0].mem = mem;
    snap[0].r = r;
    snap[0].seg = seg;
    snap[0].ip = ip;
    snap[0].flags = flags;
    snap[0].dbg_taken = dbg_taken;
    snap[0].dbg_back = dbg_back;
    snap[0].dbg_head = dbg_head;
    snap[0].xfer_flag = xfer_flag;
    snap[0].dbg_odd = dbg_odd;
    snap[0].dbg_disp = dbg_disp;
    snap[0].dbg_shift_cnt = dbg_shift_cnt;
    snap[0].fault_chg = fault_chg;
    snap[0].fault_base = fault_base;
    snap[0].cyc_in_exec = cyc_in_exec;
    snap[0].d_valid = d_valid;
    snap[0].d_rm = d_rm;
    snap[0].seg_override = seg_override;
    snap[0].rep_prefix = rep_prefix;
    snap[0].cpu_v20 = cpu_v20;
    snap[0].cpu_mz = cpu_mz;
    snap[0].dbg_op = dbg_op;
    snap[0].dbg_ip = dbg_ip;
    snap[0].d_reg = d_reg;
    snap[0].d_isreg = d_isreg;
    snap[0].d_regidx = d_regidx;
    snap[0].d_addr = d_addr;
    snap[0].d_segbase = d_segbase;
    snap[0].d_off = d_off;
    snap[0].irq_inhibit = irq_inhibit;
    snap[0].trap_inhibit = trap_inhibit;
    snap[0].irq_ret_override = irq_ret_override;
    snap[0].unit_cfof = unit_cfof;
    snap[0].cpu_halted = cpu_halted;
    snap[0].ws_mode = ws_mode;
    snap[0].sram = sram;
    snap[0].sram_size = sram_size;
    snap[0].bk_ram = bk_ram;
    snap[0].bk_rom0 = bk_rom0;
    snap[0].bk_rom1 = bk_rom1;
    snap[0].bk_linear = bk_linear;
    snap[0].io_ports = io_ports;
    snap[0].int_cause = int_cause;
    snap[0].sys_ctrl1 = sys_ctrl1;
    snap[0].last_tick = last_tick;
    snap[0].key_select = key_select;
    snap[0].keys_state = keys_state;
    snap[0].ws_cycles = ws_cycles;
    snap[0].last_line = last_line;
    snap[0].mapper_2003 = mapper_2003;
    snap[0].bk_ram_hi = bk_ram_hi;
    snap[0].bk_rom0_hi = bk_rom0_hi;
    snap[0].bk_rom1_hi = bk_rom1_hi;
    snap[0].rom_span = rom_span;
    snap[0].gdma_stall = gdma_stall;
    snap[0].sdma_running = sdma_running;
    snap[0].sdma_clock = sdma_clock;
    snap[0].sdma_source = sdma_source;
    snap[0].sdma_counter = sdma_counter;
    snap[0].sdma_source_shadow = sdma_source_shadow;
    snap[0].sdma_counter_shadow = sdma_counter_shadow;
    snap[0].ws_prev_keys = ws_prev_keys;
    snap[0].ws_total = ws_total;
    snap[0].ws_unsupported = ws_unsupported;
    snap[0].ws_frame_carry = ws_frame_carry;
    snap[0].model_mono = model_mono;
    snap[0].model_forced = model_forced;
    snap[0].fb = fb;
    snap[0].spr_any_c = spr_any_c;
    snap[0].spr_any_on = spr_any_on;
    snap[0].spr_front_c = spr_front_c;
    snap[0].spr_front_on = spr_front_on;
    snap[0].spr_latch = spr_latch;
    snap[0].spr_latch_n = spr_latch_n;
    snap[0].spr_next = spr_next;
    snap[0].spr_next_n = spr_next_n;
    snap[0].spr_latch_valid = spr_latch_valid;
    snap[0].ee_data = ee_data;
    snap[0].ee_input = ee_input;
    snap[0].ee_output = ee_output;
    snap[0].ee_wen = ee_wen;
    snap[0].ee_size = ee_size;
    snap[0].ee_bits = ee_bits;
    snap[0].cart_eeprom = cart_eeprom;
    snap[0].ie_done = ie_done;
    snap[0].ie_delay = ie_delay;
    snap[0].ie_fault = ie_fault;
    snap[0].lfsr = lfsr;
    snap[0].noise_acc = noise_acc;
    snap[0].ch_period = ch_period;
    snap[0].ch_idx = ch_idx;
    snap[0].ch_sample = ch_sample;
    snap[0].sweep_ctr = sweep_ctr;
    snap[0].sweep_step = sweep_step;
    snap[0].fast_primed = fast_primed;
    snap[0].sweep_prepaid = sweep_prepaid;
    snap[0].aud_acc = aud_acc;
    snap[0].voice_lp_prev = voice_lp_prev;
    snap[0].voice_level = voice_level;
    snap[0].rtc_present = rtc_present;
    snap[0].rtc_reg = rtc_reg;
    snap[0].rtc_cmd = rtc_cmd;
    snap[0].rtc_index = rtc_index;
    snap[0].rtc_remaining = rtc_remaining;
    snap[0].rtc_unsupported_busy = rtc_unsupported_busy;
    snap[0].rtc_cycles = rtc_cycles;
    snap[0].boot_image = boot_image;
    snap[0].boot_size = boot_size;
    snap[0].boot_enabled = boot_enabled;
    let payload = to_bytes(snap);
    let header: u64[4] = [STATE_MAGIC, STATE_VERSION, hash(rom[..]), hash(payload[..])];
    var out = to_bytes(header);
    for b in payload { out.push(b); }
    return out;
}

// Validate the entire container before changing any live machine state.
fn load_state_bytes(data: const u8[:]) -> bool {
    if data.len < 33 || data.len > 2000000 { return false; }
    let header, header_ok = from_bytes<u64[>..]>(data[..33]);
    if !header_ok || header.len != 4 { return false; }
    if header[0] != STATE_MAGIC || header[1] != STATE_VERSION { return false; }
    if header[2] != hash(rom[..]) || header[3] != hash(data[33..]) { return false; }
    let snap, ok = from_bytes<MachineState[>..]>(data[33..]);
    if !ok || snap.len != 1 { return false; }
    if snap[0].sram_size < 0 || snap[0].sram_size > 524288 { return false; }
    if snap[0].boot_size < 0 || snap[0].boot_size > 65536 { return false; }
    if snap[0].spr_latch_n < 0 || snap[0].spr_latch_n > 128 { return false; }
    if snap[0].spr_next_n < 0 || snap[0].spr_next_n > 128 { return false; }
    mem = snap[0].mem;
    r = snap[0].r;
    seg = snap[0].seg;
    ip = snap[0].ip;
    flags = snap[0].flags;
    dbg_taken = snap[0].dbg_taken;
    dbg_back = snap[0].dbg_back;
    dbg_head = snap[0].dbg_head;
    xfer_flag = snap[0].xfer_flag;
    dbg_odd = snap[0].dbg_odd;
    dbg_disp = snap[0].dbg_disp;
    dbg_shift_cnt = snap[0].dbg_shift_cnt;
    fault_chg = snap[0].fault_chg;
    fault_base = snap[0].fault_base;
    cyc_in_exec = snap[0].cyc_in_exec;
    d_valid = snap[0].d_valid;
    d_rm = snap[0].d_rm;
    seg_override = snap[0].seg_override;
    rep_prefix = snap[0].rep_prefix;
    cpu_v20 = snap[0].cpu_v20;
    cpu_mz = snap[0].cpu_mz;
    dbg_op = snap[0].dbg_op;
    dbg_ip = snap[0].dbg_ip;
    d_reg = snap[0].d_reg;
    d_isreg = snap[0].d_isreg;
    d_regidx = snap[0].d_regidx;
    d_addr = snap[0].d_addr;
    d_segbase = snap[0].d_segbase;
    d_off = snap[0].d_off;
    irq_inhibit = snap[0].irq_inhibit;
    trap_inhibit = snap[0].trap_inhibit;
    irq_ret_override = snap[0].irq_ret_override;
    unit_cfof = snap[0].unit_cfof;
    cpu_halted = snap[0].cpu_halted;
    ws_mode = snap[0].ws_mode;
    sram = snap[0].sram;
    sram_size = snap[0].sram_size;
    bk_ram = snap[0].bk_ram;
    bk_rom0 = snap[0].bk_rom0;
    bk_rom1 = snap[0].bk_rom1;
    bk_linear = snap[0].bk_linear;
    io_ports = snap[0].io_ports;
    int_cause = snap[0].int_cause;
    sys_ctrl1 = snap[0].sys_ctrl1;
    last_tick = snap[0].last_tick;
    key_select = snap[0].key_select;
    keys_state = snap[0].keys_state;
    ws_cycles = snap[0].ws_cycles;
    last_line = snap[0].last_line;
    mapper_2003 = snap[0].mapper_2003;
    bk_ram_hi = snap[0].bk_ram_hi;
    bk_rom0_hi = snap[0].bk_rom0_hi;
    bk_rom1_hi = snap[0].bk_rom1_hi;
    rom_span = snap[0].rom_span;
    gdma_stall = snap[0].gdma_stall;
    sdma_running = snap[0].sdma_running;
    sdma_clock = snap[0].sdma_clock;
    sdma_source = snap[0].sdma_source;
    sdma_counter = snap[0].sdma_counter;
    sdma_source_shadow = snap[0].sdma_source_shadow;
    sdma_counter_shadow = snap[0].sdma_counter_shadow;
    ws_prev_keys = snap[0].ws_prev_keys;
    ws_total = snap[0].ws_total;
    ws_unsupported = snap[0].ws_unsupported;
    ws_frame_carry = snap[0].ws_frame_carry;
    model_mono = snap[0].model_mono;
    model_forced = snap[0].model_forced;
    fb = snap[0].fb;
    spr_any_c = snap[0].spr_any_c;
    spr_any_on = snap[0].spr_any_on;
    spr_front_c = snap[0].spr_front_c;
    spr_front_on = snap[0].spr_front_on;
    spr_latch = snap[0].spr_latch;
    spr_latch_n = snap[0].spr_latch_n;
    spr_next = snap[0].spr_next;
    spr_next_n = snap[0].spr_next_n;
    spr_latch_valid = snap[0].spr_latch_valid;
    ee_data = snap[0].ee_data;
    ee_input = snap[0].ee_input;
    ee_output = snap[0].ee_output;
    ee_wen = snap[0].ee_wen;
    ee_size = snap[0].ee_size;
    ee_bits = snap[0].ee_bits;
    cart_eeprom = snap[0].cart_eeprom;
    ie_done = snap[0].ie_done;
    ie_delay = snap[0].ie_delay;
    ie_fault = snap[0].ie_fault;
    lfsr = snap[0].lfsr;
    noise_acc = snap[0].noise_acc;
    ch_period = snap[0].ch_period;
    ch_idx = snap[0].ch_idx;
    ch_sample = snap[0].ch_sample;
    sweep_ctr = snap[0].sweep_ctr;
    sweep_step = snap[0].sweep_step;
    fast_primed = snap[0].fast_primed;
    sweep_prepaid = snap[0].sweep_prepaid;
    aud_acc = snap[0].aud_acc;
    voice_lp_prev = snap[0].voice_lp_prev;
    voice_level = snap[0].voice_level;
    rtc_present = snap[0].rtc_present;
    rtc_reg = snap[0].rtc_reg;
    rtc_cmd = snap[0].rtc_cmd;
    rtc_index = snap[0].rtc_index;
    rtc_remaining = snap[0].rtc_remaining;
    rtc_unsupported_busy = snap[0].rtc_unsupported_busy;
    rtc_cycles = snap[0].rtc_cycles;
    boot_image = snap[0].boot_image;
    boot_size = snap[0].boot_size;
    boot_enabled = snap[0].boot_enabled;
    aud_buf = [];
    return true;
}
