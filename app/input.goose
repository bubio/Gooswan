// Keyboard, gamepad, shortcuts, and remapping.
var front_capture:      i64      = -1;
var front_capture_pad:  bool     = false;
var front_pad_previous: bool[26] = [false; 26];

extern fn hostpad_poll();
extern fn hostpad_down(button: i64) -> bool;
extern fn hostpad_name(out: u8[:]) -> i64;
extern fn hostpad_button_name(button: i64, out: u8[:]) -> i64;

fn front_rotate_pads(k: i64, rotation: i64) -> i64 {
    var out = k;
    let steps: i64 = if rotation == 2 { 1 } else if rotation == 1 { 3 } else { 0 };
    for n in steps {
        let y = out & 15; let x = (out >> 4) & 15;
        out = (out & ~255) | (((y << 1) | (y >> 3)) & 15) | ((((x << 1) | (x >> 3)) & 15) << 4);
    }
    return out;
}
fn front_shortcut_modifier() -> bool {
    return gfx::key_down("Left Ctrl") || gfx::key_down("Right Ctrl") || gfx::key_down("Left GUI") || gfx::key_down("Right GUI");
}
fn front_keys() -> i64 {
    // Mouse hover over the chrome does not capture keyboard/gamepad input.
    if !gfx::focused() || front_dialog || front_settings || front_about || front_recent || front_menu_open || ui::wants_keyboard(front_ui) { return 0; }
    if front_shortcut_modifier() { return 0; }
    var keys: i64 = 0;
    for i in 11 {
        if gfx::key_down(settings.keys[i].bytes[..settings.keys[i].len]) || hostpad_down(settings.pads[i]) { keys |= BUTTON_BITS[i]; }
    }
    return front_rotate_pads(keys, if settings.rotate_input { settings.rotation } else { 0 });
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
        else if link_dialog { link_dialog = false; }
        else if hostwindow_is_fullscreen() { front_toggle_fullscreen(); }
    }
    if gfx::key_pressed("F11") { front_toggle_fullscreen(); }
    if !front_shortcut_modifier() { return; }
    if gfx::key_pressed("O") { front_pick_rom(); }
    if gfx::key_pressed("Q") { front_running = false; }
    if gfx::key_pressed(",") { front_open_settings(); }
    if front_settings || front_about || front_recent { return; }
    if gfx::key_pressed("P") && front_loaded { front_toggle_pause(); }
    if gfx::key_pressed("R") { front_reset(); }
    if gfx::key_pressed("S") { front_save_state(); }
    if gfx::key_pressed("L") { front_load_state(); }
    for n in 1..5 { if gfx::key_pressed(str(n)) { front_set_scale(n); } }
    if gfx::key_pressed("Up") { front_set_rotation(0); }
    if gfx::key_pressed("Left") { front_set_rotation(2); }
    if gfx::key_pressed("Right") { front_set_rotation(1); }
}
