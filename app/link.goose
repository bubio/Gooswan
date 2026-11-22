// Link Play dialog, room lifecycle and the transport boundary to the core.
extern fn hostlink_open(token_path: const u8[:]) -> bool;
extern fn hostlink_stop();
extern fn hostlink_send(kind: u8, payload: const u8[:]) -> bool;
extern fn hostlink_poll(frame: u8[:]) -> i64;
extern fn hostlink_open_site(account: bool) -> bool;

enum LinkStage { Idle, Pairing, Joining, Seated, Linked }
var link_stage = LinkStage.Idle;
var link_dialog:     bool    = false;
var link_reopen:     bool    = false;
var link_peer:       bool    = false;
var link_ready:      bool    = false;
var link_code:       u8[64]  = [0; 64];
var link_code_len:   i64     = 0;
var link_device:     u8[64]  = [0; 64];
var link_device_len: i64     = 0;
var link_message:    u8[>..] = [];

fn link_active() -> bool { return link_stage == LinkStage.Seated || link_stage == LinkStage.Linked; }
fn link_token_path() -> u8[>..] { return config_path("swan-revival-token"); }

fn link_end(message: const u8[:]) {
    let was_active = link_active();
    hostlink_stop();
    core::serial_detach();
    link_stage = LinkStage.Idle;
    link_peer = false; link_ready = false;
    link_message = str(message);
    if was_active { front_resync(); }
    if message.len > 0 { front_notify(message); }
}
fn link_begin(pair: bool, code: const u8[:]) {
    if link_stage != LinkStage.Idle || code.len == 0 { return; }
    if settings_dir.len == 0 || !hostlink_open(link_token_path()) {
        link_end("Could not start the Swan Revival worker"); return;
    }
    if !hostlink_send(if pair { 'A' } else { 'J' }, code) {
        link_end("Could not start Swan Revival"); return;
    }
    link_stage = if pair { LinkStage.Pairing } else { LinkStage.Joining };
    link_message = [];
}
fn link_set_ready() {
    if link_stage != LinkStage.Seated || !link_peer || link_ready { return; }
    if !hostlink_send('R', "") { link_end("Could not send Ready"); return; }
    link_ready = true;
}
fn link_poll() {
    if link_stage == LinkStage.Idle { return; }
    var frame: u8[8193] = [0; 8193];
    for i in 16 {
        let n = hostlink_poll(frame[..]);
        if n == 0 { return; }
        if n < 0 { link_end("Swan Revival connection closed"); return; }
        if frame[0] == 'E' { link_end(frame[1..n]); return; }
        if frame[0] == 'A' && link_stage == LinkStage.Pairing { link_end("Swan Revival account linked"); return; }
        if frame[0] == 'J' && link_stage == LinkStage.Joining {
            let path = str(front_path);
            // Power on with the cable present before the game reaches its link menu.
            if !front_load_rom(path, true) { link_end("Could not restart the ROM for link play"); return; }
            front_paused = false;
            core::serial_attach(); link_stage = LinkStage.Seated;
            front_notify("Select Ready when both players have joined");
        } else if frame[0] == 'P' && n == 2 && link_stage == LinkStage.Seated {
            link_peer = frame[1] != 0;
            if !link_peer { link_ready = false; }
        } else if frame[0] == 'S' && n == 2 && link_stage == LinkStage.Seated {
            core::serial_start(frame[1]); link_stage = LinkStage.Linked;
            front_notify("Swan Revival cable connected");
        } else if frame[0] == 'D' && link_stage == LinkStage.Linked {
            if !core::serial_receive(frame[1..n]) { link_end("Swan Revival cable data overflow"); return; }
        } else {
            link_end("Invalid response from the Swan Revival worker"); return;
        }
    }
}
fn link_flush() {
    if link_stage != LinkStage.Linked { return; }
    var data: u8[>..] = [];
    if !core::serial_take_output(data) {
        link_end("Swan Revival send buffer overflow"); return;
    }
    var at: i64 = 0;
    while at < data.len {
        let end = min(at + 384, data.len);
        if !hostlink_send('D', data[at..end]) { link_end("Swan Revival send buffer overflow"); return; }
        at = end;
    }
}

