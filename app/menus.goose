// v2026.4's UI adapter clears Nuklear's retained read-only flag when a
// WINDOW_NO_INPUT window becomes interactive again. Use one neutral frame
// after a modal loop to repair popup/window input state without losing layout.
fn front_window_flags(flags: i64) -> i64 {
    return flags | (if front_ui_recover_input { ui::WINDOW_NO_INPUT } else { 0 });
}
// Compact menus and sectioned dialogs, following UsaProject's Nuklear patterns.
var front_settings_reopen: bool = false;
var front_about_reopen:    bool = false;
var front_recent:          bool = false;
var front_recent_reopen:   bool = false;
var front_pre_mute:        i64  = 100;

fn front_item(title: const u8[:], shortcut: const u8[:], action: i64, enabled: bool) {
    let c = front_ui;
    if !enabled { ui::widget_disable_begin(c); }
    let bounds = ui::widget_bounds(c);
    var item_style = ui::style(c).menu_button; item_style.text_alignment = ui::TEXT_LEFT as u32;
    if ui::button_label_styled(c, item_style, title) && enabled { front_action = action; }
    if shortcut.len > 0 {
        let width = ui::text_width(ui::font(c), shortcut);
        ui::draw_text(c, ui::rect(bounds.x + bounds.w - width - 6.0, bounds.y, width, bounds.h), shortcut, ui::font(c), UI_CLEAR, UI_MUTED);
    }
    if !enabled { ui::widget_disable_end(c); }
}
fn front_menu_sep() {
    let c = front_ui;
    ui::layout_row_dynamic(c, 5.0, 1);
    let state, r = ui::widget(c);
    if state != 0 { ui::stroke_line(c, r.x + 2.0, r.y + 2.0, r.x + r.w - 2.0, r.y + 2.0, 1.0, UI_BORDER); }
    ui::layout_row_dynamic(c, 22.0, 1);
}
fn front_prepare_dialog(name: const u8[:], bounds: ui::Rect, reopen: bool) {
    ui::window_show(front_ui, name, ui::SHOWN);
    if reopen { ui::window_set_bounds(front_ui, name, bounds); ui::window_set_focus(front_ui, name); }
}
fn front_open_about() {
    front_settings = false; front_capture = -1; front_recent = false;
    front_about = true; front_about_reopen = true;
}
fn front_open_recent() {
    front_settings = false; front_capture = -1; front_about = false;
    front_recent = true; front_recent_reopen = true;
}
fn front_draw_ui() {
    let c = front_ui;
    let recovering_input = front_ui_recover_input;
    front_menu_open = false;
    let screen = gfx::screen_size(); let density = max(hostwindow_scale(), 1.0);
    let ww = screen.x / density; let hh = screen.y / density;
    // Background chrome does not compete with the foreground dialog for focus.
    let saved = ui::style(c); var chrome = saved;
    chrome.window.padding = float2 { 4.0, 2.0 };
    chrome.window.spacing = float2 { 2.0, 2.0 };
    ui::set_style(c, chrome);
    ui::window_set_bounds(c, "Menu", ui::rect(0.0, 0.0, ww, FRONT_MENU_HEIGHT));
    if ui::begin(c, "Menu", ui::rect(0.0, 0.0, ww, FRONT_MENU_HEIGHT), front_window_flags(ui::WINDOW_NO_SCROLLBAR)) {
        ui::menubar_begin(c); ui::layout_row_static(c, 20.0, 56, 3);
        if ui::menu_begin_label(c, "File", ui::TEXT_LEFT, float2 { min(292.0, ww - 8.0), min(232.0, hh - 32.0) }) {
            front_menu_open = true;
            ui::layout_row_dynamic(c, min(210.0, hh - 54.0), 1);
            if ui::group_begin(c, "FileActions", 0) {
                ui::layout_row_dynamic(c, 22.0, 1);
                front_item("Open ROM...", "Ctrl+O", 1, !front_dialog);
                front_item("Open Recent...", "", 15, settings.recent_count > 0);
                front_menu_sep();
                front_item("Save State", "Ctrl+S", 4, front_path.len > 0);
                front_item("Load State", "Ctrl+L", 5, front_path.len > 0);
                front_menu_sep();
                front_item("Settings...", "Ctrl+,", 6, true);
                front_item("About Gooswan...", "", 7, true);
                front_menu_sep(); front_item("Quit", "Ctrl+Q", 8, true);
                ui::group_end(c);
            }
            if front_action != 0 { ui::menu_close(c); }
            ui::menu_end(c);
        }
        if ui::menu_begin_label(c, "Emu", ui::TEXT_LEFT, float2 { min(270.0, ww - 8.0), 110.0 }) {
            front_menu_open = true; ui::layout_row_dynamic(c, 22.0, 1);
            front_item(if front_paused { "Resume" } else { "Pause" }, "Ctrl+P", 9, front_loaded);
            front_item("Reset", "Ctrl+R", 10, front_loaded);
            front_menu_sep(); front_item("BIOS Settings...", "", 11, true);
            if front_action != 0 { ui::menu_close(c); }
            ui::menu_end(c);
        }
        if ui::menu_begin_label(c, "View", ui::TEXT_LEFT, float2 { min(270.0, ww - 8.0), min(278.0, hh - 32.0) }) {
            front_menu_open = true;
            ui::layout_row_dynamic(c, min(256.0, hh - 54.0), 1);
            if ui::group_begin(c, "ViewActions", 0) {
                front_display_controls();
                ui::group_end(c);
            }
            if front_action != 0 { ui::menu_close(c); }
            ui::menu_end(c);
        }
        ui::menubar_end(c);
    }
    ui::end(c);
    front_draw_status(ww, hh);
    ui::set_style(c, saved);
    if !front_loaded && !front_settings && !front_about && !front_recent { front_draw_welcome(ww, hh); }
    if front_settings { front_draw_settings(ww, hh); }
    if front_recent { front_draw_recent(ww, hh); }
    if front_about { front_draw_about(ww, hh); }
    // The Settings X button can request recovery while this frame is drawn.
    // Leave that request for the next complete frame instead of discarding it.
    if recovering_input { front_ui_recover_input = false; }
}
fn front_draw_status(ww: f32, hh: f32) {
    let c = front_ui;
    ui::window_set_bounds(c, "Status", ui::rect(0.0, hh - FRONT_STATUS_HEIGHT, ww, FRONT_STATUS_HEIGHT));
    if ui::begin(c, "Status", ui::rect(0.0, hh - FRONT_STATUS_HEIGHT, ww, FRONT_STATUS_HEIGHT), front_window_flags(ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BACKGROUND | ui::WINDOW_NO_INPUT)) {
        let right: f32 = if ww >= 400.0 { 226.0 } else { 118.0 };
        ui::layout_row_begin(c, ui::STATIC, 18.0, if ww >= 400.0 { 7 } else { 3 });
        ui::layout_row_push(c, max(ww - right - 18.0, 40.0));
        if front_message.len > 0 && gfx::time() < front_message_until { ui::label(c, front_message, ui::TEXT_LEFT); }
        else if !front_loaded { ui::label_colored(c, "Ready", ui::TEXT_LEFT, UI_MUTED); }
        else { ui::label(c, str(front_label, if front_fault { " - stopped" } else if front_paused { " - paused" } else { "" }), ui::TEXT_LEFT); }
        if ww >= 400.0 {
            ui::layout_row_push(c, 10.0); front_status_divider();
            ui::layout_row_push(c, 40.0); ui::label_colored(c, if !front_loaded { "--" } else if core::is_mono() { "Mono" } else { "Color" }, ui::TEXT_CENTERED, UI_MUTED);
            ui::layout_row_push(c, 10.0); front_status_divider();
        }
        ui::layout_row_push(c, 22.0); front_volume_icon();
        ui::layout_row_push(c, 78.0); front_volume_slider();
        if ww >= 400.0 { ui::layout_row_push(c, 62.0); ui::label_colored(c, str(front_fps, " FPS"), ui::TEXT_RIGHT, UI_MUTED); }
        ui::layout_row_end(c);
    }
    ui::end(c);
}
fn front_status_divider() {
    let state, r = ui::widget(front_ui);
    if state != 0 { ui::stroke_line(front_ui, r.x + r.w / 2.0, r.y + 2.0, r.x + r.w / 2.0, r.y + r.h - 2.0, 1.0, UI_BORDER); }
}
fn front_volume_icon() {
    let c = front_ui; let state, r = ui::widget(c);
    if state == 0 { return; }
    if !front_settings && !front_about && !front_recent && ui::input_is_mouse_pressed(c, ui::BUTTON_LEFT) && ui::input_is_mouse_hovering_rect(c, r) {
        if settings.volume > 0 { front_pre_mute = settings.volume; settings.volume = 0; }
        else { settings.volume = max(front_pre_mute, 1); }
        front_set_volume();
    }
    let col = if settings.volume == 0 { UI_MUTED } else { UI_TEXT };
    let cy = r.y + r.h / 2.0;
    ui::fill_rect(c, ui::rect(r.x + 2.0, cy - 3.0, 4.0, 6.0), 0.0, col);
    let points: float2[4] = [float2 { r.x + 6.0, cy - 3.0 }, float2 { r.x + 6.0, cy + 3.0 }, float2 { r.x + 11.0, cy + 6.0 }, float2 { r.x + 11.0, cy - 6.0 }];
    ui::fill_polygon(c, points[..], col);
    if settings.volume == 0 { ui::stroke_line(c, r.x + 14.0, cy - 4.0, r.x + 20.0, cy + 4.0, 1.5, ui::Color { 221, 96, 87, 255 }); }
    else { ui::stroke_arc(c, r.x + 11.0, cy, 6.0, -0.7, 0.7, 1.2, col); }
}
var front_volume_drag: bool = false;
fn front_volume_slider() {
    let c = front_ui; let state, r = ui::widget(c);
    if state == 0 { return; }
    if ui::input_is_mouse_pressed(c, ui::BUTTON_LEFT) && ui::input_is_mouse_hovering_rect(c, r) && !front_settings && !front_about && !front_recent { front_volume_drag = true; }
    if !ui::input_is_mouse_down(c, ui::BUTTON_LEFT) && front_volume_drag { front_volume_drag = false; settings_save(); }
    let left = r.x + 5.0; let width = max(r.w - 10.0, 1.0); let cy = r.y + r.h / 2.0;
    if front_volume_drag {
        let mouse = gfx::mouse_pos(); let density = max(hostwindow_scale(), 1.0);
        let value = clamp(((mouse.x / density - left) * 100.0 / width) as! i64, 0, 100);
        if value != settings.volume { settings.volume = value; hostaudio_volume(value); }
    }
    ui::stroke_line(c, left, cy, left + width, cy, 3.0, ui::Color { 83, 88, 98, 255 });
    let knob = left + width * settings.volume / 100.0;
    ui::stroke_line(c, left, cy, knob, cy, 3.0, UI_MUTED);
    ui::fill_circle(c, ui::rect(knob - 4.0, cy - 4.0, 8.0, 8.0), UI_TEXT);
}
fn front_draw_welcome(ww: f32, hh: f32) {
    let c = front_ui; let w = min(380.0, ww - 24.0); let h = min(142.0, hh - 72.0);
    let saved = ui::style(c); var clear = saved;
    clear.window.fixed_background = ui::style_item_color(ui::Color { 19, 21, 25, 255 });
    ui::set_style(c, clear);
    if ui::begin(c, "Welcome", ui::rect((ww - w) / 2.0, FRONT_MENU_HEIGHT + (hh - FRONT_CHROME_HEIGHT - h) / 2.0, w, h), front_window_flags(ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BACKGROUND)) {
        ui::layout_row_dynamic(c, 28.0, 1); ui::label(c, "Gooswan", ui::TEXT_CENTERED);
        ui::layout_row_dynamic(c, 22.0, 1); ui::label_colored(c, "WonderSwan / WonderSwan Color", ui::TEXT_CENTERED, UI_MUTED);
        front_gap(8.0); ui::layout_row_dynamic(c, 28.0, 1);
        if ui::button_label(c, "Open ROM...") { front_action = 1; }
    }
    ui::end(c); ui::set_style(c, saved);
}
fn front_draw_settings(ww: f32, hh: f32) {
    let c = front_ui; let w = min(552.0, ww - 16.0); let h = min(414.0, hh - 64.0);
    front_prepare_dialog("Settings", ui::rect((ww - w) / 2.0, FRONT_MENU_HEIGHT + (hh - FRONT_CHROME_HEIGHT - h) / 2.0, w, h), front_settings_reopen);
    front_settings_reopen = false;
    if ui::begin(c, "Settings", ui::rect((ww - w) / 2.0, 34.0, w, h), front_window_flags(ui::WINDOW_BORDER | ui::WINDOW_TITLE | ui::WINDOW_MOVABLE | ui::WINDOW_CLOSABLE | ui::WINDOW_NO_SCROLLBAR)) {
        ui::layout_row_static(c, 26.0, 98, 2);
        if front_tab("ROM", front_section == 0) { front_section = 0; front_capture = -1; }
        if front_tab("Input", front_section == 1) { front_section = 1; }
        ui::layout_row_dynamic(c, max(h - 112.0, 70.0), 1);
        if ui::group_begin(c, "SettingsBody", 0) {
            if front_section == 0 { front_rom_settings(); }
            else { front_input_settings(); }
            front_gap(14.0); ui::group_end(c);
        }
        ui::layout_row_begin(c, ui::STATIC, 26.0, 2);
        ui::layout_row_push(c, max(w - 122.0, 60.0));
        ui::label_colored(c, if settings_writable { "Changes are saved automatically." } else { "settings.toml needs repair; writes disabled." }, ui::TEXT_LEFT, UI_MUTED);
        ui::layout_row_push(c, 88.0); if ui::button_label(c, "Close") { front_action = 14; }
        ui::layout_row_end(c);
    }
    ui::end(c);
    if ui::window_is_hidden(c, "Settings") { front_close_settings(); }
}
fn front_rom_settings() {
    let c = front_ui;
    if front_box("BootMode", "Startup", 174.0) {
        ui::layout_row_dynamic(c, 22.0, 1);
        let modes: const u8[:][4] = ["Direct boot without BIOS", "WonderSwan", "WonderSwan Color", "SwanCrystal"];
        for i in 4 { if ui::option_label(c, modes[i], settings.bios == i) && settings.bios != i { settings.bios = i; settings_save(); } }
        ui::layout_row_dynamic(c, 18.0, 1); ui::label_colored(c, "Applies when you open or reset a ROM.", ui::TEXT_LEFT, UI_MUTED);
        ui::group_end(c);
    }
    if front_box("BiosFiles", "BIOS ROMs", 98.0) {
        ui::layout_row_static(c, 26.0, 212, 1);
        if ui::button_label(c, "Open ROM Directory") { front_action = 13; }
        ui::layout_row_dynamic(c, 18.0, 1); ui::label_colored(c, "Use ws_irom.bin, wsc_irom.bin or wc_irom.bin.", ui::TEXT_LEFT, UI_MUTED);
        ui::group_end(c);
    }
}
fn front_pad_label(button: i64) -> u8[>..] {
    let names: const u8[:][15] = ["South", "East", "West", "North", "Back", "Guide", "Start", "Left stick", "Right stick", "L shoulder", "R shoulder", "D-pad Up", "D-pad Down", "D-pad Left", "D-pad Right"];
    if button < 0 { return str("Unbound"); }
    if button < 15 { return str(names[button]); }
    var name: u8[64] = [0; 64]; let n = hostpad_button_name(button, name[..]); return str(name[..min(n, 64)]);
}
fn front_input_settings() {
    let c = front_ui;
    if front_box("InputBehavior", "Orientation", 72.0) {
        ui::layout_row_dynamic(c, 22.0, 1);
        if ui::checkbox_label(c, "Rotate directional input with screen", settings.rotate_input) { settings_save(); }
        ui::group_end(c);
    }
    if front_box("InputBindings", "Button mappings", 442.0) {
        ui::layout_row_dynamic(c, 22.0, 1);
        var name: u8[256] = [0; 256]; let n = hostpad_name(name[..]); ui::label_colored(c, name[..min(n, 256)], ui::TEXT_LEFT, UI_MUTED);
        let widths: f32[3] = [0.15, 0.42, 0.43];
        ui::layout_row(c, ui::DYNAMIC, 22.0, widths);
        ui::label_colored(c, "Button", ui::TEXT_LEFT, UI_MUTED); ui::label_colored(c, "Keyboard", ui::TEXT_LEFT, UI_MUTED); ui::label_colored(c, "Controller", ui::TEXT_LEFT, UI_MUTED);
        ui::layout_row(c, ui::DYNAMIC, 25.0, widths);
        for i in 11 {
            ui::label(c, BUTTON_LABELS[i], ui::TEXT_LEFT);
            if ui::button_label(c, if front_capture == i && !front_capture_pad { "Press key... Esc cancels" } else { settings.keys[i].bytes[..settings.keys[i].len] }) { front_capture = i; front_capture_pad = false; }
            let pad_label: u8[>..] = if front_capture == i && front_capture_pad { "Press button..." } else { front_pad_label(settings.pads[i]) };
            if ui::button_label(c, pad_label) { front_capture = i; front_capture_pad = true; }
        }
        ui::group_end(c);
    }
    ui::layout_row_static(c, 26.0, 172, 1);
    if ui::button_label(c, "Reset Input Defaults") {
        for i in 11 { settings.keys[i] = app_text(DEFAULT_KEYS[i]); settings.pads[i] = DEFAULT_PADS[i]; }
        settings.rotate_input = true; front_capture = -1; settings_save();
    }
}
fn front_display_controls() {
    let c = front_ui;
    ui::layout_row_dynamic(c, 18.0, 1); ui::label_colored(c, "Scale", ui::TEXT_LEFT, UI_MUTED);
    ui::layout_row_dynamic(c, 24.0, 4);
    for n in 1..5 { if front_tab(str(n, "x"), settings.scale == n) { front_action = 20 + n; } }
    ui::layout_row_dynamic(c, 22.0, 1);
    var fullscreen = hostwindow_is_fullscreen(); if ui::checkbox_label(c, "Fullscreen (F11)", fullscreen) { front_action = 12; }
    front_gap(4.0);
    ui::layout_row_dynamic(c, 18.0, 1); ui::label_colored(c, "Orientation", ui::TEXT_LEFT, UI_MUTED);
    ui::layout_row_dynamic(c, 24.0, 3);
    let rotations: const u8[:][3] = ["Normal", "Left", "Right"]; let values: i64[3] = [0, 2, 1];
    for i in 3 { if front_tab(rotations[i], settings.rotation == values[i]) { front_action = 30 + values[i]; } }
    front_gap(4.0);
    ui::layout_row_dynamic(c, 18.0, 1); ui::label_colored(c, "Sampling", ui::TEXT_LEFT, UI_MUTED);
    ui::layout_row_dynamic(c, 24.0, 2);
    if front_tab("Nearest", !settings.linear) { front_action = 40; }
    if front_tab("Bilinear", settings.linear) { front_action = 41; }
}
fn front_draw_recent(ww: f32, hh: f32) {
    let c = front_ui; let w = min(476.0, ww - 16.0); let h = min(354.0, hh - 64.0);
    front_prepare_dialog("Recent ROMs", ui::rect((ww - w) / 2.0, (hh - h) / 2.0, w, h), front_recent_reopen); front_recent_reopen = false;
    if ui::begin(c, "Recent ROMs", ui::rect((ww - w) / 2.0, (hh - h) / 2.0, w, h), front_window_flags(ui::WINDOW_BORDER | ui::WINDOW_TITLE | ui::WINDOW_MOVABLE | ui::WINDOW_CLOSABLE | ui::WINDOW_NO_SCROLLBAR)) {
        ui::layout_row_dynamic(c, max(h - 82.0, 40.0), 1);
        if ui::group_begin(c, "RecentList", 0) {
            ui::layout_row_dynamic(c, 26.0, 1);
            for i in settings.recent_count {
                if ui::button_label(c, front_basename(settings.recent[i].bytes[..settings.recent[i].len])) { front_open_path = str(settings.recent[i].bytes[..settings.recent[i].len]); front_action = 2; front_recent = false; }
            }
            ui::group_end(c);
        }
        ui::layout_row_dynamic(c, 26.0, 2);
        if ui::button_label(c, "Clear History") { front_action = 3; }
        if ui::button_label(c, "Close") { front_recent = false; }
    }
    ui::end(c); if ui::window_is_hidden(c, "Recent ROMs") { front_recent = false; }
}
fn front_draw_about(ww: f32, hh: f32) {
    let c = front_ui; let w = min(374.0, ww - 16.0); let h = min(248.0, hh - 64.0);
    front_prepare_dialog("About Gooswan", ui::rect((ww - w) / 2.0, (hh - h) / 2.0, w, h), front_about_reopen); front_about_reopen = false;
    if ui::begin(c, "About Gooswan", ui::rect((ww - w) / 2.0, (hh - h) / 2.0, w, h), front_window_flags(ui::WINDOW_BORDER | ui::WINDOW_TITLE | ui::WINDOW_MOVABLE | ui::WINDOW_CLOSABLE | ui::WINDOW_NO_SCROLLBAR)) {
        ui::layout_row_dynamic(c, 28.0, 1); ui::label(c, "Gooswan", ui::TEXT_CENTERED);
        ui::layout_row_dynamic(c, 22.0, 1); ui::label(c, "WonderSwan / WonderSwan Color", ui::TEXT_CENTERED);
        ui::label_colored(c, "Goose / SDL3 / Nuklear", ui::TEXT_CENTERED, UI_MUTED);
        ui::label_colored(c, "Reference: Swanium", ui::TEXT_CENTERED, UI_MUTED);
        front_gap(8.0); ui::layout_row_dynamic(c, 26.0, 1); if ui::button_label(c, "Close") { front_about = false; }
    }
    ui::end(c); if ui::window_is_hidden(c, "About Gooswan") { front_about = false; }
}
fn front_do_action() {
    let action = front_action; front_action = 0;
    // Dialogs are opened only after all current windows have consumed input,
    // so a menu click cannot also toggle an option in the newly opened window.
    if action == 1 { front_pick_rom(); }
    else if action == 2 { let path = str(front_open_path); front_load(path); }
    else if action == 3 { settings.recent_count = 0; settings_save(); }
    else if action == 4 { front_save_state(); }
    else if action == 5 { front_load_state(); }
    else if action == 6 { front_open_settings(); }
    else if action == 7 { front_open_about(); }
    else if action == 8 { front_running = false; }
    else if action == 9 { front_paused = !front_paused; front_resync(); }
    else if action == 10 { front_reset(); }
    else if action == 11 { front_start_bios(); }
    else if action == 12 { front_toggle_fullscreen(); }
    else if action == 13 { let dir = config_path("bios"); if !app_mkdirs(dir) || !host_open_directory(dir) { front_notify("Could not open BIOS directory"); } }
    else if action == 14 { front_close_settings(); }
    else if action == 15 { front_open_recent(); }
    else if action >= 21 && action <= 24 { front_set_scale(action - 20); }
    else if action >= 30 && action <= 32 { front_set_rotation(action - 30); }
    else if action == 40 || action == 41 { settings.linear = action == 41; settings_save(); }
}
