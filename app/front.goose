// Desktop frontend. Host I/O stays here; core advances only at frame boundaries.
let front_vs = embed_shader("vert", """
    layout(location = 0) out vec2 v_uv;
    void main() {
        vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
        v_uv = vec2(p.x, 1.0 - p.y);
        gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    }
    """);
let front_fs = embed_shader("frag", """
    layout(set = 2, binding = 0) uniform sampler2D tex;
    layout(location = 0) in vec2 v_uv;
    layout(location = 0) out vec4 o;
    void main() { o = texture(tex, v_uv); }
    """);
extern fn hostaudio_open(rate: i64) -> bool;
extern fn hostaudio_push(pcm: const i16[:]);
extern fn hostaudio_queued() -> i64;
extern fn hostaudio_clear();
extern fn hostaudio_volume(value: i64);
extern fn hostaudio_close();
extern fn hostplatform_open();
extern fn hostwindow_icon(path: const u8[:]);
extern fn host_absolute_path(path: const u8[:], out: u8[:]) -> i64;
extern fn hostplatform_close();
extern fn hostwindow_focused() -> bool;
extern fn hostwindow_restore_focus() -> bool;
extern fn hostwindow_present() -> bool;
extern fn hostwindow_size(w: i64, h: i64) -> bool;
extern fn hostwindow_fullscreen(on: bool) -> bool;
extern fn hostwindow_is_fullscreen() -> bool;
extern fn hostwindow_scale() -> f32;
extern fn hostdialog_open(location: const u8[:]) -> bool;
extern fn hostdialog_poll(out: u8[:]) -> i64;
extern fn hostpad_poll();
extern fn hostpad_down(button: i64) -> bool;
extern fn hostpad_name(out: u8[:]) -> i64;
extern fn hostpad_button_name(button: i64, out: u8[:]) -> i64;
let FRONT_AUDIO_AHEAD: i64 = 1272;
let FRONT_MAX_RUN:     i64 = 8;
var front_audio_ok: bool = false;
var front_loaded:   bool = false;
// The BIOS actually running, independent of the selection for the next boot.
var front_bios_kind:            i64         = 0;
var front_bios_eeprom_loaded:   bool        = false;
var front_paused:               bool        = false;
var front_fault:                bool        = false;
var front_ui_recover_input:     bool        = false;
var front_dialog_focus_pending: bool        = false;
var front_dialog_result:        i64         = 0;
var front_dialog:               bool        = false;
var front_settings:             bool        = false;
var front_about:                bool        = false;
var front_section:              i64         = 0;
var front_capture:              i64         = -1;
var front_capture_pad:          bool        = false;
var front_pad_previous:         bool[26]    = [false; 26];
var front_path:                 u8[>..]     = [];
var front_label:                u8[>..]     = [];
var front_message:              u8[>..]     = [];
var front_message_until:        f64         = 0.0;
var front_next_t:               f64         = 0.0;
var front_frames:               i64         = 0;
var front_fps:                  i64         = 0;
var front_running:              bool        = true;
var front_menu_open:            bool        = false;
var front_action:               i64         = 0;
var front_open_path:            u8[>..]     = [];
var front_check:                bool        = false;
var front_fullscreen_pending:   i64         = -1;
var front_fullscreen_deadline:  f64         = 0.0;
var front_ui:                   ui::Context = ui::Context { 0 };

