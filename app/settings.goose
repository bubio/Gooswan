// Host-only configuration. TOML parsing is delegated to the vendored MIT
// tomlc99 library; serialization stays explicit and human readable.
struct AppText { bytes: u8[4096] = [0; 4096], len: i64 = 0 }
fn app_text(s: const u8[:]) -> AppText {
    var t = default<AppText>();
    t.len = min(s.len, 4096);
    for i in t.len { t.bytes[i] = s[i]; }
    return t;
}
fn toml_quote(out: u8[>..]&, s: const u8[:]) {
    out.push(34);
    let hex = "0123456789abcdef";
    for c in s {
        if c == 34 || c == 92 { out.push(92); out.push(c); }
        else if c < 32 || c == 127 {
            out.append("\\u00"); out.push(hex[c >> 4]); out.push(hex[c & 15]);
        } else { out.push(c); }
    }
    out.push(34);
}
let BUTTON_LABELS: const u8[:][11] = ["Y1", "Y2", "Y3", "Y4", "X1", "X2", "X3", "X4", "Start", "A", "B"];
let BUTTON_BITS: i64[11] = [
    core::KEY_Y1, core::KEY_Y2, core::KEY_Y3, core::KEY_Y4,
    core::KEY_X1, core::KEY_X2, core::KEY_X3, core::KEY_X4,
    core::KEY_START, core::KEY_A, core::KEY_B,
];
let DEFAULT_KEYS: const u8[:][11] = ["W", "D", "S", "A", "Up", "Right", "Down", "Left", "Return", "X", "Z"];
// Match Swanium: X-pad on D-pad, A on east, B on south; Y-pad unbound.
let DEFAULT_PADS: i64[11] = [-1, -1, -1, -1, 11, 14, 12, 13, 6, 1, 0];
struct Settings {
    scale:        i64         = 3,
    volume:       i64         = 100,
    fullscreen:   bool        = false,
    rotation:     i64         = 0,
    linear:       bool        = false,
    rotate_input: bool        = true,
    bios:         i64         = 0,
    recent:       AppText[10] = [default<AppText>(); 10],
    recent_count: i64         = 0,
    keys:         AppText[11] = [default<AppText>(); 11],
    pads:         i64[11]     = [-1; 11],
}
var settings = default<Settings>();
var settings_dir:      u8[>..] = [];
var settings_writable: bool    = true;
var settings_notice:   u8[>..] = [];
extern fn hostconfig_dir(out: u8[:]) -> i64;
extern fn hostconfig_parse(source: const u8[:]) -> bool;
extern fn hostconfig_free();
extern fn hostconfig_int(section: const u8[:], key: const u8[:], fallback: i64) -> i64;
extern fn hostconfig_bool(section: const u8[:], key: const u8[:], fallback: bool) -> bool;
extern fn hostconfig_string(section: const u8[:], key: const u8[:], index: i64, out: u8[:]) -> i64;
extern fn host_open_directory(path: const u8[:]) -> bool;

