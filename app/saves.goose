// Save-data persistence: the core hands out its save media as bytes;
// the frontend keeps them next to the ROM as <rom>.sav (cartridge
// SRAM), <rom>.eep (cartridge EEPROM, only when fitted) and <rom>.iep
// (the console's internal EEPROM), plus <rom>.rtc for a cartridge
// clock's registers. Loaded after power-on, written on ROM/BIOS switches,
// reset and exit. BIOS boots also persist the console EEPROM independently.

fn save_path(path: const u8[:], kind: i64) -> u8[>..] {
    let extension = match kind {
        core::SAVE_SRAM => ".sav",
        core::SAVE_CART_EEPROM => ".eep",
        core::SAVE_RTC => ".rtc",
        _ => ".iep",
    };
    return str(path, extension);
}

fn load_saves(path: const u8[:], load_internal: bool = true) {
    for kind in core::SAVE_KINDS {
        if kind == core::SAVE_INTERNAL_EEPROM && !load_internal { continue; }
        if core::save_size(kind) == 0 { continue; }
        var buf: u8[>..] = [];
        if read_file(save_path(path, kind), buf) { core::save_load(kind, buf); }
    }
}

fn save_saves(path: const u8[:]) -> bool {
    var ok = true;
    for kind in core::SAVE_KINDS {
        if core::save_size(kind) == 0 { continue; }
        var buf: u8[>..] = [];
        core::save_read(kind, buf);
        if !write_file_atomic(save_path(path, kind), buf) { ok = false; }
    }
    return ok;
}

// Console storage is keyed by the BIOS in use, never the next-boot setting.
// Cartridge sidecars are still written for backward compatibility.
fn bios_path(kind: i64, extension: const u8[:]) -> u8[>..] {
    let name = match kind { 1 => "ws_irom", 2 => "wsc_irom", _ => "wc_irom" };
    return config_path(str("bios/", name, extension));
}

fn bios_eeprom_path(kind: i64) -> u8[>..] { return bios_path(kind, ".iep"); }
fn read_bios_eeprom(bios_kind: i64, out: u8[>..]&) -> bool {
    if bios_kind < 1 || bios_kind > 3 || settings_dir.len == 0 { return false; }
    let path = bios_eeprom_path(bios_kind);
    if !file_exists(path) { return true; }
    return read_file(path, out) && out.len == core::save_size(core::SAVE_INTERNAL_EEPROM);
}
fn save_bios_eeprom(bios_kind: i64) -> bool {
    if bios_kind < 1 || bios_kind > 3 || settings_dir.len == 0 { return false; }
    if !app_mkdirs(config_path("bios")) { return false; }
    var data: u8[>..] = [];
    core::save_read(core::SAVE_INTERNAL_EEPROM, data);
    return write_file_atomic(bios_eeprom_path(bios_kind), data);
}

// Set a cartridge clock from the host's wall clock (UTC: the os
// package exposes no time zone), as Swanium's frontend does at load.
fn sync_rtc_to_host() {
    if !core::has_rtc() { return; }
    let secs: i64 = time_ns() / 1000000000;
    let days: i64 = secs / 86400;
    let rem:  i64 = secs % 86400;
    // civil_from_days (Howard Hinnant)
    let z:   i64 = days + 719468;
    let era: i64 = z / 146097;
    let doe: i64 = z - era * 146097;
    let yoe: i64 = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy: i64 = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp:  i64 = (5 * doy + 2) / 153;
    let d:   i64 = doy - (153 * mp + 2) / 5 + 1;
    let m:   i64 = if mp < 10 { mp + 3 } else { mp - 9 };
    let y:   i64 = yoe + era * 400 + (if m <= 2 { 1 } else { 0 });
    core::set_rtc_datetime(y, m, d, (days + 4) % 7, rem / 3600, (rem / 60) % 60, rem % 60);
}
