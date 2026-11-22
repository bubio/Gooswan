// v2026.4's UI adapter clears Nuklear's retained read-only flag when a
// WINDOW_NO_INPUT window becomes interactive again. Use one neutral frame
// after a modal loop to repair popup/window input state without losing layout.
fn front_window_flags(flags: i64) -> i64 {
    return flags | (if front_ui_recover_input { ui::WINDOW_NO_INPUT } else { 0 });
}
// The frame that closes a menu still belongs to that menu: do not forward
// its click/release to a window behind it.
var front_menu_blocks_input: bool = false;
fn front_content_window_flags(flags: i64) -> i64 {
    return front_window_flags(flags | (if front_menu_blocks_input { ui::WINDOW_NO_INPUT } else { 0 }));
}
// Compact menus and sectioned dialogs, following UsaProject's Nuklear patterns.
var front_settings_reopen: bool = false;
var front_about_reopen:    bool = false;
var front_recent:          bool = false;
var front_recent_reopen:   bool = false;
var front_pre_mute:        i64  = 100;

// Measure the same rows that are drawn, in logical pixels using the active font.
enum FrontAction {
    None, PickRom, LoadRom, ClearHistory, SaveState, LoadState, OpenSettings,
    OpenAbout, OpenLink, Quit, TogglePause, Reset, StartBios, ToggleFullscreen,
    OpenBiosDirectory, CloseSettings, OpenRecent,
    Scale { value: i64 }, Rotate { value: i64 }, Filter { linear: bool },
}
var front_action = FrontAction.None;
var front_open_path: u8[>..] = [];

