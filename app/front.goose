// Desktop event loop and emulation pacing.
extern fn hostaudio_open(rate: i64) -> bool;
extern fn hostaudio_push(pcm: const i16[:]);
extern fn hostaudio_queued() -> i64;
extern fn hostaudio_clear();
extern fn hostaudio_volume(value: i64);
extern fn hostaudio_close();
let FRONT_AUDIO_AHEAD: i64 = 1272;
let FRONT_MAX_RUN:     i64 = 8;
var front_audio_ok: bool = false;

let FRONT_FRAME_PERIOD: f64 = (core::FRAME_CYCLES as f64) / core::CPU_HZ;
var front_paused:        bool    = false;
var front_fault:         bool    = false;
var front_section:       i64     = 0;
var front_message:       u8[>..] = [];
var front_message_until: f64     = 0.0;
var front_next_t:        f64     = 0.0;
var front_frames:        i64     = 0;
var front_fps:           i64     = 0;
var front_running:       bool    = true;
var front_menu_open:     bool    = false;
var front_check:         bool    = false;

fn front_notify(s: const u8[:]) { front_message = str(s); front_message_until = gfx::time() + 5.0; }
fn front_resync() {
    hostaudio_clear(); core::audio_clear();
    front_next_t = gfx::time() + FRONT_FRAME_PERIOD;
}

fn front_toggle_pause() {
    front_paused = !front_paused;
    front_resync();
}

fn front_set_volume() { hostaudio_volume(settings.volume); settings_save(); }
fn front_audio_pump() {
    if !front_audio_ok { core::audio_clear(); return; }
    var pcm: i16[>..] = [];
    for i in core::audio_len() { pcm.push(core::audio_sample(i) as! i16); }
    core::audio_clear(); hostaudio_push(pcm[..]);
}