fn link_open_dialog() {
    front_settings = false; front_capture = -1; front_about = false; front_recent = false;
    link_dialog = true; link_reopen = true;
}
fn link_draw_dialog(ww: f32, hh: f32) {
    let c = front_ui;
    let w = min(386.0, ww - 16.0);
    let h = min(240.0, hh - front_chrome_height() - 12.0);
    let bounds = ui::rect((ww - w) / 2.0, FRONT_MENU_HEIGHT + 6.0, w, h);
    front_prepare_dialog("Swan Revival Link Play", bounds, link_reopen);
    link_reopen = false;
    if ui::begin(c, "Swan Revival Link Play", bounds, front_content_window_flags(ui::WINDOW_BORDER | ui::WINDOW_TITLE | ui::WINDOW_MOVABLE | ui::WINDOW_CLOSABLE)) {
        ui::layout_row_dynamic(c, 25.0, 2);
        if ui::button_label(c, "Swan Revival account") { hostlink_open_site(true); }
        if ui::button_label(c, "Open lobby") { hostlink_open_site(false); }
        ui::layout_row_dynamic(c, 24.0, 1);
        match link_stage {
            Idle => {
                ui::label(c, if front_path.len == 0 { "Open the room's game first" } else { "Room code" }, ui::TEXT_LEFT);
                ui::layout_row_dynamic(c, 25.0, 2);
                ui::edit_string(c, ui::EDIT_FIELD, link_code[..], link_code_len, ui::FILTER_ASCII);
                if front_path.len == 0 { ui::widget_disable_begin(c); }
                if ui::button_label(c, "Join") && front_path.len > 0 { link_begin(false, link_code[..link_code_len]); }
                if front_path.len == 0 { ui::widget_disable_end(c); }
                ui::layout_row_dynamic(c, 24.0, 1);
                ui::label(c, "One-time device code", ui::TEXT_LEFT);
                ui::layout_row_dynamic(c, 25.0, 2);
                ui::edit_string(c, ui::EDIT_FIELD, link_device[..], link_device_len, ui::FILTER_ASCII);
                if ui::button_label(c, "Link account") {
                    link_begin(true, link_device[..link_device_len]);
                    for i in link_device.len { link_device[i] = 0; }
                    link_device_len = 0;
                }
                ui::layout_row_dynamic(c, 24.0, 1);
                ui::label(c, link_message, ui::TEXT_LEFT);
            },
            Pairing => ui::label(c, "Linking account…", ui::TEXT_LEFT),
            Joining => ui::label(c, "Joining room…", ui::TEXT_LEFT),
            Seated => {
                ui::label(c, if !link_peer { "Waiting for another player…" } else if link_ready { "Waiting for the other player to be ready…" } else { "Select Ready to connect the cable." }, ui::TEXT_LEFT);
                if !link_peer || link_ready { ui::widget_disable_begin(c); }
                if ui::button_label(c, "Ready") { link_set_ready(); }
                if !link_peer || link_ready { ui::widget_disable_end(c); }
            },
            Linked => ui::label(c, "Cable connected", ui::TEXT_LEFT),
        }
        if link_stage != LinkStage.Idle && ui::button_label(c, "Leave or cancel") { link_end("Left Swan Revival"); }
    }
    ui::end(c);
    if ui::window_is_hidden(c, "Swan Revival Link Play") { link_dialog = false; }
}

// Also run from a relocated app so every package exercises its real worker.
fn link_test_worker() {
    var frame: u8[8193] = [0; 8193];
    if hostlink_open("unused") && hostlink_send('J', "!") {
        for i in 1000 {
            let n = hostlink_poll(frame[..]);
            if n < 0 { break; }
            if n > 0 {
                hostlink_stop();
                if frame[0] == 'E' && frame[1..n] == "Enter a six-character Swan Revival room code" {
                    print("Swan Revival worker: pass"); return;
                }
                break;
            }
            sleep_ms(5);
        }
    }
    hostlink_stop();
    print("Swan Revival worker: failed");
    exit(1);
}
