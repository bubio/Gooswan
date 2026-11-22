// General-purpose DMA and sound DMA registers and timing.
namespace core;

fn dma_read_word(port: i64) -> i64 {
    return io_ports[port] | ((io_ports[port + 1] as i64) << 8);
}

fn dma_write_word(port: i64, value: i64) {
    io_ports[port] = (value & 0xFF) as! u8;
    io_ports[port + 1] = ((value >> 8) & 0xFF) as! u8;
}

fn dma_read_address(port: i64) -> i64 {
    return dma_read_word(port) | (((io_ports[port + 2] as i64) & 0x0F) << 16);
}

fn dma_write_address(port: i64, value: i64) {
    dma_write_word(port, value);
    io_ports[port + 2] = ((value >> 16) & 0x0F) as! u8;
}

var gdma_stall: i64 = 0;

fn run_gdma() {
    var src = dma_read_address(GDMA_SRC_LO);
    var dst = dma_read_word(GDMA_DST);
    var len = dma_read_word(GDMA_LEN);
    let step: i64 = if (io_ports[GDMA_CTRL] & 0x40) != 0 { -1 } else { 1 };
    var moved: i64 = 0;
    while len > 0 {
        if src >= 0x10000 && src < 0x20000 { break; }
        if src >= 0x80000 && src < 0x90000 && (sys_ctrl1 & 0x08) != 0 { break; }
        wb8(dst & 0xFFFF, rd8(src));  // through the bus: mono drops writes above 16 KB (Swanium write_wram)
        src = (src + step) & 0xFFFFF;
        dst = (dst + step) & 0xFFFF;
        len -= 1;
        moved += 1;
    }
    dma_write_address(GDMA_SRC_LO, src);
    dma_write_word(GDMA_DST, dst);
    dma_write_word(GDMA_LEN, len);
    io_ports[GDMA_CTRL] = ((io_ports[GDMA_CTRL] as i64) & 0x7F) as! u8;
    if moved > 0 { gdma_stall += 5 + moved; }  // charged to the OUT that started it (ws_frame), so the frame still spans 40,704 cycles
}

// ---- Sound DMA (colour only): feeds the voice data latch (port 0x89)
// from memory on the 24 kHz cadence (one sample per 128 CPU cycles x
// the rate divider), following Swanium's bus model. The register
// shadows live in ports 0x4A-0x52; source/counter latch into the
// engine (with shadows for REPEAT) when a stopped engine first ticks
// with ENABLE set, and are written back to the ports on every step.
var sdma_running:        bool = false;
var sdma_clock:          i64  = 0;
var sdma_source:         i64  = 0;
var sdma_counter:        i64  = 0;
var sdma_source_shadow:  i64  = 0;
var sdma_counter_shadow: i64  = 0;

fn sdma_writeback() {
    dma_write_address(SDMA_SRC_LO, sdma_source);
    dma_write_address(SDMA_LEN_LO, sdma_counter);
}

fn sdma_step() {
    let ctrl: i64 = io_ports[SDMA_CTRL];
    if (ctrl & 0x04) != 0 { io_ports[SND_VOICE_SAMPLE] = 0; voice_feed(0); return; }  // HOLD: latch silence, pointers stay
    let sb: i64 = rd8(sdma_source);
    io_ports[SND_VOICE_SAMPLE] = sb as! u8; voice_feed(sb);
    if (ctrl & 0x40) != 0 { sdma_source = (sdma_source - 1) & 0xFFFFF; } else { sdma_source = (sdma_source + 1) & 0xFFFFF; }
    sdma_counter = (sdma_counter - 1) & 0xFFFFF;
    if sdma_counter == 0 {
        if (ctrl & 0x08) != 0 { sdma_source = sdma_source_shadow; sdma_counter = sdma_counter_shadow; }
        else { io_ports[SDMA_CTRL] = ((io_ports[SDMA_CTRL] as i64) & 0x7F) as! u8; sdma_running = false; }
    }
    sdma_writeback();
}

fn sdma_tick(dc: i64) {
    if model_mono || ((io_ports[SDMA_CTRL] as i64) & 0x80) == 0 { sdma_running = false; sdma_clock = 0; return; }
    if !sdma_running {
        let counter: i64 = dma_read_address(SDMA_LEN_LO);
        if counter == 0 { io_ports[SDMA_CTRL] = ((io_ports[SDMA_CTRL] as i64) & 0x7F) as! u8; return; }  // nothing to send: ENABLE self-clears
        sdma_source = dma_read_address(SDMA_SRC_LO);
        sdma_counter = counter;
        sdma_source_shadow = sdma_source;
        sdma_counter_shadow = sdma_counter;
        sdma_clock = 0;
        sdma_running = true;
    }
    sdma_clock += dc;
    let rate_bits: i64 = (io_ports[SDMA_CTRL] as i64) & 3;
    let rate:      i64 = if rate_bits == 0 { 6 } else if rate_bits == 1 { 4 } else if rate_bits == 2 { 2 } else { 1 };
    let period:    i64 = 128 * rate;
    while sdma_clock >= period {
        sdma_clock -= period;
        sdma_step();
        if !sdma_running { sdma_clock = 0; break; }
    }
}
