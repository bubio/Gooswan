namespace core;

var serial_pass: i64 = 0;
var serial_fail: i64 = 0;

fn serial_check(name: const u8[:], passed: bool) {
    if passed { serial_pass += 1; }
    else { serial_fail += 1; print("Serial FAIL ", name); }
}

fn serial_test() {
    var output: u8[>..] = [];
    serial_attach();
    port_wr(INT_ENABLE, 9);
    port_wr(SERIAL_STATUS, 0x80);
    serial_check("idle status", port_rd(SERIAL_STATUS) == 0x84);
    serial_check("idle transmit IRQ", port_rd(INT_CAUSE) == SERIAL_TX_IRQ);
    port_wr(INT_CAUSE_CLEAR, 1);
    port_wr(SERIAL_DATA, 0xAD);
    serial_check("busy status", port_rd(SERIAL_STATUS) == 0x80);
    serial_check("waiting for both players", serial_take_output(output) && output.len == 0);
    ws_cycles = 3200; serial_tick();
    serial_check("transmit completes in the lobby", port_rd(SERIAL_STATUS) == 0x84);
    serial_check("lobby discards transmitted bytes", serial_take_output(output) && output.len == 0);

    serial_start(2);
    port_wr(SERIAL_STATUS, 0xC0);
    port_wr(SERIAL_DATA, 0x5A);
    ws_cycles = 3999; serial_tick();
    serial_check("fast transmit still busy one cycle early", port_rd(SERIAL_STATUS) == 0xC0);
    ws_cycles = 4000; serial_tick();
    serial_check("timestamp and speed sent on completion", serial_take_output(output) && output.len == 6
        && output[0] == 4 && output[1] == 1 && output[4] == 0x5A && output[5] == 1);

    let records: u8[12] = [0xF0, 0xFF, 0xFF, 0xFF, 0xA5, 1, 0x01, 0, 0, 0, 0xFF, 1];
    serial_check("reject malformed records", !serial_receive(records[..5]));
    serial_check("accept wrapped timestamps", serial_receive(records[..]));
    let first = ws_cycles + SERIAL_JITTER;
    ws_cycles = first - 1; serial_tick();
    serial_check("jitter buffer delays first byte", port_rd(SERIAL_STATUS) == 0xC4);
    ws_cycles = first; serial_tick();
    serial_check("receive-ready status", port_rd(SERIAL_STATUS) == 0xC5);
    serial_check("receive-ready IRQ", (port_rd(INT_CAUSE) & SERIAL_RX_IRQ) != 0);
    ws_cycles = first + 800; serial_tick();
    serial_check("overrun reported", port_rd(SERIAL_STATUS) == 0xC7);
    serial_check("older byte retained and read clears ready", port_rd(SERIAL_DATA) == 0xA5 && port_rd(SERIAL_STATUS) == 0xC6);
    port_wr(INT_CAUSE_CLEAR, SERIAL_RX_IRQ);
    serial_check("read then acknowledge clears IRQ", (port_rd(INT_CAUSE) & SERIAL_RX_IRQ) == 0);
    port_wr(SERIAL_STATUS, 0xE0);
    serial_check("overrun reset", port_rd(SERIAL_STATUS) == 0xC4);

    serial_attach(); serial_start(3);
    serial_receive(records[..]);
    ws_cycles += SERIAL_JITTER; serial_tick();
    ws_cycles += 800; serial_tick();
    serial_check("room can select newest byte on overrun", port_rd(SERIAL_DATA) == 0xFF);
    serial_check("connected state cannot be loaded or saved", save_state_bytes().len == 0 && !load_state_bytes(output[..]));
    serial_detach();
    serial_check("disconnected receive latch reads empty", port_rd(SERIAL_DATA) == 0);
    print("Serial: ", serial_pass, " passed, ", serial_fail, " failed");
}
