var frontend_pass: i64 = 0;
var frontend_fail: i64 = 0;
fn frontend_check(name: const u8[:], ok: bool) {
    if ok { frontend_pass += 1; } else { frontend_fail += 1; print("FRONTEND FAIL ", name); }
}
fn frontend_test() {
    settings_defaults();
    frontend_check("defaults", settings.scale == 3 && settings.volume == 100 && settings.rotate_input && settings.pads[9] == 1);
    settings.scale = 4; settings.volume = 27; settings.rotation = 2;
    settings.linear = true; settings.fullscreen = true; settings.bios = 3;
    settings.keys[9] = app_text("Left Shift"); settings.pads[0] = 3;
    settings_recent("/roms/日本語/quote\"and\\slash.wsc");
    let encoded = settings_encode();
    frontend_check("TOML roundtrip parses", settings_parse(encoded));
    frontend_check("TOML roundtrip values", settings.scale == 4 && settings.volume == 27 && settings.rotation == 2 && settings.linear && settings.fullscreen && settings.bios == 3);
    frontend_check("TOML UTF8 and escapes", settings.recent[0].bytes[..settings.recent[0].len] == "/roms/日本語/quote\"and\\slash.wsc");
    frontend_check("TOML binding persistence", settings.keys[9].bytes[..settings.keys[9].len] == "Left Shift" && settings.pads[0] == 3);
    frontend_check("partial config", settings_parse("# comment\nvolume = 20\nunknown = { ignored = true }\n"));
    frontend_check("missing keys default", settings.scale == 3 && settings.volume == 20 && settings.rotate_input);
    frontend_check("range normalization", settings_parse("scale = 900\nvolume = -1\nrotation = 8\nbios = 9\n[gamepad]\nA = 100\n"));
    frontend_check("clamped values", settings.scale == 4 && settings.volume == 0 && settings.rotation == 2 && settings.bios == 3 && settings.pads[9] == 25);
    frontend_check("malformed config rejected", !settings_parse("scale = [\n")); hostconfig_free();
    frontend_check("unknown key binding parses", settings_parse("[keyboard]\nA = 'not a real key'\n"));
    frontend_check("unknown key uses default", settings.keys[9].bytes[..settings.keys[9].len] == "X");
    frontend_check("wrong types use defaults", settings_parse("scale = 'three'\nvolume = false\n"));
    frontend_check("typed defaults", settings.scale == 3 && settings.volume == 100);
    for n in 15 { settings_recent(str("/roms/", n, ".ws")); }
    frontend_check("history limited", settings.recent_count == 10);
    settings_recent("/roms/10.ws");
    frontend_check("history dedup moves to front", settings.recent_count == 10 && settings.recent[0].bytes[..settings.recent[0].len] == "/roms/10.ws");
    frontend_check("rotation left", front_rotate_pads(core::KEY_X1 | core::KEY_Y4 | core::KEY_A, 2) == (core::KEY_X2 | core::KEY_Y1 | core::KEY_A));
    frontend_check("rotation right", front_rotate_pads(core::KEY_X1 | core::KEY_START, 1) == (core::KEY_X4 | core::KEY_START));
    frontend_check("rotation normal", front_rotate_pads(0xFFF, 0) == 0xFFF);
    frontend_check("video normal is row-major", front_video_pixel_index(7, 19, 0) == 19 * core::SCREEN_W + 7);
    frontend_check("video rotates right", front_video_pixel_index(7, 19, 1) == 7 * core::SCREEN_H + (core::SCREEN_H - 20));
    frontend_check("video rotates left", front_video_pixel_index(7, 19, 2) == (core::SCREEN_W - 8) * core::SCREEN_H + 19);
    // Explicitly isolated path, so this test never changes real user settings.
    var tmp: u8[>..] = [];
    env("TMPDIR", tmp); if tmp.len == 0 { env("TEMP", tmp); } if tmp.len == 0 { tmp = str("/tmp"); }
    settings_dir = str(tmp, "/gooswan-settings-test-", clock_ns());
    frontend_check("create config directory", app_mkdirs(settings_dir));
    link_open_dialog();
    frontend_check("missing account link opens pairing", !link_account_linked && link_show_pairing);
    frontend_check("save account fixture", write_file(link_token_path(), "fixture"));
    link_open_dialog();
    frontend_check("saved account opens room controls", link_account_linked && !link_show_pairing);
    link_needs_relink = true;
    link_open_dialog();
    frontend_check("rejected account link reopens pairing", !link_account_linked && link_show_pairing);
    link_needs_relink = false;
    link_dialog = false;
    delete_file(link_token_path());
    settings_writable = true;
    frontend_check("atomic save", settings_save());
    var data: u8[>..] = [];
    frontend_check("saved file parses", read_file(config_path("settings.toml"), data) && settings_parse(data));
    var absolute: u8[4096] = [0; 4096];
    let absolute_len = host_absolute_path(config_path("settings.toml"), absolute[..]);
    frontend_check("canonical UTF8 path", absolute_len > 0 && absolute_len < 4096);
    settings_writable = false;
    frontend_check("protected config not overwritten", !settings_save());
    frontend_bios_eeprom_test();
    delete_file(config_path("settings.toml")); delete_dir(settings_dir);
    print("frontend_test: ", frontend_pass, " passed, ", frontend_fail, " failed");
    if frontend_fail > 0 { exit(1); }
}

