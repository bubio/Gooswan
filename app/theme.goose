// Compact Nuklear chrome and readable toggles, following UsaProject's
// docs/nuklear-reference.md. All dimensions are logical pixels.
var FRONT_MENU_HEIGHT: i64 = 26;
let FRONT_STATUS_HEIGHT: i64 = 24;
fn front_chrome_height() -> i64 { return FRONT_MENU_HEIGHT + FRONT_STATUS_HEIGHT; }
let UI_TEXT = ui::Color { 220, 222, 226, 255 };
let UI_MUTED = ui::Color { 155, 161, 170, 255 };
let UI_ACCENT = ui::Color { 70, 110, 160, 255 };
let UI_BORDER = ui::Color { 65, 68, 74, 255 };
let UI_CLEAR = ui::Color { 0, 0, 0, 0 };

fn front_apply_theme() {
    var s = ui::style(front_ui);
    s.text.color = UI_TEXT;
    s.window.background = ui::Color { 42, 44, 48, 255 };
    s.window.fixed_background = ui::style_item_color(s.window.background);
    s.window.border_color = UI_BORDER; s.window.group_border_color = UI_BORDER;
    s.window.menu_border_color = UI_BORDER;
    s.window.padding = float2 { 8.0, 6.0 };
    s.window.group_padding = float2 { 8.0, 6.0 };
    s.window.spacing = float2 { 4.0, 4.0 };
    s.window.header.normal = ui::style_item_color(ui::Color { 35, 37, 41, 255 });
    s.window.header.hover = s.window.header.normal; s.window.header.active = s.window.header.normal;
    s.window.header.label_normal = UI_TEXT; s.window.header.label_hover = UI_TEXT; s.window.header.label_active = UI_TEXT;
    s.window.header.padding = float2 { 6.0, 4.0 };
    s.window.header.label_padding = float2 { 4.0, 2.0 };
    s.button.normal = ui::style_item_color(ui::Color { 49, 52, 57, 255 });
    s.button.hover = ui::style_item_color(ui::Color { 62, 67, 75, 255 });
    s.button.active = ui::style_item_color(UI_ACCENT);
    s.button.text_normal = UI_TEXT; s.button.text_hover = UI_TEXT; s.button.text_active = UI_TEXT;
    s.button.border_color = UI_BORDER; s.button.rounding = 3.0;
    s.menu_button.text_normal = UI_TEXT; s.menu_button.text_hover = UI_TEXT; s.menu_button.text_active = UI_TEXT;
    s.menu_button.hover = ui::style_item_color(ui::Color { 58, 64, 74, 255 });
    s.menu_button.active = ui::style_item_color(UI_ACCENT);
    s.selectable.text_normal = UI_TEXT; s.selectable.text_hover = UI_TEXT; s.selectable.text_pressed = UI_TEXT;
    s.selectable.hover = ui::style_item_color(UI_ACCENT);
    s.selectable.pressed = ui::style_item_color(UI_ACCENT);
    // Nuklear's default cursor is darker than its box, making a checked box
    // look like an empty hole. Use a bright cursor for both toggles.
    s.checkbox.text_normal = UI_TEXT; s.checkbox.text_hover = UI_TEXT; s.checkbox.text_active = UI_TEXT;
    s.checkbox.cursor_normal = ui::style_item_color(ui::Color { 220, 220, 220, 255 });
    s.checkbox.cursor_hover = ui::style_item_color(ui::Color { 255, 255, 255, 255 });
    s.option.text_normal = UI_TEXT; s.option.text_hover = UI_TEXT; s.option.text_active = UI_TEXT;
    s.option.cursor_normal = s.checkbox.cursor_normal; s.option.cursor_hover = s.checkbox.cursor_hover;
    s.slider.bar_filled = UI_ACCENT;
    s.slider.cursor_normal = ui::style_item_color(UI_TEXT);
    s.slider.cursor_hover = s.slider.cursor_normal; s.slider.cursor_active = s.slider.cursor_normal;
    s.slider.cursor_size = float2 { 10.0, 10.0 };
    s.scrollv.cursor_normal = ui::style_item_color(ui::Color { 93, 98, 108, 255 });
    ui::set_style(front_ui, s);
    ui::style_hide_cursor(front_ui);
    let chrome = front_menu_style().window;
    let height = front_menu_row_height() + 2.0 * chrome.padding.y + chrome.spacing.y;
    FRONT_MENU_HEIGHT = height as! i64;
    if FRONT_MENU_HEIGHT < height { FRONT_MENU_HEIGHT += 1; }
}
fn front_gap(height: f32) { ui::layout_row_dynamic(front_ui, height, 1); ui::spacing(front_ui, 1); }
fn front_box(id: const u8[:], title: const u8[:], height: f32) -> bool {
    ui::layout_row_dynamic(front_ui, height, 1);
    return ui::group_begin_titled(front_ui, id, title, ui::WINDOW_BORDER | ui::WINDOW_TITLE | ui::WINDOW_NO_SCROLLBAR);
}
fn front_tab(label: const u8[:], active: bool) -> bool {
    let saved = ui::style(front_ui);
    if active { var selected = saved; selected.button.normal = ui::style_item_color(UI_ACCENT); ui::set_style(front_ui, selected); }
    let clicked = ui::button_label(front_ui, label);
    if active { ui::set_style(front_ui, saved); }
    return clicked;
}