struct FrontMenuItem { title: const u8[:], shortcut: const u8[:], action: FrontAction, enabled: bool, checked: bool = false }
struct FrontMenuSize { width: f32 = 0.0, height: f32 = 0.0 }
fn front_menu_style() -> ui::Style {
    var s = ui::style(front_ui);
    s.window.padding = float2 { 4.0, 2.0 };
    s.window.spacing = float2 { 2.0, 2.0 };
    return s;
}
fn front_menu_row_height() -> f32 {
    let s = ui::style(front_ui);
    return ui::info(ui::font(front_ui)).height + 2.0 * (s.menu_button.padding.y + s.menu_button.border);
}
fn front_menu_text_width(text: const u8[:]) -> f32 { return ui::text_width(ui::font(front_ui), text); }
fn front_menu_button_width(text: const u8[:], style: ui::StyleButton) -> f32 {
    return front_menu_text_width(text) + 2.0 * (style.padding.x + style.border);
}
fn front_menu_separator_height() -> f32 { return ui::style(front_ui).window.spacing.y * 2.0 + 1.0; }
fn front_menu_has_checks(items: const FrontMenuItem[:]) -> bool {
    for item in items { if item.checked { return true; } }
    return false;
}
fn front_menu_measure(items: const FrontMenuItem[:]) -> FrontMenuSize {
    let s = ui::style(front_ui);
    var size = FrontMenuSize {};
    var shortcut_width: f32 = 0.0;
    for item in items {
        if item.action == FrontAction.None { size.height += front_menu_separator_height(); }
        else {
            size.height += front_menu_row_height();
            size.width = max(size.width, front_menu_text_width(item.title));
            shortcut_width = max(shortcut_width, front_menu_text_width(item.shortcut));
        }
        size.height += s.window.spacing.y;
    }
    // Reserve separate label and shortcut columns with a readable minimum gap.
    if shortcut_width > 0.0 { size.width += ui::info(ui::font(front_ui)).height + shortcut_width; }
    if front_menu_has_checks(items) { size.width += ui::info(ui::font(front_ui)).height; }
    size.width += 2.0 * (s.menu_button.padding.x + s.menu_button.border);
    return size;
}
// Groups reserve scrollbar space even when the content fits. Include it in the
// natural size, then limit only the viewport when the host window is smaller.
fn front_menu_popup_size(content: FrontMenuSize, ww: f32, hh: f32) -> float2, f32 {
    let s = ui::style(front_ui).window;
    let anchor = ui::widget_bounds(front_ui);
    let outer = 2.0 * (s.menu_padding.y + s.menu_border) + s.spacing.y;
    let body = content.height + 2.0 * s.group_padding.y + s.scrollbar_size.y;
    let width = content.width + 2.0 * (s.group_padding.x + s.menu_padding.x + s.menu_border) + s.scrollbar_size.x;
    let height = min(body + outer, max(hh - anchor.y - anchor.h - s.spacing.y, outer + 1.0));
    return float2 { min(width, max(ww - anchor.x - s.spacing.x, 1.0)), height }, max(height - outer, 1.0);
}
fn front_action_menu(label: const u8[:], id: const u8[:], items: const FrontMenuItem[:], ww: f32, hh: f32) {
    let c = front_ui;
    let checks = front_menu_has_checks(items);
    let size, body = front_menu_popup_size(front_menu_measure(items), ww, hh);
    if ui::menu_begin_label(c, label, ui::TEXT_LEFT, size) {
        front_menu_open = true;
        ui::layout_row_dynamic(c, body, 1);
        if ui::group_begin(c, id, 0) {
            for item in items {
                if item.action == FrontAction.None { front_menu_sep(); }
                else {
                    ui::layout_row_dynamic(c, front_menu_row_height(), 1);
                    front_item(item.title, item.shortcut, item.action, item.enabled, checks, item.checked);
                }
            }
            ui::group_end(c);
        }
        if front_action != FrontAction.None { ui::menu_close(c); }
        ui::menu_end(c);
    }
}
fn front_item(title: const u8[:], shortcut: const u8[:], action: FrontAction, enabled: bool, checks: bool, checked: bool) {
    let c = front_ui;
    if !enabled { ui::widget_disable_begin(c); }
    let bounds = ui::widget_bounds(c);
    var item_style = ui::style(c).menu_button; item_style.text_alignment = ui::TEXT_LEFT as u32;
    let inset = item_style.padding.x + item_style.border;
    if checks { item_style.padding.x += ui::info(ui::font(c)).height; }
    if ui::button_label_styled(c, item_style, title) && enabled { front_action = action; }
    if checked {
        let x = bounds.x + inset; let y = bounds.y + bounds.h / 2.0;
        ui::stroke_line(c, x, y, x + 3.0, y + 3.0, 1.5, UI_TEXT);
        ui::stroke_line(c, x + 3.0, y + 3.0, x + 9.0, y - 4.0, 1.5, UI_TEXT);
    }
    if shortcut.len > 0 {
        let width = ui::text_width(ui::font(c), shortcut);
        ui::draw_text(c, ui::rect(bounds.x + bounds.w - width - inset, bounds.y, width, bounds.h), shortcut, ui::font(c), UI_CLEAR, UI_MUTED);
    }
    if !enabled { ui::widget_disable_end(c); }
}
fn front_menu_sep() {
    let c = front_ui;
    ui::layout_row_dynamic(c, front_menu_separator_height(), 1);
    let state, r = ui::widget(c);
    let inset = ui::style(c).menu_button.padding.x;
    if state != 0 { ui::stroke_line(c, r.x + inset, r.y + r.h / 2.0, r.x + r.w - inset, r.y + r.h / 2.0, 1.0, UI_BORDER); }
}
fn front_prepare_dialog(name: const u8[:], bounds: ui::Rect, reopen: bool) {
    ui::window_show(front_ui, name, ui::SHOWN);
    if reopen { ui::window_set_bounds(front_ui, name, bounds); ui::window_set_focus(front_ui, name); }
}
fn front_open_about() {
    front_settings = false; front_capture = -1; front_recent = false; link_dialog = false;
    front_about = true; front_about_reopen = true;
}
fn front_open_recent() {
    front_settings = false; front_capture = -1; front_about = false; link_dialog = false;
    front_recent = true; front_recent_reopen = true;
}
fn front_draw_ui() {
    let c = front_ui;
    let recovering_input = front_ui_recover_input;
    front_menu_blocks_input = front_menu_open;
    front_menu_open = false;
    let screen = gfx::screen_size(); let density = max(hostwindow_scale(), 1.0);
    let ww = screen.x / density; let hh = screen.y / density;
    // Background chrome does not compete with the foreground dialog for focus.
    let saved = ui::style(c); let chrome = front_menu_style();
    ui::set_style(c, chrome);
    ui::window_set_bounds(c, "Menu", ui::rect(0.0, 0.0, ww, FRONT_MENU_HEIGHT));
    if ui::begin(c, "Menu", ui::rect(0.0, 0.0, ww, FRONT_MENU_HEIGHT), front_window_flags(ui::WINDOW_NO_SCROLLBAR)) {
        let file_items: FrontMenuItem[10] = [
            FrontMenuItem { "Open ROM...", "Ctrl+O", FrontAction.PickRom, !front_dialog },
            FrontMenuItem { "Open Recent...", "", FrontAction.OpenRecent, settings.recent_count > 0 },
            FrontMenuItem { "", "", FrontAction.None, false },
            FrontMenuItem { "Save State", "Ctrl+S", FrontAction.SaveState, front_path.len > 0 && !link_active() },
            FrontMenuItem { "Load State", "Ctrl+L", FrontAction.LoadState, front_path.len > 0 && !link_active() },
            FrontMenuItem { "", "", FrontAction.None, false },
            FrontMenuItem { "Settings...", "Ctrl+,", FrontAction.OpenSettings, true },
            FrontMenuItem { "About Gooswan...", "", FrontAction.OpenAbout, true },
            FrontMenuItem { "", "", FrontAction.None, false },
            FrontMenuItem { "Quit", "Ctrl+Q", FrontAction.Quit, true },
        ];
        let emu_items: FrontMenuItem[5] = [
            FrontMenuItem { if front_paused { "Resume" } else { "Pause" }, "Ctrl+P", FrontAction.TogglePause, front_loaded },
            FrontMenuItem { "Reset", "Ctrl+R", FrontAction.Reset, front_loaded },
            FrontMenuItem { "", "", FrontAction.None, false },
            FrontMenuItem { "BIOS Settings...", "", FrontAction.StartBios, true },
            FrontMenuItem { "Link Play...", "", FrontAction.OpenLink, true },
        ];
        let view_items: FrontMenuItem[13] = [
            FrontMenuItem { "Scale 1x", "", FrontAction.Scale { value: 1 }, true, settings.scale == 1 },
            FrontMenuItem { "Scale 2x", "", FrontAction.Scale { value: 2 }, true, settings.scale == 2 },
            FrontMenuItem { "Scale 3x", "", FrontAction.Scale { value: 3 }, true, settings.scale == 3 },
            FrontMenuItem { "Scale 4x", "", FrontAction.Scale { value: 4 }, true, settings.scale == 4 },
            FrontMenuItem { "", "", FrontAction.None, false },
            FrontMenuItem { "Fullscreen", "F11", FrontAction.ToggleFullscreen, true, hostwindow_is_fullscreen() },
            FrontMenuItem { "", "", FrontAction.None, false },
            FrontMenuItem { "Normal", "", FrontAction.Rotate { value: 0 }, true, settings.rotation == 0 },
            FrontMenuItem { "Rotate Left", "", FrontAction.Rotate { value: 2 }, true, settings.rotation == 2 },
            FrontMenuItem { "Rotate Right", "", FrontAction.Rotate { value: 1 }, true, settings.rotation == 1 },
            FrontMenuItem { "", "", FrontAction.None, false },
            FrontMenuItem { "Nearest", "", FrontAction.Filter { linear: false }, true, !settings.linear },
            FrontMenuItem { "Bilinear", "", FrontAction.Filter { linear: true }, true, settings.linear },
        ];
        ui::menubar_begin(c);
        // Extra space belongs to header cells, not to the popup item spacing.
        let gap = ui::info(ui::font(c)).height * 0.75;
        let widths: f32[3] = [front_menu_button_width("File", chrome.menu_button) + gap,
            front_menu_button_width("Emu", chrome.menu_button) + gap, front_menu_button_width("View", chrome.menu_button) + gap];
        ui::layout_row(c, ui::STATIC, front_menu_row_height(), widths[..]);
        front_action_menu("File", "FileActions", file_items[..], ww, hh);
        front_action_menu("Emu", "EmuActions", emu_items[..], ww, hh);
        front_action_menu("View", "ViewActions", view_items[..], ww, hh);
        ui::menubar_end(c);
    }
    ui::end(c);
    front_menu_blocks_input = front_menu_blocks_input || front_menu_open;
    front_draw_status(ww, hh);
    ui::set_style(c, saved);
    if !front_loaded && !front_settings && !front_about && !front_recent && !link_dialog { front_draw_welcome(ww, hh); }
    if front_settings { front_draw_settings(ww, hh); }
    if front_recent { front_draw_recent(ww, hh); }
    if front_about { front_draw_about(ww, hh); }
    if link_dialog { link_draw_dialog(ww, hh); }
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
    if !front_menu_blocks_input && !front_settings && !front_about && !front_recent && ui::input_is_mouse_pressed(c, ui::BUTTON_LEFT) && ui::input_is_mouse_hovering_rect(c, r) {
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
    if ui::input_is_mouse_pressed(c, ui::BUTTON_LEFT) && ui::input_is_mouse_hovering_rect(c, r) && !front_menu_blocks_input && !front_settings && !front_about && !front_recent { front_volume_drag = true; }
    if (!ui::input_is_mouse_down(c, ui::BUTTON_LEFT) || front_menu_blocks_input) && front_volume_drag { front_volume_drag = false; settings_save(); }
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
    if ui::begin(c, "Welcome", ui::rect((ww - w) / 2.0, FRONT_MENU_HEIGHT + (hh - front_chrome_height() - h) / 2.0, w, h), front_content_window_flags(ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BACKGROUND)) {
        ui::layout_row_dynamic(c, 28.0, 1); ui::label(c, "Gooswan", ui::TEXT_CENTERED);
        ui::layout_row_dynamic(c, 22.0, 1); ui::label_colored(c, "WonderSwan / WonderSwan Color", ui::TEXT_CENTERED, UI_MUTED);
        front_gap(8.0); ui::layout_row_dynamic(c, 28.0, 1);
        if ui::button_label(c, "Open ROM...") { front_action = FrontAction.PickRom; }
    }
    ui::end(c); ui::set_style(c, saved);
}
fn front_draw_settings(ww: f32, hh: f32) {
    let c = front_ui; let w = min(552.0, ww - 16.0); let h = min(414.0, hh - 64.0);
    front_prepare_dialog("Settings", ui::rect((ww - w) / 2.0, FRONT_MENU_HEIGHT + (hh - front_chrome_height() - h) / 2.0, w, h), front_settings_reopen);
    front_settings_reopen = false;
    if ui::begin(c, "Settings", ui::rect((ww - w) / 2.0, 34.0, w, h), front_content_window_flags(ui::WINDOW_BORDER | ui::WINDOW_TITLE | ui::WINDOW_MOVABLE | ui::WINDOW_CLOSABLE | ui::WINDOW_NO_SCROLLBAR)) {
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
        ui::layout_row_push(c, 88.0); if ui::button_label(c, "Close") { front_action = FrontAction.CloseSettings; }
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
        if ui::button_label(c, "Open ROM Directory") { front_action = FrontAction.OpenBiosDirectory; }
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
fn front_draw_recent(ww: f32, hh: f32) {
    let c = front_ui; let w = min(476.0, ww - 16.0); let h = min(354.0, hh - 64.0);
    front_prepare_dialog("Recent ROMs", ui::rect((ww - w) / 2.0, (hh - h) / 2.0, w, h), front_recent_reopen); front_recent_reopen = false;
    if ui::begin(c, "Recent ROMs", ui::rect((ww - w) / 2.0, (hh - h) / 2.0, w, h), front_content_window_flags(ui::WINDOW_BORDER | ui::WINDOW_TITLE | ui::WINDOW_MOVABLE | ui::WINDOW_CLOSABLE | ui::WINDOW_NO_SCROLLBAR)) {
        ui::layout_row_dynamic(c, max(h - 82.0, 40.0), 1);
        if ui::group_begin(c, "RecentList", 0) {
            ui::layout_row_dynamic(c, 26.0, 1);
            for i in settings.recent_count {
                if ui::button_label(c, front_basename(settings.recent[i].bytes[..settings.recent[i].len])) { front_open_path = str(settings.recent[i].bytes[..settings.recent[i].len]); front_action = FrontAction.LoadRom; front_recent = false; }
            }
            ui::group_end(c);
        }
        ui::layout_row_dynamic(c, 26.0, 2);
        if ui::button_label(c, "Clear History") { front_action = FrontAction.ClearHistory; }
        if ui::button_label(c, "Close") { front_recent = false; }
    }
    ui::end(c); if ui::window_is_hidden(c, "Recent ROMs") { front_recent = false; }
}
fn front_draw_about(ww: f32, hh: f32) {
    let c = front_ui; let w = min(374.0, ww - 16.0); let h = min(248.0, hh - 64.0);
    front_prepare_dialog("About Gooswan", ui::rect((ww - w) / 2.0, (hh - h) / 2.0, w, h), front_about_reopen); front_about_reopen = false;
    if ui::begin(c, "About Gooswan", ui::rect((ww - w) / 2.0, (hh - h) / 2.0, w, h), front_content_window_flags(ui::WINDOW_BORDER | ui::WINDOW_TITLE | ui::WINDOW_MOVABLE | ui::WINDOW_CLOSABLE | ui::WINDOW_NO_SCROLLBAR)) {
        ui::layout_row_dynamic(c, 28.0, 1); ui::label(c, "Gooswan", ui::TEXT_CENTERED);
        ui::layout_row_dynamic(c, 22.0, 1); ui::label(c, "WonderSwan / WonderSwan Color", ui::TEXT_CENTERED);
        ui::label_colored(c, "Goose / SDL3 / Nuklear", ui::TEXT_CENTERED, UI_MUTED);
        ui::label_colored(c, "Reference: Swanium", ui::TEXT_CENTERED, UI_MUTED);
        front_gap(8.0); ui::layout_row_dynamic(c, 26.0, 1); if ui::button_label(c, "Close") { front_about = false; }
    }
    ui::end(c); if ui::window_is_hidden(c, "About Gooswan") { front_about = false; }
}
fn front_do_action() {
    let action = front_action;
    front_action = FrontAction.None;
    // Wait until existing windows have consumed input before opening a dialog.
    match action {
        None => {},
        PickRom => front_pick_rom(),
        LoadRom => { let path = str(front_open_path); front_load(path); },
        ClearHistory => { settings.recent_count = 0; settings_save(); },
        SaveState => front_save_state(),
        LoadState => front_load_state(),
        OpenSettings => front_open_settings(),
        OpenAbout => front_open_about(),
        OpenLink => link_open_dialog(),
        Quit => { front_running = false; },
        TogglePause => front_toggle_pause(),
        Reset => front_reset(),
        StartBios => front_start_bios(),
        ToggleFullscreen => front_toggle_fullscreen(),
        OpenBiosDirectory => {
            let dir = config_path("bios");
            if !app_mkdirs(dir) || !host_open_directory(dir) { front_notify("Could not open BIOS directory"); }
        },
        CloseSettings => front_close_settings(),
        OpenRecent => front_open_recent(),
        Scale scale => front_set_scale(scale.value),
        Rotate rotation => front_set_rotation(rotation.value),
        Filter filter => { settings.linear = filter.linear; settings_save(); },
    }
}
