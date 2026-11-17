// Embed the distribution font so the application can be moved on its own.
var front_font_atlas:   ui::FontAtlas = ui::FontAtlas { 0 };
var front_font_density: f32           = 0.0;
fn front_make_ui() -> ui::Context {
    let atlas = ui::create_font_atlas();
    // Latin, kana, unified kanji, full-width punctuation.
    let ranges: u32[8] = [32, 255, 0x3000, 0x30FF, 0x4E00, 0x9FFF, 0xFF00, 0xFFEF];
    let font = ui::add_font_from_memory(atlas, embed_file("../assets/fonts/MPLUS1p-Regular.ttf"), 16.0, ui::FontConfig {}, ranges[..]);
    if font.id != 0 && ui::bake(atlas, max(hostwindow_scale(), 1.0)) {
        let context = ui::create_context(font);
        if context.id != 0 { front_font_atlas = atlas; return context; }
    }
    ui::destroy(atlas);
    return ui::create(16.0);
}
fn front_scale_ui() {
    let density = max(hostwindow_scale(), 1.0);
    if density != front_font_density {
        if front_font_atlas.id != 0 { ui::bake(front_font_atlas, density); }
        ui::set_scale(front_ui, density); front_font_density = density;
    }
}