fn front_notify(s: const u8[:]) { front_message = str(s); front_message_until = gfx::time() + 5.0; }
fn front_basename(path: const u8[:]) -> const u8[:] {
    var start: i64 = 0;
    for i in path.len { if path[i] == '/' || path[i] == 92 { start = i + 1; } }
    return path[start..];
}
fn front_parse(s: const u8[:]) -> i64 { let n, ok = parse_int(s); return if ok { n } else { 0 }; }
fn front_resync() {
    hostaudio_clear(); core::audio_clear();
    front_next_t = gfx::time() + (core::FRAME_CYCLES as f64) / core::CPU_HZ;
}
fn front_save_media() -> bool {
    if !front_loaded { return true; }
    if front_path.len > 0 && !save_saves(front_path) { front_notify("Could not write cartridge save data"); return false; }
    if front_bios_kind > 0 && !save_bios_eeprom(front_bios_kind) {
        front_notify("Could not write BIOS internal EEPROM"); return false;
    }
    return true;
}
fn front_resize() {
    if hostwindow_is_fullscreen() { return; }
    let w: i64 = if settings.rotation == 0 { 224 } else { 144 };
    let h: i64 = if settings.rotation == 0 { 144 } else { 224 };
    hostwindow_size(w * settings.scale, h * settings.scale + front_chrome_height());
}
fn front_set_scale(scale: i64) { settings.scale = scale; front_resize(); settings_save(); }
fn front_set_rotation(rotation: i64) { settings.rotation = rotation; front_resize(); settings_save(); }
fn front_toggle_fullscreen() {
    let target = !hostwindow_is_fullscreen();
    if hostwindow_fullscreen(target) {
        front_fullscreen_pending = if target { 1 } else { 0 };
        front_fullscreen_deadline = gfx::time() + 3.0;
    } else { front_notify("Could not change fullscreen mode"); }
}
fn front_set_volume() { hostaudio_volume(settings.volume); settings_save(); }
fn front_open_settings() {
    front_settings = true; front_capture = -1;
    front_about = false; front_recent = false; front_settings_reopen = true;
}
fn front_close_settings() {
    front_settings = false; front_capture = -1;
    front_ui_recover_input = true;
    if front_ui.id != 0 {
        // Remove the dialog from Nuklear's focus stack immediately; merely
        // omitting it next frame can leave the menu marked read-only.
        ui::window_show(front_ui, "Settings", ui::HIDDEN);
        ui::window_set_focus(front_ui, "Menu");
    }
    settings_save();
}
fn front_pick_rom() {
    if front_dialog { return; }
    if hostdialog_open(front_path) { front_dialog = true; front_capture = -1; front_resync(); }
    else { front_notify("Could not open file picker"); }
}
// Native dialogs can consume button/key releases and leave Nuklear's previous
// popup window read-only. Reset both caches and restore the active UI window
// for every completion path, including Cancel and native errors.
fn front_finish_dialog(result: i64, path: const u8[:]) {
    front_dialog = false; front_dialog_result = result;
    if result == 1 { front_load(path); }
    else if result < 0 { front_notify("File picker failed"); }
    front_resync();
    front_capture = -1; front_volume_drag = false; front_menu_open = false;
    front_ui_recover_input = true;
    if front_ui.id != 0 {
        ui::input_begin(front_ui);
        for button in 6 { ui::input_button(front_ui, button, -1, -1, false); }
        for key in 30 { ui::input_key(front_ui, key, false); }
        ui::input_end(front_ui);
        // Drop the synthetic release edges too: a cancellation must not click
        // whichever widget happens to be behind the native dialog.
        ui::input_begin(front_ui);
        let mouse = gfx::mouse_pos();
        ui::input_motion(front_ui, mouse.x as! i64, mouse.y as! i64);
        ui::input_end(front_ui);
        let target = if front_settings { "Settings" } else if front_about { "About Gooswan" } else if front_recent { "Recent ROMs" } else { "Menu" };
        ui::window_set_focus(front_ui, target);
    }
    // v2026.4 has no clear-input call. A focus reset releases its cached keys
    // and buttons; the final event reflects the native window's actual focus.
    let focused = if hostwindow_present() { hostwindow_restore_focus() } else { gfx::focused() };
    gfx::inject_focus(false); gfx::inject_focus(focused);
    front_dialog_focus_pending = hostwindow_present() && !focused;
}
fn front_bios_path() -> u8[>..] {
    let name = if settings.bios == 1 { "ws_irom.bin" } else if settings.bios == 2 { "wsc_irom.bin" } else { "wc_irom.bin" };
    return config_path(str("bios/", name));
}
fn front_boot(image: const u8[:], bios_only: bool) -> bool {
    var bios: u8[>..] = [];
    var with_bios = false;
    if settings.bios != 0 {
        let path = front_bios_path();
        if read_file(path, bios) && bios.len > 0 && bios.len <= 65536 { with_bios = true; }
        else if bios_only { front_notify("Selected BIOS is missing or invalid; place it in the BIOS directory"); return false; }
        else { front_notify("Selected BIOS missing or invalid; using direct boot"); }
    } else if bios_only { front_notify("Select a BIOS in Settings > ROM first"); return false; }
    // Read and validate before replacing the current machine. Missing files
    // retain the normal first-boot defaults; unreadable/corrupt files do not.
    var internal: u8[>..] = [];
    if with_bios && !read_bios_eeprom(settings.bios, internal) {
        front_notify("Could not read BIOS internal EEPROM; current machine preserved"); return false;
    }
    core::set_model(if with_bios { if settings.bios == 1 { core::MODEL_MONO } else { core::MODEL_COLOR } } else { core::MODEL_AUTO });
    if with_bios { core::power_on_with_bios(image, bios); }
    else { core::power_on(image); }
    front_bios_kind = if with_bios { settings.bios } else { 0 };
    front_bios_eeprom_loaded = internal.len > 0;
    if front_bios_eeprom_loaded { core::save_load(core::SAVE_INTERNAL_EEPROM, internal); }
    core::set_audio(true);
    front_fault = false; front_loaded = true; front_bios_start = 0;
    return true;
}
fn front_load(path: const u8[:]) {
    var image: u8[>..] = [];
    if !read_file(path, image) || image.len < 16 || image.len > 16777216 {
        front_notify(str("Cannot open ROM: ", path)); return;
    }
    if !front_save_media() { return; }
    if !front_boot(image, false) { return; }
    var absolute: u8[4096] = [0; 4096];
    let path_len = host_absolute_path(path, absolute[..]);
    front_path = if path_len > 0 && path_len < 4096 { str(absolute[..path_len]) } else { str(path) };
    front_label = str(front_basename(path));
    // Existing ROM-local EEPROM remains the fallback until the console has
    // its own save. An older sidecar must not overwrite newly edited BIOS data.
    load_saves(front_path, !front_bios_eeprom_loaded); sync_rtc_to_host();
    // A portrait footer selects the default; explicit orientation remains selectable.
    settings.rotation = if core::is_vertical() { 2 } else { 0 };
    settings_recent(front_path); settings_save();
    gfx::set_title(str("Gooswan - ", front_label));
    front_resize(); front_resync();
}
fn front_reset() {
    if front_path.len > 0 { let path = str(front_path); front_load(path); return; }
    if front_loaded { front_start_bios(); }
}
fn front_start_bios() {
    if settings.bios == 0 { front_notify("Select a BIOS in Settings > ROM first"); return; }
    // Validate before replacing the current game.
    var bios: u8[>..] = [];
    if !read_file(front_bios_path(), bios) || bios.len == 0 || bios.len > 65536 { front_notify("Selected BIOS is missing or invalid"); return; }
    if !front_save_media() { return; }
    var image: u8[65536] = [0; 65536];
    image[0] = 0xF4; image[65520] = 0xEA; image[65524] = 0x40;
    if !front_boot(image[..], true) { return; }
    front_path = []; front_label = str("BIOS Settings");
    // Like Swanium, hold Start briefly to enter the console settings.
    front_bios_start = 12;
    gfx::set_title("Gooswan - BIOS Settings");
    front_resync();
}
var front_bios_start: i64 = 0;
fn front_state_path() -> u8[>..] {
    // Full-path identity prevents same-name ROMs in different folders colliding.
    return config_path(str("states/", hash(front_path[..]), ".state"));
}
fn front_save_state() {
    if !front_loaded || front_path.len == 0 { front_notify("Open a cartridge ROM first"); return; }
    if !app_mkdirs(config_path("states")) || !write_file_atomic(front_state_path(), core::save_state_bytes()) {
        front_notify("Could not write save state"); return;
    }
    front_notify("State saved");
}
fn front_load_state() {
    if !front_loaded || front_path.len == 0 { front_notify("Open a cartridge ROM first"); return; }
    var data: u8[>..] = [];
    if !read_file(front_state_path(), data) { front_notify("No readable save state for this ROM"); return; }
    if !core::load_state_bytes(data) { front_notify("Invalid, damaged or incompatible save state"); return; }
    front_fault = false; front_bios_start = 0; front_resync(); front_notify("State loaded");
}
fn front_rotate_pads(k: i64, rotation: i64) -> i64 {
    var out = k;
    let steps: i64 = if rotation == 2 { 1 } else if rotation == 1 { 3 } else { 0 };
    for n in steps {
        let y = out & 15; let x = (out >> 4) & 15;
        out = (out & ~255) | (((y << 1) | (y >> 3)) & 15) | ((((x << 1) | (x >> 3)) & 15) << 4);
    }
    return out;
}
fn front_keys() -> i64 {
    // Mouse hover over the chrome does not capture keyboard/gamepad input.
    if !gfx::focused() || front_dialog || front_settings || front_about || front_recent || front_menu_open || ui::wants_keyboard(front_ui) { return 0; }
    if gfx::key_down("Left Ctrl") || gfx::key_down("Right Ctrl") || gfx::key_down("Left GUI") || gfx::key_down("Right GUI") { return 0; }
    var keys: i64 = 0;
    for i in 11 {
        if gfx::key_down(settings.keys[i].bytes[..settings.keys[i].len]) || hostpad_down(settings.pads[i]) { keys |= BUTTON_BITS[i]; }
    }
    return front_rotate_pads(keys, if settings.rotate_input { settings.rotation } else { 0 });
}
fn front_audio_pump() {
    if !front_audio_ok { core::audio_clear(); return; }
    var pcm: i16[>..] = [];
    for i in core::audio_len() { pcm.push(core::audio_sample(i) as! i16); }
    core::audio_clear(); hostaudio_push(pcm[..]);
}
fn front_shortcuts() {
    if front_capture >= 0 {
        if front_capture_pad {
            for b in 26 {
                if hostpad_down(b) && !front_pad_previous[b] {
                    settings.pads[front_capture] = b; front_capture = -1; settings_save(); break;
                }
            }
        }
        for event in gfx::events() {
            if event.kind != gfx::EVENT_KEY || !event.down || event.repeat { continue; }
            if event.scancode == gfx::scancode("Escape") { front_capture = -1; break; }
            if !front_capture_pad {
                settings.keys[front_capture] = app_text(gfx::key_name(event.scancode));
                front_capture = -1; settings_save(); break;
            }
        }
        return;
    }
    if front_dialog { return; }
    if gfx::key_pressed("Escape") {
        if front_settings { front_close_settings(); }
        else if front_about { front_about = false; }
        else if front_recent { front_recent = false; }
        else if hostwindow_is_fullscreen() { front_toggle_fullscreen(); }
    }
    if gfx::key_pressed("F11") { front_toggle_fullscreen(); }
    let ctrl = gfx::key_down("Left Ctrl") || gfx::key_down("Right Ctrl") || gfx::key_down("Left GUI") || gfx::key_down("Right GUI");
    if !ctrl { return; }
    if gfx::key_pressed("O") { front_pick_rom(); }
    if gfx::key_pressed("Q") { front_running = false; }
    if gfx::key_pressed(",") { front_open_settings(); }
    if front_settings || front_about || front_recent { return; }
    if gfx::key_pressed("P") && front_loaded { front_paused = !front_paused; front_resync(); }
    if gfx::key_pressed("R") { front_reset(); }
    if gfx::key_pressed("S") { front_save_state(); }
    if gfx::key_pressed("L") { front_load_state(); }
    for n in 1..5 { if gfx::key_pressed(str(n)) { front_set_scale(n); } }
    if gfx::key_pressed("Up") { front_set_rotation(0); }
    if gfx::key_pressed("Left") { front_set_rotation(2); }
    if gfx::key_pressed("Right") { front_set_rotation(1); }
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
    if argv.len > 1 && argv[1] == "--self-test" { frontend_test(); return; }
    var max_frames: i64 = 0;
    if argv.len > 2 { max_frames = front_parse(argv[2]); }
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
    let w: i64 = if settings.rotation == 0 { 224 } else { 144 };
    let h: i64 = if settings.rotation == 0 { 144 } else { 224 };
    if !gfx::open("Gooswan", w * settings.scale, h * settings.scale + (if front_check { 0 } else { front_chrome_height() }), gfx::NO_VSYNC | gfx::WINDOW_RESIZABLE) { print("gfx: ", gfx::error()); exit(3); }
    hostplatform_open();
    let icon = str(resource_dir(), "assets/icons/gooswan.bmp");
    let checkout_icon = str(resource_dir(), "../assets/icons/gooswan.bmp");
    if file_exists(icon) { hostwindow_icon(icon); }
    else if file_exists(checkout_icon) { hostwindow_icon(checkout_icon); }
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
        hostwindow_size((if settings.rotation == 0 { 224 } else { 144 }) * 3, (if settings.rotation == 0 { 144 } else { 224 }) * 3);
    }
    var tw: i64 = 224; var th: i64 = 144;
    var tex = gfx::texture2d(tw, th);
    let nearest = gfx::sampler(gfx::NEAREST, gfx::CLAMP);
    let linear = gfx::sampler(gfx::LINEAR, gfx::CLAMP);
    let pipe = gfx::pipeline(front_vs, front_fs);
    var rgba: u8[129024] = [0; 129024];
    let period: f64 = (core::FRAME_CYCLES as f64) / core::CPU_HZ;
    var fps_time = gfx::time(); var fps_frame: i64 = 0;
    var vx: f32 = 0.0; var vy: f32 = 0.0; var vw: f32 = 0.0; var vh: f32 = 0.0;
    // Cocoa activation and window presentation are asynchronous. Raise after
    // the first frame has been presented, rather than during window creation.
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
        if front_dialog {
            var chosen: u8[4096] = [0; 4096];
            let result = hostdialog_poll(chosen[..]);
            if result != 0 {
                var n: i64 = 0; while n < 4096 && chosen[n] != 0 { n += 1; }
                front_finish_dialog(result, chosen[..n]);
            }
        }
        if !front_check { front_draw_ui(); }
        front_do_action();
        for b in 26 { front_pad_previous[b] = hostpad_down(b); }
        let actual_fullscreen = hostwindow_is_fullscreen();
        if front_fullscreen_pending >= 0 {
            if actual_fullscreen == (front_fullscreen_pending == 1) || gfx::time() > front_fullscreen_deadline { front_fullscreen_pending = -1; }
        }
        if front_fullscreen_pending < 0 && settings.fullscreen != actual_fullscreen { settings.fullscreen = actual_fullscreen; settings_save(); }
        let stopped = front_paused || front_fault || front_dialog || !front_loaded;
        var ran: i64 = 0;
        if stopped { front_resync(); }
        while !stopped && ran < FRONT_MAX_RUN {
            if front_audio_ok { if hostaudio_queued() >= FRONT_AUDIO_AHEAD { break; } }
            else {
                let now = gfx::time(); if now < front_next_t { break; }
                front_next_t += period; if now - front_next_t > 0.25 { front_next_t = now + period; }
            }
            var keys = front_keys();
            if front_bios_start > 0 { keys |= core::KEY_START; front_bios_start -= 1; }
            if !core::run_frame(keys) {
                front_fault = true; front_notify(str("Unsupported opcode ", core::fault_op(), " at ", core::fault_cs(), ":", core::fault_ip()));
                if front_check { front_running = false; }
                break;
            }
            front_audio_pump(); ran += 1; front_frames += 1;
            if front_frames % 150 == 0 { front_save_media(); }
            if max_frames > 0 && front_frames >= max_frames { front_running = false; break; }
        }
        if ran == 0 { sleep_ms(1); }
        if gfx::time() - fps_time >= 1.0 {
            front_fps = ((front_frames - fps_frame) / (gfx::time() - fps_time)) as! i64;
            fps_frame = front_frames; fps_time = gfx::time();
        }
        let nw: i64 = if settings.rotation == 0 { 224 } else { 144 };
        let nh: i64 = if settings.rotation == 0 { 144 } else { 224 };
        if nw != tw || nh != th { gfx::release(tex); tw = nw; th = nh; tex = gfx::texture2d(tw, th); }
        for sy in 144 { for sx in 224 {
            let c: i64 = if front_loaded { core::pixel(sx, sy) } else { 0 };
            let d: i64 = (if settings.rotation == 2 { (223 - sx) * 144 + sy } else if settings.rotation == 1 { sx * 144 + (143 - sy) } else { sy * 224 + sx }) * 4;
            rgba[d] = (((c >> 8) & 15) * 17) as! u8;
            rgba[d + 1] = (((c >> 4) & 15) * 17) as! u8;
            rgba[d + 2] = ((c & 15) * 17) as! u8; rgba[d + 3] = 255;
        } }
        gfx::update_texture(tex, rgba[..]);
        let screen = gfx::screen_size();
        let density = max(hostwindow_scale(), 1.0);
        let top:    f32 = if front_check { 0.0 } else { FRONT_MENU_HEIGHT * density };
        let bottom: f32 = if front_check { 0.0 } else { FRONT_STATUS_HEIGHT * density };
        let aw = screen.x as f32; let ah = max(screen.y - top - bottom, 1.0);
        let zoom = min(aw / tw, ah / th);
        vw = tw * zoom; vh = th * zoom;
        vx = (aw - vw) / 2.0; vy = top + (ah - vh) / 2.0;
        gfx::begin_screen(float4 { 0.0, 0.0, 0.0, 1.0 });
        gfx::viewport(vx, vy, vw, vh);
        gfx::bind(pipe); gfx::bind_texture(gfx::FRAGMENT, 0, tex, if settings.linear && !front_check { linear } else { nearest }); gfx::draw(3);
        gfx::end_pass();
        if !front_check { ui::render(front_ui); }
        front_smoke_after();
    }
    if front_check {
        gfx::frame();
        let px = gfx::read_pixels(gfx::screen()); let screen = gfx::screen_size();
        var bad: i64 = 0;
        if px.len == screen.x * screen.y * 4 && vw >= tw && vh >= th {
            for y in th { for x in tw {
                let xx = (vx + (x + 0.5) * vw / tw) as! i64;
                let yy = (vy + (y + 0.5) * vh / th) as! i64;
                let si = (yy * screen.x + xx) * 4; let di = (y * tw + x) * 4;
                if px[si] != rgba[di] || px[si + 1] != rgba[di + 1] || px[si + 2] != rgba[di + 2] { bad += 1; }
            } }
        } else { bad = -1; }
        print("frontcheck: mismatches=", bad, " of 32256 after ", front_frames, " frames");
        if bad != 0 || front_fault { front_save_media(); hostaudio_close(); exit(1); }
    }
    front_save_media(); settings_save();
    hostaudio_close(); hostplatform_close(); ui::destroy(front_ui);
    if front_font_atlas.id != 0 { ui::destroy(front_font_atlas); }
    gfx::close();
}
