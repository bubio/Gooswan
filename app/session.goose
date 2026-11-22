// ROM and BIOS transitions, save media, and save states.
var front_loaded: bool = false;
// The BIOS actually running, independent of the selection for the next boot.
var front_bios_kind:          i64     = 0;
var front_bios_eeprom_loaded: bool    = false;
var front_bios_start:         i64     = 0;
var front_path:               u8[>..] = [];
var front_label:              u8[>..] = [];

extern fn host_absolute_path(path: const u8[:], out: u8[:]) -> i64;

fn front_basename(path: const u8[:]) -> const u8[:] {
    var start: i64 = 0;
    for i in path.len { if path[i] == '/' || path[i] == 92 { start = i + 1; } }
    return path[start..];
}

fn front_save_media() -> bool {
    if !front_loaded { return true; }
    if front_path.len > 0 && !save_saves(front_path) { front_notify("Could not write cartridge save data"); return false; }
    if front_bios_kind > 0 && !save_bios_eeprom(front_bios_kind) {
        front_notify("Could not write BIOS internal EEPROM"); return false;
    }
    return true;
}
fn front_bios_path() -> u8[>..] { return bios_path(settings.bios, ".bin"); }

fn read_selected_bios(bios: u8[>..]&) -> bool {
    return read_file(front_bios_path(), bios) && bios.len > 0 && bios.len <= 65536;
}

fn front_boot(image: const u8[:], bios: const u8[:]) -> bool {
    let with_bios = bios.len > 0;
    // Read and validate before replacing the current machine. Missing files
    // retain the normal first-boot defaults; unreadable/corrupt files do not.
    var internal: u8[>..] = [];
    if with_bios && !read_bios_eeprom(settings.bios, internal) {
        front_notify("Could not read BIOS internal EEPROM; current machine preserved"); return false;
    }
    let model = if !with_bios { core::MODEL_AUTO } else if settings.bios == 1 { core::MODEL_MONO } else { core::MODEL_COLOR };
    core::set_model(model);
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
    var bios: u8[>..] = [];
    if settings.bios != 0 && !read_selected_bios(bios) {
        bios.clear();
        front_notify("Selected BIOS missing or invalid; using direct boot");
    }
    if !front_boot(image[..], bios[..]) { return; }
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
    if !read_selected_bios(bios) { front_notify("Selected BIOS is missing or invalid"); return; }
    if !front_save_media() { return; }
    var image: u8[65536] = [0; 65536];
    image[0] = 0xF4; image[65520] = 0xEA; image[65524] = 0x40;
    if !front_boot(image[..], bios[..]) { return; }
    front_path = []; front_label = str("BIOS Settings");
    // Like Swanium, hold Start briefly to enter the console settings.
    front_bios_start = 12;
    gfx::set_title("Gooswan - BIOS Settings");
    front_resync();
}
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