// BIOS persistence regressions use the same transition/save routines as the
// GUI, without opening a window or touching the user's ROM/BIOS files.
fn frontend_set_internal(value: u8) {
    let data: u8[2048] = [value; 2048];
    core::save_load(core::SAVE_INTERNAL_EEPROM, data[..]);
}
fn frontend_internal_is(value: u8) -> bool {
    var data: u8[>..] = [];
    core::save_read(core::SAVE_INTERNAL_EEPROM, data);
    let expected: u8[2048] = [value; 2048];
    return data[..] == expected[..];
}
fn frontend_saved_internal_is(path: const u8[:], value: u8) -> bool {
    var data: u8[>..] = [];
    let expected: u8[2048] = [value; 2048];
    return read_file(path, data) && data[..] == expected[..];
}
fn frontend_bios_eeprom_test() {
    front_loaded = false; front_path = []; front_bios_kind = 0;
    frontend_check("create isolated BIOS directory", app_mkdirs(config_path("bios")));
    var bios: u8[4096] = [0; 4096]; bios[4080] = 0xF4;
    for kind in 1..4 {
        settings.bios = kind;
        frontend_check("create synthetic BIOS", write_file(front_bios_path(), bios[..]));
    }
    settings.bios = 1;
    front_start_bios();
    frontend_check("BIOS-only first boot uses defaults", front_loaded && front_path.len == 0 && front_bios_kind == 1 && frontend_internal_is(0));
    frontend_set_internal(0x11);
    frontend_check("BIOS-only media save succeeds", front_save_media());
    frontend_check("BIOS-only media save writes EEPROM", frontend_saved_internal_is(bios_eeprom_path(1), 0x11));
    front_reset();
    frontend_check("BIOS reset restores EEPROM", frontend_internal_is(0x11));
    // Changing the UI selection must not redirect the running BIOS's save.
    settings.bios = 2; frontend_set_internal(0x22);
    frontend_check("save uses active BIOS rather than selection", front_save_media() && frontend_saved_internal_is(bios_eeprom_path(1), 0x22) && !file_exists(bios_eeprom_path(2)));
    front_start_bios();
    frontend_check("different BIOS has separate defaults", front_bios_kind == 2 && frontend_internal_is(0));
    frontend_set_internal(0x33);
    frontend_check("shutdown save persists current BIOS", front_save_media() && frontend_saved_internal_is(bios_eeprom_path(2), 0x33));
    // Clear frontend/core state as a fresh process would, then boot from disk.
    front_loaded = false; front_path = []; front_bios_kind = 0;
    core::power_on(bios[..]); front_start_bios();
    frontend_check("restart restores saved BIOS EEPROM", front_bios_kind == 2 && frontend_internal_is(0x33));
    settings.bios = 1; front_start_bios();
    frontend_check("switching back restores other BIOS EEPROM", front_bios_kind == 1 && frontend_internal_is(0x22));
    var cart: u8[65536] = [0; 65536]; cart[65520] = 0xF4;
    let path = config_path("eeprom-test.ws");
    frontend_check("create cartridge fixture", write_file(path, cart[..]));
    let legacy: u8[2048] = [0x44; 2048];
    frontend_check("create legacy ROM EEPROM", write_file(save_path(path, core::SAVE_INTERNAL_EEPROM), legacy[..]));
    front_load(path);
    frontend_check("ROM switch keeps BIOS settings over old sidecar", front_path.len > 0 && front_bios_kind == 1 && frontend_internal_is(0x22));
    frontend_set_internal(0x55);
    frontend_check("BIOS cartridge updates console and legacy sidecar", front_save_media() && frontend_saved_internal_is(bios_eeprom_path(1), 0x55) && frontend_saved_internal_is(save_path(path, core::SAVE_INTERNAL_EEPROM), 0x55));
    settings.bios = 0; front_reset();
    frontend_check("direct boot retains ROM-local EEPROM", front_bios_kind == 0 && frontend_internal_is(0x55));
    frontend_set_internal(0x66);
    frontend_check("direct boot does not overwrite BIOS EEPROM", front_save_media() && frontend_saved_internal_is(bios_eeprom_path(1), 0x55));
    settings.bios = 1; front_start_bios();
    frontend_check("BIOS setup survives direct cartridge session", front_bios_kind == 1 && frontend_internal_is(0x55));
    // A first cartridge boot can import its old sidecar when no console save exists.
    settings.bios = 3; front_load(path);
    frontend_check("missing console save imports legacy EEPROM", front_bios_kind == 3 && frontend_internal_is(0x66));
    frontend_check("legacy EEPROM becomes persistent console save", front_save_media() && frontend_saved_internal_is(bios_eeprom_path(3), 0x66));
    // Failed load/save operations must leave the machine and original data intact.
    frontend_check("create corrupt EEPROM fixture", write_file(bios_eeprom_path(2), "bad"));
    settings.bios = 2; front_start_bios();
    frontend_check("corrupt EEPROM does not replace active machine", front_bios_kind == 3 && front_path.len > 0 && frontend_internal_is(0x66));
    var damaged: u8[>..] = [];
    frontend_check("corrupt EEPROM remains untouched", read_file(bios_eeprom_path(2), damaged) && damaged == "bad");
    let previous_dir = str(settings_dir);
    frontend_check("create blocked save directory fixture", write_file(config_path("blocked"), "file"));
    settings_dir = str(previous_dir, "/blocked"); front_path = [];
    frontend_check("BIOS EEPROM write failure is reported", !front_save_media() && frontend_internal_is(0x66));
    settings_dir = str(previous_dir);
    front_loaded = false; front_bios_kind = 0;
    delete_file(config_path("blocked")); delete_file(path); delete_file(save_path(path, core::SAVE_INTERNAL_EEPROM));
    for kind in 1..4 { settings.bios = kind; delete_file(front_bios_path()); delete_file(bios_eeprom_path(kind)); }
    delete_dir(config_path("bios"));
}

