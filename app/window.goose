// SDL window controls and native file-picker focus recovery.
extern fn hostplatform_open();
extern fn hostwindow_icon(data: const u8[:]);
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

var front_ui:                   ui::Context = ui::Context { 0 };
var front_ui_recover_input:     bool        = false;
var front_dialog_focus_pending: bool        = false;
var front_dialog_result:        i64         = 0;
var front_dialog:               bool        = false;
var front_settings:             bool        = false;
var front_about:                bool        = false;
var front_fullscreen_pending:   i64         = -1;
var front_fullscreen_deadline:  f64         = 0.0;

fn front_resize() {
    if hostwindow_is_fullscreen() { return; }
    let w, h = front_video_size();
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

fn front_poll_dialog() {
    if !front_dialog { return; }
    var chosen: u8[4096] = [0; 4096];
    let result = hostdialog_poll(chosen[..]);
    if result == 0 { return; }
    var n: i64 = 0;
    while n < chosen.len && chosen[n] != 0 { n += 1; }
    front_finish_dialog(result, chosen[..n]);
}

fn front_update_fullscreen() {
    let actual = hostwindow_is_fullscreen();
    if front_fullscreen_pending >= 0 {
        if actual != (front_fullscreen_pending == 1) && gfx::time() <= front_fullscreen_deadline { return; }
        front_fullscreen_pending = -1;
    }
    if settings.fullscreen != actual {
        settings.fullscreen = actual;
        settings_save();
    }
}
