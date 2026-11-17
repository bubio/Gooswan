// Use the same M PLUS 1p font as UsaProject, with system/bitmap fallbacks.
var front_font_atlas:   ui::FontAtlas = ui::FontAtlas { 0 };
var front_font_density: f32           = 0.0;
fn front_make_ui() -> ui::Context {
    var win: u8[>..] = []; env("WINDIR", win);
    let windows_cjk = str(win, "/Fonts/YuGothM.ttc");
    let windows_latin = str(win, "/Fonts/segoeui.ttf");
    let packaged = str(resource_dir(), "assets/fonts/MPLUS1p-Regular.ttf");
    let checkout = str(resource_dir(), "../assets/fonts/MPLUS1p-Regular.ttf");
    let bundle = str(resource_dir(), "../Resources/assets/fonts/MPLUS1p-Regular.ttf");
    let candidates: const u8[:][10] = [
        bundle, packaged, checkout,
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
        windows_cjk, windows_latin,
    ];
    for path in candidates {
        if !file_exists(path) { continue; }
        let atlas = ui::create_font_atlas();
        // Latin, kana, unified kanji, full-width punctuation.
        let ranges: u32[8] = [32, 255, 0x3000, 0x30FF, 0x4E00, 0x9FFF, 0xFF00, 0xFFEF];
        let font = ui::add_font_from_file(atlas, path, 16.0, ui::FontConfig {}, ranges[..]);
        if font.id != 0 && ui::bake(atlas, max(hostwindow_scale(), 1.0)) {
            let context = ui::create_context(font);
            if context.id != 0 { front_font_atlas = atlas; return context; }
        }
        ui::destroy(atlas);
    }
    return ui::create(16.0);
}
fn front_scale_ui() {
    let density = max(hostwindow_scale(), 1.0);
    if density != front_font_density {
        if front_font_atlas.id != 0 { ui::bake(front_font_atlas, density); }
        ui::set_scale(front_ui, density); front_font_density = density;
    }
}
