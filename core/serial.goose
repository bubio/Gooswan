// EXT port and the clocked byte stream used by a connected link cable.
namespace core;

let SERIAL_TX_IRQ:      i64 = 1;
let SERIAL_RX_IRQ:      i64 = 8;
let SERIAL_FIFO_SIZE:   i64 = 4096;
let SERIAL_RECORD_SIZE: i64 = 6;
let SERIAL_JITTER:      i64 = 30720; // 10 ms at 3.072 MHz

struct SerialArrival { clock: i64, value: u8 }
var serial_arrivals:     SerialArrival[4096] = [SerialArrival { 0, 0 }; 4096];
var serial_read_at:      i64                 = 0;
var serial_write_at:     i64                 = 0;
var serial_output:       u8[>..]             = [];
var serial_attached:     bool                = false;
var serial_linked:       bool                = false;
var serial_keep_new:     bool                = false;
var serial_room_fast:    bool                = false;
var serial_start_clock:  i64                 = 0;
var serial_send_due:     i64                 = -1;
var serial_send_data:    u8                  = 0;
var serial_recv_clock:   i64                 = -3200;
var serial_recv_data:    u8                  = 0;
var serial_has_recv:     bool                = false;
var serial_overrun:      bool                = false;
var serial_last_us:      i64                 = -1;
var serial_sender_us:    i64                 = 0;
var serial_offset:       i64                 = 0;
var serial_last_due:     i64                 = 0;
var serial_window_start: i64                 = 0;
var serial_min_slack:    i64                 = 0;
var serial_failed:       bool                = false;

fn serial_reset() {
    serial_attached = false; serial_linked = false; serial_failed = false;
    serial_read_at = 0; serial_write_at = 0; serial_output.clear();
    serial_send_due = -1; serial_recv_clock = -3200;
    serial_has_recv = false; serial_overrun = false; serial_recv_data = 0;
}

fn serial_attach() { serial_reset(); serial_attached = true; }
fn serial_detach() {
    if serial_attached { int_cause &= ~(SERIAL_TX_IRQ | SERIAL_RX_IRQ); }
    serial_reset();
    refresh_serial();
}
fn serial_start(flags: i64) {
    serial_linked = true;
    serial_keep_new = (flags & 1) != 0;
    serial_room_fast = (flags & 2) != 0;
    serial_start_clock = ws_cycles;
    serial_last_us = -1;
}

// A record contains a little-endian timestamp in microseconds, a byte and a
// speed bit. Unwrap the peer clock, anchor to local emulated time and keep
// enough queued audio-independent time to absorb packet jitter.
fn serial_receive(records: const u8[:]) -> bool {
    let count = records.len / SERIAL_RECORD_SIZE;
    if !serial_linked || records.len % SERIAL_RECORD_SIZE != 0 || count > SERIAL_FIFO_SIZE - (serial_write_at - serial_read_at) { return false; }
    for i in count {
        let at = i * SERIAL_RECORD_SIZE;
        let us = records[at] | ((records[at + 1] as i64) << 8)
            | ((records[at + 2] as i64) << 16) | ((records[at + 3] as i64) << 24);
        let first = serial_last_us < 0;
        serial_sender_us = if first { us } else { serial_sender_us + ((us - serial_last_us) & 0xFFFFFFFF) };
        serial_last_us = us;
        let sender = serial_sender_us * CPU_HZ / 1000000;
        if first {
            serial_offset = ws_cycles + SERIAL_JITTER - sender;
            serial_window_start = ws_cycles; serial_min_slack = 0;
            serial_last_due = ws_cycles;
        }
        let spacing: i64 = if (records[at + 5] & 1) != 0 { 800 } else { 3200 };
        let due = max(sender + serial_offset, serial_last_due + spacing);
        if due < ws_cycles { serial_offset += ws_cycles - due; }
        serial_last_due = max(due, ws_cycles);
        let slack = serial_last_due - ws_cycles - SERIAL_JITTER;
        serial_min_slack = min(serial_min_slack, slack);
        if ws_cycles - serial_window_start >= 2 * CPU_HZ {
            serial_offset -= max(0, min(serial_min_slack, CPU_HZ / 1000));
            serial_window_start = ws_cycles; serial_min_slack = slack;
        }
        serial_arrivals[serial_write_at % SERIAL_FIFO_SIZE] = SerialArrival { serial_last_due, records[at + 4] };
        serial_write_at += 1;
    }
    return true;
}

fn serial_take_output(out: u8[>..]&) -> bool {
    out.append(serial_output[..]); serial_output.clear();
    return !serial_failed;
}

fn serial_byte_cycles() -> i64 { return if (io_ports[SERIAL_STATUS] & 0x40) != 0 { 800 } else { 3200 }; }
fn serial_on() -> bool { return (io_ports[SERIAL_STATUS] & 0x80) != 0; }
fn serial_status() -> i64 {
    return io_ports[SERIAL_STATUS] | (if serial_has_recv { 1 } else { 0 })
        | (if serial_overrun { 2 } else { 0 }) | (if serial_on() && serial_send_due < 0 { 4 } else { 0 });
}
fn serial_read() -> i64 {
    serial_has_recv = false;
    return serial_recv_data;
}
fn serial_write(p: i64, v: i64) {
    if p == SERIAL_STATUS {
        io_ports[p] = (v & (if serial_attached { 0xC0 } else { 0xC4 })) as! u8;
        if (v & 0x20) != 0 { serial_overrun = false; }
        if !serial_on() { serial_has_recv = false; }
    } else if serial_attached {
        serial_send_data = v as! u8;
        serial_send_due = ws_cycles + serial_byte_cycles();
    }
    refresh_serial();
}

fn refresh_serial() {
    let enabled = io_ports[INT_ENABLE] as i64;
    if serial_attached {
        let levels = (if serial_send_due < 0 { SERIAL_TX_IRQ } else { 0 }) | (if serial_has_recv { SERIAL_RX_IRQ } else { 0 });
        if serial_on() { int_cause |= levels & enabled; }
    } else if model_mono && serial_on() { int_cause |= enabled & SERIAL_TX_IRQ; }
}

fn serial_tick() {
    if serial_send_due >= 0 && ws_cycles >= serial_send_due {
        if serial_linked && serial_on() {
            if serial_output.len == SERIAL_FIFO_SIZE * SERIAL_RECORD_SIZE { serial_failed = true; }
            else {
                let us = max(0, serial_send_due - serial_start_clock) * 1000000 / CPU_HZ;
                for i in 4 { serial_output.push(((us >> (i * 8)) & 0xFF) as! u8); }
                serial_output.push(serial_send_data);
                serial_output.push(if serial_room_fast { 1 } else { 0 });
            }
        }
        serial_send_due = -1;
        refresh_serial();
    }
    if serial_read_at == serial_write_at || ws_cycles - serial_recv_clock < serial_byte_cycles() { return; }
    let arrival = serial_arrivals[serial_read_at % SERIAL_FIFO_SIZE];
    if arrival.clock > ws_cycles { return; }
    serial_read_at += 1;
    serial_recv_clock = ws_cycles;
    if !serial_on() { return; }
    if serial_has_recv { serial_overrun = true; }
    if !serial_has_recv || serial_keep_new { serial_recv_data = arrival.value; }
    serial_has_recv = true;
    refresh_serial();
}