fn settings_defaults() {
    settings = default<Settings>();
    for i in 11 { settings.keys[i] = app_text(DEFAULT_KEYS[i]); settings.pads[i] = DEFAULT_PADS[i]; }
}
fn app_mkdirs(path: const u8[:]) -> bool {
    if path.len == 0 { return false; }
    for i in 1..path.len {
        if path[i] == '/' || path[i] == 92 { make_dir(path[..i]); }
    }
    return make_dir(path);
}
fn config_path(name: const u8[:]) -> u8[>..] { return str(settings_dir, "/", name); }
fn settings_parse(source: const u8[:]) -> bool {
    if !hostconfig_parse(source) { return false; }
    settings_defaults();
    settings.scale = clamp(hostconfig_int("", "scale", settings.scale), 1, 4);
    settings.volume = clamp(hostconfig_int("", "volume", settings.volume), 0, 100);
    settings.fullscreen = hostconfig_bool("", "fullscreen", settings.fullscreen);
    settings.rotation = clamp(hostconfig_int("", "rotation", settings.rotation), 0, 2);
    settings.linear = hostconfig_bool("", "bilinear", settings.linear);
    settings.rotate_input = hostconfig_bool("", "rotate_input_with_screen", settings.rotate_input);
    settings.bios = clamp(hostconfig_int("", "bios", settings.bios), 0, 3);
    for i in 10 {
        var name = default<AppText>();
        let n = hostconfig_string("", "recent_files", i, name.bytes[..]);
        if n < 0 { break; }
        if n == 0 || n > 4096 { continue; }
        name.len = n;
        settings.recent[settings.recent_count] = name; settings.recent_count += 1;
    }
    for i in 11 {
        var key = default<AppText>();
        let n = hostconfig_string("keyboard", BUTTON_LABELS[i], -1, key.bytes[..]);
        if n > 0 && n < 64 && gfx::scancode(key.bytes[..n]) != 0 { key.len = n; settings.keys[i] = key; }
        settings.pads[i] = clamp(hostconfig_int("gamepad", BUTTON_LABELS[i], DEFAULT_PADS[i]), -1, 25);
    }
    hostconfig_free();
    return true;
}
fn settings_encode() -> u8[>..] {
    var out = str("# Gooswan settings. BIOS: 0=direct, 1=WS, 2=WSC, 3=Crystal.\n",
        "scale = ", settings.scale, "\nvolume = ", settings.volume,
        "\nfullscreen = ", settings.fullscreen, "\nrotation = ", settings.rotation,
        "\nbilinear = ", settings.linear, "\nrotate_input_with_screen = ", settings.rotate_input,
        "\nbios = ", settings.bios, "\nrecent_files = [");
    for i in settings.recent_count {
        if i > 0 { out.append(", "); }
        toml_quote(out, settings.recent[i].bytes[..settings.recent[i].len]);
    }
    out.append("]\n\n[keyboard]\n");
    for i in 11 {
        out.append(str(BUTTON_LABELS[i], " = "));
        toml_quote(out, settings.keys[i].bytes[..settings.keys[i].len]); out.push(10);
    }
    out.append("\n[gamepad]\n");
    for i in 11 { out.append(str(BUTTON_LABELS[i], " = ", settings.pads[i], "\n")); }
    return out;
}
fn settings_save() -> bool {
    if !settings_writable || settings_dir.len == 0 { return false; }
    if !write_file_atomic(config_path("settings.toml"), settings_encode()) {
        settings_notice = str("Could not save settings.toml"); return false;
    }
    return true;
}
fn settings_load() {
    settings_defaults();
    if !env("GOOSWAN_CONFIG_DIR", settings_dir) {
        var path: u8[4096] = [0; 4096];
        let n = hostconfig_dir(path[..]);
        if n > 0 && n < 4096 { settings_dir.append(path[..n]); }
    }
    if !app_mkdirs(settings_dir) {
        settings_writable = false; settings_notice = str("Cannot create configuration directory"); return;
    }
    var data: u8[>..] = [];
    let path = config_path("settings.toml");
    if file_exists(path) {
        if !read_file(path, data) || !settings_parse(data) {
            settings_writable = false;
            settings_notice = str("Invalid settings.toml; using defaults. Original file preserved.");
            hostconfig_free();
        }
    }
}
fn settings_recent(path: const u8[:]) {
    if path.len > 4096 { return; }
    var at = settings.recent_count;
    for i in settings.recent_count { if settings.recent[i].bytes[..settings.recent[i].len] == path { at = i; break; } }
    var i = min(at, 9);
    while i > 0 { settings.recent[i] = settings.recent[i - 1]; i -= 1; }
    settings.recent[0] = app_text(path);
    settings.recent_count = min(settings.recent_count + (if at == settings.recent_count { 1 } else { 0 }), 10);
}