// Native or headless UI integration smoke. Run with an isolated
// GOOSWAN_CONFIG_DIR; screenshots stay in that directory.
var front_smoke:                bool    = false;
var front_smoke_ready_seen:     bool    = false;
var front_smoke_link_fixture:   bool    = false;
var front_smoke_tick:           i64     = 0;
var front_smoke_wait:           f64     = 0.0;
var front_smoke_dialog:         bool    = false;
var front_smoke_dialog_waiting: bool    = false;
var front_smoke_rom_path:       u8[>..] = [];
fn front_smoke_before() {
    if !front_smoke { return; }
    if front_smoke_dialog_waiting {
        if front_dialog { return; }
        frontend_check("native file picker selected ROM", front_dialog_result == 1 && front_loaded && !front_fault);
        write_file(config_path("dialog-result.txt"), str("result=", front_dialog_result, " loaded=", front_loaded));
        front_smoke_dialog_waiting = false;
    }
    gfx::inject_focus(true);
    if gfx::time() < front_smoke_wait { return; }
    front_smoke_tick += 1;
    let t = front_smoke_tick;
    if t == 1 { frontend_check("ROM-less startup", !front_loaded); gfx::inject_key("Left Ctrl", true); gfx::inject_key(",", true); }
    if t == 2 { frontend_check("settings shortcut", front_settings); gfx::inject_key(",", false); gfx::inject_key("Left Ctrl", false); }
    if t == 12 { front_section = 1; }
    if t == 22 { front_capture = 9; front_capture_pad = false; gfx::inject_key("C", true); }
    if t == 23 { frontend_check("keyboard capture", front_capture < 0 && settings.keys[9].bytes[..settings.keys[9].len] == "C"); gfx::inject_key("C", false); }
    if t == 24 { gfx::inject_key("Escape", true); }
    if t == 25 { frontend_check("settings escape", !front_settings); gfx::inject_key("Escape", false); }
    if t == 28 { front_load(front_smoke_rom_path); }
    if t == 32 {
        let scale = max(hostwindow_scale(), 1.0);
        gfx::inject_mouse(24.0 * scale, 12.0 * scale, gfx::MOUSE_LEFT, true);
    }
    if t == 33 {
        let scale = max(hostwindow_scale(), 1.0);
        gfx::inject_mouse(24.0 * scale, 12.0 * scale, gfx::MOUSE_LEFT, false);
    }
    if t == 36 { frontend_check("File menu opens", front_menu_open); }
    if t == 37 { let scale = max(hostwindow_scale(), 1.0); gfx::inject_mouse(70.0 * scale, 154.0 * scale, gfx::MOUSE_LEFT, true); }
    if t == 38 { let scale = max(hostwindow_scale(), 1.0); gfx::inject_mouse(70.0 * scale, 154.0 * scale, gfx::MOUSE_LEFT, false); }
    if t == 39 {
        frontend_check("menu opens Settings", front_settings);
        frontend_check("menu click does not change BIOS", settings.bios == 0);
    }
    if t == 40 { let scale = max(hostwindow_scale(), 1.0); gfx::inject_mouse(594.0 * scale, 47.0 * scale, gfx::MOUSE_LEFT, true); }
    if t == 41 { let scale = max(hostwindow_scale(), 1.0); gfx::inject_mouse(594.0 * scale, 47.0 * scale, gfx::MOUSE_LEFT, false); }
    if t == 42 { frontend_check("settings close button", !front_settings); front_open_about(); }
    if t == 48 { front_about = false; front_set_rotation(2); }
    if t == 54 { front_set_rotation(1); }
    if t == 60 { front_set_rotation(0); front_set_scale(4); }
    if t == 66 { gfx::inject_key("Left Ctrl", true); gfx::inject_key("P", true); }
    if t == 67 { frontend_check("pause shortcut", front_paused); gfx::inject_key("P", false); gfx::inject_key("Left Ctrl", false); }
    if t == 70 {
        frontend_check("GUI reports no misuse", gfx::misuse_count() == 0);
    }
    if t == 72 && hostwindow_present() { front_toggle_fullscreen(); front_smoke_wait = gfx::time() + 1.5; }
    if t == 73 && hostwindow_present() { frontend_check("fullscreen entered", hostwindow_is_fullscreen()); }
    if t == 76 && hostwindow_present() { front_toggle_fullscreen(); front_smoke_wait = gfx::time() + 1.5; }
    if t == 77 && hostwindow_present() { frontend_check("fullscreen exited", !hostwindow_is_fullscreen()); }
    if t == 80 && front_smoke_dialog { front_pick_rom(); front_smoke_dialog_waiting = true; }
    if t == 82 && !file_exists(link_token_path()) { front_smoke_link_fixture = true; link_open_dialog(); frontend_check("Link Play opens account setup", link_dialog && link_show_pairing); }
    if t == 85 && front_smoke_link_fixture {
        // Render the linked view without pairing to the live service.
        link_account_linked = true; link_show_pairing = false;
    }
    if t == 89 {
        // The worker waits for its first command. This exercises the real
        // Ready button without joining a live room.
        let worker = hostlink_open("unused");
        frontend_check("Ready test starts isolated worker", worker);
        if !worker { return; }
        link_stage = LinkStage.Seated;
        link_peer = true;
        link_open_dialog();
    }
    if t == 91 && link_stage == LinkStage.Seated {
        gfx::inject_mouse(gfx::screen_size().x / 2.0, 136.0 * max(hostwindow_scale(), 1.0), gfx::MOUSE_LEFT, true);
    }
    if t == 92 && link_stage == LinkStage.Seated {
        gfx::inject_mouse(gfx::screen_size().x / 2.0, 136.0 * max(hostwindow_scale(), 1.0), gfx::MOUSE_LEFT, false);
    }
    if t == 96 { frontend_check("Ready leaves the UI usable", gfx::misuse_count() == 0); front_running = false; }
}
fn front_smoke_after() {
    if !front_smoke { return; }
    let t = front_smoke_tick;
    let name = if t == 1 { "welcome" } else if t == 10 { "settings-rom" } else if t == 20 { "settings-input" } else if t == 30 { "main" } else if t == 36 { "file-menu" } else if t == 46 { "about" } else if t == 52 { "rotate-left" } else if t == 58 { "rotate-right" } else if t == 83 { "link-account" } else if t == 86 { "link-room" } else { "" };
    if name.len > 0 { frontend_check("screenshot", gfx::screenshot(config_path(str(name, ".png")))); }
    if t >= 91 && link_ready && link_stage == LinkStage.Seated {
        front_smoke_ready_seen = true;
        // Stop before link_poll writes the Ready frame to the unseated worker.
        hostlink_stop();
        link_stage = LinkStage.Idle; link_peer = false; link_ready = false; link_dialog = false;
    }
    if t == 96 {
        frontend_check("Ready keeps the room open", front_smoke_ready_seen);
        let result = str("ui_smoke: ", frontend_pass, " passed, ", frontend_fail, " failed");
        print(result);
        write_file(config_path("ui-smoke-result.txt"), result);
        if frontend_fail > 0 { exit(1); }
    }
}

