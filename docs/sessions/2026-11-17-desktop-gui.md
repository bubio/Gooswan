# Desktop GUI and Swanium feature parity

## Implemented

The Goose frontend now uses the pinned v2026.4 `ui`/Nuklear package over the
existing gfx renderer. It opens without a ROM and provides File / Emu / View
menus, native ROM selection, ten-entry recent history, pause/reset, 1–4x scale,
fullscreen, left/right rotation, aspect-ratio preservation, nearest/bilinear
sampling, status/FPS/master volume, settings and About windows.

Settings live in `settings.toml` under the OS configuration directory, with
`GOOSWAN_CONFIG_DIR` for isolated/portable operation. The MIT tomlc99 parser is
vendored at a fixed commit, while writing is explicit Goose code using atomic
replacement. Invalid TOML is preserved and not overwritten. Input mappings,
BIOS choice, display/audio settings and history persist. Unknown keyboard names
fall back to defaults rather than reaching gfx's fatal invalid-name check.

The host C adapter supplies SDL3 APIs absent from the fixed Goose release:
window size/fullscreen/DPI, gamepad polling, configuration directories, file
manager opening and native asynchronous dialogs. Dialog callbacks publish an
owned path under a mutex; the main loop performs the actual ROM change. CLI and
picker paths are canonicalized so their save-state slots agree.

Core additions are host-independent: BIOS overlays aligned to 4 KiB, disabled
by system-control bit 7, and versioned whole-machine snapshots. Snapshots carry
ROM identity and payload integrity, validate before restoring, and preserve
CPU/RAM/PPU/APU/DMA/EEPROM/RTC/frame-carry and BIOS overlay state. Host audio
queues are cleared on transitions. Existing cartridge save sidecars remain in
place; writes now use atomic replacement. Swanium state/config interchange is
not part of this change.

The UI uses system fonts, including CJK glyph ranges where available, with the
bundled bitmap font as a fallback. Settings/About are in-app windows, rather
than independent native windows. Optional licenses are included in release zips.

## Validation

On macOS ARM64:

- Core purity, Goose warning/format lint, native builds, C99 `-Wall -Wextra
  -Werror` syntax checks, shellcheck and actionlint passed.
- Existing self-tests: CPU 12, PPU 39, APU 83, EEPROM 25 passed.
- New state tests: 24 passed. Continuation matches the complete machine snapshot
  and audio after restore; damaged/truncated/version-mismatched/other-ROM states
  are rejected without mutation. Synthetic BIOS mapping, overlay disable,
  restore, execution and short-stub alignment are covered.
- Frontend self-tests: 24 passed. TOML roundtrip/UTF-8/escaping, partial settings, invalid
  syntax/types/key names, bounds, history, rotations, atomic file writes,
  protected settings and canonical paths.
- Full existing battery passed: 8086 634406/646000; WSHWTest Test All;
  three framebuffer goldens; WSTimingTest 400 passed / 7 known deferred cases.
- Native UI smoke passed 15 checks, including ROM-less startup, keyboard capture, settings/pause
  shortcuts, fullscreen entry/exit and seven captured screens.
- A separate native dialog smoke passed 15 checks after selecting the generated
  `smoke.ws` in the macOS file picker, confirming callback delivery and ROM load.
  Computer use required a temporary test app bundle under ignored `.goose/`.
  Its initial dialog-wait test used a decrementing frame counter that did not
  finish reliably; an explicit waiting state replaced it. The test app exits
  successfully and records its result under the isolated config directory.
- User-owned WS/WSC/SwanCrystal BIOS images each ran 300 frames and displayed
  the personal-data settings screen. BIOS bytes and generated captures are
  outside Git. A local copy of Final Fantasy 4 booted through the WSC BIOS and
  passed the 600-frame native framebuffer check with zero pixel mismatches.

Linux CI now includes a headless UI smoke using lavapipe. It has not been run
locally on Linux. Windows/Linux native behavior, physical gamepad hotplug and
remapping, audible output, fractional display scaling and additional real-game
coverage still require their respective platform/device checks. No broad
accuracy rewrite was attempted; the seven known timing cases remain deferred.

## Commands

```sh
sh scripts/build.sh --test
GOOSWAN_CONFIG_DIR="$PWD/.goose/ui-smoke" SDL_AUDIODRIVER=dummy ./app/gooswan --ui-smoke
# Interactive: choose the generated smoke.ws when the native picker opens.
GOOSWAN_CONFIG_DIR="$PWD/.goose/ui-dialog" SDL_AUDIODRIVER=dummy ./app/gooswan --ui-smoke-dialog
./tools/sst bios_test /path/to/bios.bin mono .goose/bios.ppm
```

## UI refinement using UsaProject as reference

After user review, the Nuklear UI was refined using UsaProject's
`docs/nuklear-reference.md`, `src/ui.zig`, `src/ui_dialog.zig` and `src/nk.zig`.
UsaProject itself was only read.

