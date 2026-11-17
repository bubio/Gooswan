// Deterministic continuation and transactional rejection, through the core API.
namespace core;
var state_pass: i64 = 0;
var state_fail: i64 = 0;
fn state_check(name: const u8[:], ok: bool) {
    if ok { state_pass += 1; } else { state_fail += 1; print("STATE FAIL ", name); }
}
fn state_test() {
    var image: u8[65536] = [0; 65536];
    // Repeatedly increment WRAM with interrupts disabled.
    image[65520] = 0xEA; image[65521] = 0; image[65522] = 1; image[65523] = 0; image[65524] = 0;
    power_on(image[..]);
    mem[256] = 0xFA; mem[257] = 0xFE; mem[258] = 0x06; mem[259] = 0; mem[260] = 2; mem[261] = 0xEB; mem[262] = 0xFA;
    set_audio(true);
    io_ports[SND_CTRL] = 1; io_ports[SND_OUTPUT_CTRL] = 0x0F;
    io_ports[SND_CH_VOL] = 0xFF;
    for i in 16 { mem[i] = (i * 13) as! u8; }
    state_check("initial execution", run_frame(0)); audio_clear();
    let saved = save_state_bytes();
    for n in 3 { state_check("continued execution", run_frame(KEY_A)); }
    let expected = save_state_bytes(); let pcm = to_bytes(aud_buf[..]);
    state_check("restore accepted", load_state_bytes(saved));
    for n in 3 { state_check("restored execution", run_frame(KEY_A)); }
    state_check("entire machine continuation matches", save_state_bytes() == expected);
    state_check("audio continuation matches", to_bytes(aud_buf[..]) == pcm);
    let unchanged = save_state_bytes();
    state_check("truncation rejected", !load_state_bytes(saved[..saved.len - 1]));
    var bad = str(saved); bad[50] ^= 1;
    state_check("corruption rejected", !load_state_bytes(bad));
    bad = str(saved); bad[9] = 2;
    state_check("unsupported version rejected", !load_state_bytes(bad));
    state_check("failed loads do not mutate", save_state_bytes() == unchanged);
    image[20] = 1; power_on(image[..]);
    let other = save_state_bytes();
    state_check("wrong ROM rejected", !load_state_bytes(saved));
    state_check("wrong ROM leaves current machine", save_state_bytes() == other);
    // BIOS bytes take priority over cartridge mapping and disable on 0xA0.7.
    var bios: u8[8192] = [0xFF; 8192];
    bios[8176] = 0xF4;
    state_check("BIOS boot accepted", power_on_with_bios(image[..], bios[..]));
    state_check("BIOS reset-vector mapping", rd8(0xFFFF0) == 0xF4);
    state_check("BIOS can execute", run_frame(0) && cpu_halted);
    let bios_state = save_state_bytes();
    port_wr(SYSTEM_CTRL1, 0x80);
    state_check("overlay disabled by system port", !boot_enabled && rd8(0xFFFF0) == 0xEA);
    state_check("state restores BIOS overlay", load_state_bytes(bios_state) && boot_enabled && rd8(0xFFFF0) == 0xF4);
    state_check("invalid BIOS leaves machine", !power_on_with_bios(image[..], "") && boot_enabled);
    // Four-byte-short stubs map to the next 4 KiB boundary.
    state_check("stub alignment", power_on_with_bios(image[..], bios[..8188]) && boot_size == 8192 && rd8(0xFFFF0) == 0xF4);
    power_on(image[..]);
    state_check("direct boot clears overlay", !boot_enabled && rd8(0xFFFF0) == 0xEA);
    print("state_test: ", state_pass, " passed, ", state_fail, " failed");
    if state_fail > 0 { exit(1); }
}

// Optional local BIOS smoke; no BIOS or cartridge bytes are committed.
fn bios_test(path: const u8[:], mono: bool, output: const u8[:]) {
    var bios: u8[>..] = [];
    if !read_file(path, bios) { print("cannot read BIOS"); exit(1); }
    var image: u8[65536] = [0; 65536];
    image[0] = 0xF4; image[65520] = 0xEA; image[65524] = 0x40;
    set_model(if mono { MODEL_MONO } else { MODEL_COLOR });
    if !power_on_with_bios(image[..], bios) { print("invalid BIOS"); exit(1); }
    for n in 300 {
        if !run_frame(if n < 12 { KEY_START } else { 0 }) {
            print("BIOS unsupported opcode ", fault_op(), " at ", fault_cs(), ":", fault_ip()); exit(1);
        }
    }
    var distinct: i64 = 0;
    for i in 32256 { if fb[i] != fb[0] { distinct += 1; } }
    print("bios_test: 300 frames, non-background pixels=", distinct, ", overlay=", boot_enabled);
    var ppm = str("P6\n224 144\n255\n");
    for c in fb {
        ppm.push(((((c as i64) >> 8) & 15) * 17) as! u8);
        ppm.push(((((c as i64) >> 4) & 15) * 17) as! u8);
        ppm.push((((c as i64) & 15) * 17) as! u8);
    }
    if !write_file(output, ppm) || distinct == 0 { exit(1); }
}