// Native dialogs may consume the release that followed the Open ROM click.
// Exercise the recovery with real gfx/Nuklear contexts and missing releases.
fn frontend_dialog_frame() {
    if !gfx::frame() { frontend_check("dialog test frame", false); return; }
    ui::input_from_gfx(front_ui);
    front_draw_ui();
    gfx::begin_screen(float4 { 0.0, 0.0, 0.0, 1.0 }); gfx::end_pass();
    ui::render(front_ui);
}
fn frontend_dialog_test() {
    settings_defaults(); settings_writable = false;
    if !gfx::open_headless(672, 482) { print("dialog_test gfx: ", gfx::error()); exit(1); }
    front_ui = front_make_ui(); front_apply_theme();
    frontend_dialog_frame();
    // Hovering the menu bar must not capture the emulated console's keys.
    gfx::inject_mouse(16.0, 12.0, gfx::MOUSE_LEFT, false);
    gfx::inject_key("X", true); frontend_dialog_frame();
    frontend_check("menu bar hover exercises mouse capture", ui::wants_mouse(front_ui));
    frontend_check("menu bar hover allows game keys", front_keys() == core::KEY_A);
    front_settings = true;
    frontend_check("settings blocks game keys", front_keys() == 0);
    front_settings = false;
    front_menu_open = true;
    frontend_check("open menu blocks game keys", front_keys() == 0);
    front_menu_open = false;
    gfx::inject_focus(false); frontend_dialog_frame();
    frontend_check("unfocused window blocks game keys", front_keys() == 0);
    gfx::inject_focus(true); gfx::inject_key("X", false); frontend_dialog_frame();
    gfx::inject_mouse(16.0, 12.0, gfx::MOUSE_LEFT, true); frontend_dialog_frame();
    gfx::inject_mouse(16.0, 12.0, gfx::MOUSE_LEFT, false); frontend_dialog_frame();
    frontend_check("File menu opens before native dialog", front_menu_open);
    gfx::inject_mouse(65.0, 44.0, gfx::MOUSE_LEFT, true); frontend_dialog_frame();
    frontend_check("Open ROM menu action selected", front_action == FrontAction.PickRom);
    front_action = FrontAction.None; front_dialog = true;
    // Both the button-up and modifier-up can be consumed by a modal loop.
    ui::input_begin(front_ui); ui::input_key(front_ui, ui::KEY_CTRL, true); ui::input_end(front_ui);
    let context = front_ui.id;
    front_finish_dialog(2, "");
    frontend_check("Cancel clears dialog flag", !front_dialog && front_dialog_result == 2);
    frontend_check("Cancel releases Nuklear mouse", !ui::input_is_mouse_down(front_ui, ui::BUTTON_LEFT));
    frontend_check("Cancel releases Nuklear modifier", !ui::input_is_key_down(front_ui, ui::KEY_CTRL));
    frontend_check("Cancel preserves current UI context", front_ui.id == context);
    frontend_dialog_frame();
    frontend_check("Cancel releases gfx mouse cache", !gfx::mouse_down(gfx::MOUSE_LEFT));
    gfx::inject_mouse(16.0, 12.0, gfx::MOUSE_LEFT, true); frontend_dialog_frame();
    gfx::inject_mouse(16.0, 12.0, gfx::MOUSE_LEFT, false); frontend_dialog_frame();
    frontend_check("File menu reopens after Cancel", front_menu_open);
    gfx::inject_mouse(60.0, 154.0, gfx::MOUSE_LEFT, true); frontend_dialog_frame();
    frontend_check("Settings menu works after Cancel", front_action == FrontAction.OpenSettings);
    front_do_action();
    gfx::inject_mouse(60.0, 154.0, gfx::MOUSE_LEFT, false); frontend_dialog_frame();
    frontend_check("Settings window opens after Cancel", front_settings);
    // Cancelling a keyboard-opened picker must return focus to that dialog.
    front_dialog = true; front_finish_dialog(2, ""); frontend_dialog_frame();
    frontend_check("Cancel preserves open settings", front_settings && !front_dialog);
    front_close_settings(); frontend_dialog_frame();
    // A native error has the same recovery and must allow another Open action.
    front_dialog = true; front_finish_dialog(-1, ""); frontend_dialog_frame();
    gfx::inject_mouse(16.0, 12.0, gfx::MOUSE_LEFT, true); frontend_dialog_frame();
    gfx::inject_mouse(16.0, 12.0, gfx::MOUSE_LEFT, false); frontend_dialog_frame();
    frontend_check("File menu reopens after native error", front_menu_open && !front_dialog);
    gfx::inject_mouse(65.0, 44.0, gfx::MOUSE_LEFT, true); frontend_dialog_frame();
    frontend_check("Open ROM can be requested again", front_action == FrontAction.PickRom);
    ui::destroy(front_ui); if front_font_atlas.id != 0 { ui::destroy(front_font_atlas); }
    gfx::close();
    print("dialog_test: ", frontend_pass, " passed, ", frontend_fail, " failed");
    if frontend_fail > 0 { exit(1); }
}