fn front_run_frames(max_frames: i64) -> i64 {
    if front_paused || front_fault || front_dialog || !front_loaded {
        front_resync();
        return 0;
    }
    var ran: i64 = 0;
    while ran < FRONT_MAX_RUN {
        if front_audio_ok && !link_active() {
            if hostaudio_queued() >= FRONT_AUDIO_AHEAD { break; }
        } else {
            let now = gfx::time();
            if now < front_next_t { break; }
            front_next_t += FRONT_FRAME_PERIOD;
            if now - front_next_t > 0.25 { front_next_t = now + FRONT_FRAME_PERIOD; }
        }
        var keys = front_keys();
        if front_bios_start > 0 {
            keys |= core::KEY_START;
            front_bios_start -= 1;
        }
        if !core::run_frame(keys) {
            front_fault = true;
            front_notify(str("Unsupported opcode ", core::fault_op(), " at ", core::fault_cs(), ":", core::fault_ip()));
            if front_check { front_running = false; }
            break;
        }
        front_audio_pump();
        link_flush();
        ran += 1;
        front_frames += 1;
        if max_frames > 0 && front_frames >= max_frames {
            front_running = false;
            break;
        }
    }
    return ran;
}
fn front_help() {
    print("Gooswan - WonderSwan / WonderSwan Color emulator");
    print("Usage: gooswan [<rom> [<frames> [check]]]");
    print("       gooswan <option>");
    print("");
    print("With no arguments, open the app and choose File > Open ROM.");
    print("<frames> limits emulation to the given number of frames.");
    print("check verifies the presented picture against the emulated framebuffer.");
    print("");
    print("Options:");
    print("  -h, --help          Show this help and exit");
    print("  --self-test         Run settings and input tests without opening a window");
    print("  --dialog-test       Run offscreen dialog-cancellation tests");
    print("  --ui-smoke          Run GUI smoke tests");
    print("  --ui-smoke-dialog   Run GUI smoke tests including the native picker");
    print("  --cancel-test       Open the native picker for a manual cancellation test");
}
fn front_main() {
    let argv = args();
    if argv.len > 1 && (argv[1] == "--help" || argv[1] == "-h") { front_help(); return; }
    if argv.len > 1 && argv[1] == "--dialog-test" { frontend_dialog_test(); return; }
    if argv.len > 1 && argv[1] == "--link-self-test" { link_test_worker(); return; }
    if argv.len > 1 && argv[1] == "--self-test" { frontend_test(); return; }
    var max_frames: i64 = 0;
    if argv.len > 2 {
        let frames, ok = parse_int(argv[2]);
        if ok { max_frames = frames; }
    }
    front_check = argv.len > 3 && argv[3] == "check";
    front_smoke = argv.len > 1 && (argv[1] == "--ui-smoke" || argv[1] == "--ui-smoke-dialog");
    front_smoke_dialog = argv.len > 1 && argv[1] == "--ui-smoke-dialog";
    front_cancel_live = argv.len > 1 && argv[1] == "--cancel-test";
    if argv.len > 1 && argv[1].len > 0 && argv[1][0] == '-' && !front_smoke && !front_cancel_live {
        print("Unknown option: ", argv[1]);
        print("Run gooswan --help for usage.");
        exit(1);
    }
    settings_load();
    let w, h = front_video_size();
    if !gfx::open("Gooswan", w * settings.scale, h * settings.scale + (if front_check { 0 } else { front_chrome_height() }), gfx::NO_VSYNC | gfx::WINDOW_RESIZABLE) { print("gfx: ", gfx::error()); exit(3); }
    hostplatform_open();
    hostwindow_icon(embed_file("../assets/icons/gooswan.bmp"));
    front_resize();
    front_ui = front_make_ui();
    if front_ui.id == 0 { print("ui: ", ui::error()); exit(3); }
    front_apply_theme();
    if !front_check { front_resize(); }
    front_audio_ok = hostaudio_open(core::AUDIO_RATE);
    hostaudio_volume(settings.volume);
    if settings_notice.len > 0 { front_notify(settings_notice); }
    if front_smoke {
        var image: u8[65536] = [0; 65536]; image[65520] = 0xF4;
        let path = config_path("smoke.ws");
        if !write_file(path, image[..]) { print("cannot write smoke fixture"); exit(1); }
        front_smoke_rom_path = str(path);
    } else if argv.len > 1 && !front_cancel_live { front_load(argv[1]); }
    if settings.fullscreen && !front_check { front_toggle_fullscreen(); }
    if front_check {
        if !front_loaded { exit(1); }
        let check_w, check_h = front_video_size();
        hostwindow_size(check_w * 3, check_h * 3);
    }
    var video = front_video_open();
    var fps_time = gfx::time();
    var fps_frame: i64 = 0;
    // The window may not be ready to take focus until the first frame is presented.
    var startup_frames: i64 = 0;
    while front_running && gfx::frame() {
        if startup_frames < 2 {
            startup_frames += 1;
            if startup_frames == 2 { hostwindow_restore_focus(); }
        }
        if front_dialog_focus_pending && hostwindow_focused() {
            if !gfx::focused() { gfx::inject_focus(true); }
            front_dialog_focus_pending = false;
        }
        hostpad_poll();
        front_scale_ui();
        ui::input_from_gfx(front_ui);
        front_shortcuts();
        front_smoke_before();
        front_cancel_before();
        front_poll_dialog();
        link_poll();
        if !front_check { front_draw_ui(); }
        front_do_action();
        for b in 26 { front_pad_previous[b] = hostpad_down(b); }
        front_update_fullscreen();
        if front_run_frames(max_frames) == 0 { sleep_ms(1); }

        let now = gfx::time();
        if now - fps_time >= 1.0 {
            front_fps = ((front_frames - fps_frame) / (now - fps_time)) as! i64;
            fps_frame = front_frames;
            fps_time = now;
        }
        front_draw_video(video);
        if !front_check { ui::render(front_ui); }
        front_smoke_after();
    }
    if front_check {
        let bad = front_video_mismatches(video);
        print("frontcheck: mismatches=", bad, " of ", core::SCREEN_W * core::SCREEN_H, " after ", front_frames, " frames");
        if bad != 0 || front_fault { front_save_media(); hostaudio_close(); exit(1); }
    }
    hostlink_stop();
    front_save_media(); settings_save();
    hostaudio_close(); hostplatform_close(); ui::destroy(front_ui);
    if front_font_atlas.id != 0 { ui::destroy(front_font_atlas); }
    gfx::close();
}