- Bundled the same OFL-licensed M PLUS 1p Regular font at 16 logical pixels,
  rather than relying on varying system fonts. The font and OFL notice are
  included in release archives.
- Reduced the menu/status chrome to 26/24 logical pixels, with grouped status
  text, a speaker/mute icon, a click/drag volume rail and a separate FPS value.
- Brightened checkbox/radio cursors, increased text contrast, used blue selected
  tabs and grouped the ROM/Input/Display settings. Settings no longer enlarge
  the main application window; their body scrolls independently of the footer.
- Made Settings/About/Recent dialogs movable and closable, with correct reopen
  handling. Recent history lives in its own scrollable dialog. A compact startup
  panel opens a ROM from the otherwise empty screen.
- Menu shortcuts use measured right-aligned text rather than space padding.
  Menu contents use scrollable groups so small windows can reach every action.
  Goose's UI API requires `menu_close` outside the group and rejects menu-item
  calls inside a group; styled buttons enqueue actions instead, and the menu
  closes only after its group ends.
- Background status chrome does not take focus. Dialog opening remains deferred
  until the current frame's widgets have consumed their input, preventing the
  menu-to-dialog click propagation described in UsaProject's reference.

Validation after refinement: native GUI smoke **21 passed / 0 failed**, including
menu-driven Settings opening, BIOS-selection preservation across that click,
Settings X-close, keyboard capture, fullscreen transitions and screenshots of
ROM/Input/Display settings, menus, welcome, About and rotation. Frontend tests
remain **24 passed / 0 failed**; build, formatting/lint and release ZIP contents
were checked. The core was not changed by this UI refinement.

### Settings tabs follow-up

At user request, removed the Display tab from Settings. Settings contains only
ROM and Input; all display controls remain in the View menu. Removed the unused
display-settings renderer and its obsolete smoke-test screenshot.


## BIOS internal EEPROM persistence fix

The review found that BIOS-only startup clears `front_path`, so the previous
`front_save_media` early return skipped EEPROM persistence on every save path.

- Track the BIOS actually in use separately from `settings.bios`, which selects
  the *next* boot. Save its internal EEPROM under the configuration directory's
  `bios/ws_irom.iep`, `bios/wsc_irom.iep` or `bios/wc_irom.iep`, even without a
  cartridge path. Periodic, transition and exit saves use the same entry point.
- Validate/read the console EEPROM before changing the live machine, then
  restore it after power-on. A saved console EEPROM takes precedence over an
  old cartridge `.iep`; when no console save exists, import the cartridge's
  existing `.iep`. Continue writing cartridge sidecars for compatibility.
  Direct boot retains the existing per-ROM EEPROM behavior.
- Corrupt or unreadable console EEPROM data aborts the requested boot. Failed
  atomic saves are reported and prevent transitions from discarding the machine.
- Added 27 frontend regression checks with generated BIOS/cartridge fixtures
  and isolated storage, covering first boot, full-byte persistence, reset,
  restart-equivalent restoration, BIOS changes while running, cartridge
  transitions, legacy sidecar import, direct boot, corrupt files and failed
  writes. Frontend self-tests now pass **51 / 51** without opening a GUI.

Validation for this fix: `sh scripts/build.sh --test` passed, including core
purity, warning/format lint, both builds, all self-tests, the unchanged 8086
corpus baseline, WSHWTest, framebuffer goldens and WSTimingTest (400 passing /
7 previously documented deferred cases).


## Open ROM cancellation input recovery

User report: choosing File > Open ROM and cancelling could leave menus inert,
particularly when the ROM-less welcome screen remained present.

- All native completion paths (selected/cancelled/error) now share
  `front_finish_dialog`. It clears the modal flag, drains held Nuklear mouse
  buttons/editing modifiers without synthesizing a widget click, restores the
  appropriate in-app window, and resets gfx's cached pressed state through a
  focus transition matching the native window's actual focus.
- Restore the native parent with SDL_RaiseWindow on the main thread. If native
  focus restoration is asynchronous, reconcile the gfx cache once the native
  window reports focus. No test-only focus injection is used after the modal
  in the interactive regression.
- v2026.4's UI wrapper retains Nuklear's internal read-only flag but explicitly
  removes it when WINDOW_NO_INPUT is cleared. Draw one neutral-input frame
  after a modal, then resume normal window flags. This preserves layout/scroll
  state while ensuring Menu/Settings/Recent/About become interactive again.
- Added `--dialog-test`, exercising real offscreen gfx/Nuklear contexts with
  deliberately missing releases: **13 passed / 0 failed**, including reopening
  File, selecting Settings, retaining Settings, recovering from native errors
  and requesting Open again. Linux lavapipe CI runs it with the existing UI smoke.
- Added interactive `--cancel-test`: ROM-less File > Open ROM > native Cancel,
  with an initial focus injection only before opening the modal. The native
  macOS run recorded **5 passed / 0 failed**, including actual focus restoration
  and the File/Settings actions after cancellation. The UI automation service's
  post-exit window snapshots were stale; the regression's isolated result file
  confirmed completion. Temporary tracing was removed.