// Interactive native regression: only the Cancel button requires user/GUI
// automation. Focus injection is used once at startup, never after the modal.
var front_cancel_live:     bool = false;
var front_cancel_step:     i64  = 0;
var front_cancel_deadline: f64  = 0.0;
fn front_cancel_before() {
    if !front_cancel_live { return; }
    front_cancel_step += 1;
    let step = front_cancel_step; let density = max(hostwindow_scale(), 1.0);
    if step == 1 { gfx::inject_focus(true); }
    if step == 3 { gfx::inject_mouse(16.0 * density, 12.0 * density, gfx::MOUSE_LEFT, true); }
    if step == 4 { gfx::inject_mouse(16.0 * density, 12.0 * density, gfx::MOUSE_LEFT, false); }
    if step == 5 { frontend_check("native File menu opens", front_menu_open); }
    if step == 6 { gfx::inject_mouse(65.0 * density, 44.0 * density, gfx::MOUSE_LEFT, true); }
    if step == 7 { gfx::inject_mouse(65.0 * density, 44.0 * density, gfx::MOUSE_LEFT, false); }
    if step == 8 {
        if front_dialog { front_cancel_step -= 1; return; }
        frontend_check("native Cancel completed", front_dialog_result == 2 && !front_loaded);
        front_cancel_deadline = gfx::time() + 3.0;
    }
    if step == 9 {
        if !gfx::focused() && gfx::time() < front_cancel_deadline { front_cancel_step -= 1; return; }
        frontend_check("native focus restored without test injection", gfx::focused());
        gfx::inject_mouse(16.0 * density, 12.0 * density, gfx::MOUSE_LEFT, true);
    }
    if step == 10 { gfx::inject_mouse(16.0 * density, 12.0 * density, gfx::MOUSE_LEFT, false); }
    if step == 11 { frontend_check("native File menu reopens after Cancel", front_menu_open); }
    if step == 12 { gfx::inject_mouse(60.0 * density, 154.0 * density, gfx::MOUSE_LEFT, true); }
    if step == 13 { gfx::inject_mouse(60.0 * density, 154.0 * density, gfx::MOUSE_LEFT, false); }
    if step == 14 {
        frontend_check("native Settings works after Cancel", front_settings);
        let result = str("cancel_test: ", frontend_pass, " passed, ", frontend_fail, " failed");
        print(result); write_file(config_path("cancel-test-result.txt"), result);
        front_running = false;
        if frontend_fail > 0 { exit(1); }
    }
}
