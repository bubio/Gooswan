# Gooswan - WonderSwan / WonderSwan Color Emulator

Gooswan is a **WonderSwan / WonderSwan Color** emulator written in [Goose](https://github.com/aardappel/goose), developed test-first against hardware-captured CPU corpora and public test ROMs.

<p align="center">
  <a href="https://github.com/bubio/Gooswan/releases/latest">
    <img src="https://img.shields.io/github/v/release/bubio/Gooswan" alt="Latest Release">
  </a>
  <a href="https://github.com/bubio/Gooswan/releases/latest">
    <img src="https://img.shields.io/github/downloads/bubio/Gooswan/total.svg" alt="Downloads">
  </a>
  <a href="https://github.com/bubio/Gooswan/actions/workflows/ci.yml">
    <img src="https://github.com/bubio/Gooswan/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
</p>

Gooswan separates a platform-independent core (`core/`, a Goose package with no host I/O) from a small SDL3 frontend (`app/`). Its structural and behavioural reference is [Swanium](https://github.com/bubio/Swanium), the same machine implemented in Rust; a milestone is done when its tests pass, not when the code looks right.

## Key Features

- **Test-First Core:** The V30MZ CPU is built against the [SingleStepTests](https://github.com/SingleStepTests) 8086 / V20 corpora, then WSCpuTest for the V30MZ-specific behaviour.
- **Platform-Independent Core:** CPU, memory map, interrupts, timers, DMA, PPU, APU, EEPROM, cartridge and RTC live in `core/`, which imports nothing but std; `scripts/check_core.sh` keeps it that way.
- **WonderSwan + WonderSwan Color:** Mono and colour rendering, sound DMA and HyperVoice, cartridge / internal EEPROM, RTC carts.
- **Vertical Games:** Detected from the cartridge footer; the picture turns 90° in a portrait window and the pads turn with it, as in Swanium.
- **Swanium Differential Check:** `tools/diff_swanium.py` compares framebuffers, WRAM and audio frame by frame against a sibling Swanium checkout.
- **CI-Packaged Releases:** One GitHub Actions workflow builds and tests Linux, macOS and Windows, and attaches a zip per platform to each release.

## Download

Prebuilt binaries are attached to [**Releases**](https://github.com/bubio/Gooswan/releases/latest). Each ZIP contains a desktop application, this README, third-party notices and the bundled GUI font. macOS archives contain `Gooswan.app`; Windows archives contain `Gooswan/Gooswan.exe` (no console window); Linux archives contain `Gooswan/gooswan`, an icon, desktop entry and a per-user installer.

| Platform | Asset name |
|----------|------------|
| macOS (Apple Silicon) | `gooswan-macos-arm64.zip` |
| macOS (Intel) | `gooswan-macos-x86_64.zip` |
| Linux (x64, glibc of Ubuntu 22.04 or newer) | `gooswan-linux-amd64.zip` |
| Windows (x64) | `gooswan-windows-x86_64.zip` |

> On macOS, drag `Gooswan.app` to Applications and open it. The app is ad-hoc signed, but is not notarized. If Gatekeeper blocks a trusted download, remove its quarantine flag:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Gooswan.app
> ```

On Windows, extract the entire ZIP and open `Gooswan/Gooswan.exe`. On Linux, run `Gooswan/gooswan` directly, or run `sh Gooswan/install.sh` to install it in your user account and add it to the application menu. Keep the bundled `assets/` beside the executable.

## Building

The project downloads its pinned Goose compiler (`v2026.4`) on first use. No global Goose installation or `PATH` setup is needed. Requires `curl`, `tar` (or `unzip` on Windows), a SHA-256 tool (`shasum` or `sha256sum`), and a C compiler supported by Goose. On Windows, run the scripts from Git Bash with Visual Studio installed.

The compiler and its bundled libraries are kept in `.tools/goose/`, which is excluded from Git. Build caches default to the ignored project-local `.goose/` directory (`GOOSE_HOME` can override this). Both local builds and CI use `scripts/goose.sh`; the version and platform checksums are defined together in that script. To update Goose, change the version and all checksums there. Installed versions remain separate, and subsequent runs work offline.

```bash
sh scripts/goose.sh --version                 # download / verify the local compiler
sh scripts/goose.sh build app/gooswan.goose    # frontend -> app/gooswan
sh scripts/goose.sh build tools/sst.goose      # test harness / headless runner -> tools/sst
```

Full check (core purity, lint, both builds and the regression battery). Runs on Linux, macOS and Git Bash on Windows; the battery needs `nasm`, `curl` and `unzip` for the test data:

```bash
sh scripts/fetch_test_roms.sh    # builds WSHWTest / WSTimingTest into tests/roms
sh scripts/fetch_corpus.sh       # SingleStepTests 8086 corpus into tests/data
sh scripts/build.sh --test
```

Build a native desktop distribution (Python 3 is required for packaging):

```bash
sh scripts/build.sh
sh scripts/package_zip.sh app/gooswan macos arm64   # Intel Mac: x86_64
# Linux: sh scripts/package_zip.sh app/gooswan linux amd64
# Windows (Git Bash): sh scripts/package_zip.sh app/gooswan.exe windows x86_64
python3 scripts/check_package.py gooswan-macos-arm64.zip macos
open dist/Gooswan.app                             # local macOS app
```

Run packaging on the target OS. macOS packaging uses Xcode Command Line Tools (`vtool`, `codesign`, `ditto`) and leaves a launchable app in `dist/Gooswan.app`. `scripts/build.sh` targets macOS 13.5 by default (`MACOSX_DEPLOYMENT_TARGET` can override it), and packaging records the binary's actual minimum OS version. The application version is defined in `VERSION`. Icons live in `assets/icons/`; regenerate ICNS/ICO/PNG/BMP derivatives from `AppIcon.png` on macOS with `python3 scripts/generate_icons.py`.

CI builds all four targets, packages them on their native runners, and verifies each ZIP after extracting outside the checkout. Linux additionally runs the packaged GUI smoke test with lavapipe. Workflow artifacts contain the complete ZIPs; release publishing uploads those same verified archives. Windows keeps a console-enabled development binary for CLI tests and sets the GUI subsystem only in the packaged copy.

`scripts/lint.sh` fails on any `goose check` warning or a source not in `goose format` layout.

## Usage

```bash
./app/gooswan                     # open a ROM from File > Open ROM
./app/gooswan path/to/game.wsc
./app/gooswan --help              # show CLI usage (-h also works), then exit
```

Default controls:

- Arrow keys = X-pad
- `W A S D` = Y-pad
- `X` = A, `Z` = B
- `Enter` = Start
- Gamepad: D-pad = X-pad, South = B, East = A, Start = Start
- `Esc` = close settings/About or leave fullscreen

The File / Emu / View menus expose ROM history, save/load state, settings, pause/reset, 1–4x window scales, fullscreen, left/right rotation, and nearest/bilinear sampling. The game image retains its aspect ratio. The compact Nuklear UI uses the bundled M PLUS 1p Japanese font, readable selection indicators, grouped settings tabs and scrollable ROM history; its layout follows UsaProject. Keyboard and gamepad buttons can be rebound in **Settings > Input**; Escape cancels capture. Ctrl+O/S/L/P/R opens a ROM, saves/loads state, pauses, or resets. Ctrl+, opens settings, Ctrl+Q quits, and F11 toggles fullscreen. Command also works in place of Ctrl on macOS.

Save data is written next to the ROM on ROM switches, exit and every 150 frames: `<rom>.sav`, `<rom>.eep`, `<rom>.iep`, and `<rom>.rtc` for carts with a clock.

`./app/gooswan <rom> <frames> check` runs a fixed number of frames and verifies the presented picture against the emulated framebuffer (works headless with `GOOSE_GFX_HEADLESS=1` and lavapipe).

### Settings and BIOS

Settings are stored as **`settings.toml`** in the application configuration directory:

- macOS: `~/Library/Application Support/gooswan/`
- Linux: `$XDG_CONFIG_HOME/gooswan/` (default `~/.config/gooswan/`)
- Windows: `%APPDATA%/gooswan/`

`GOOSWAN_CONFIG_DIR` overrides this directory for portable setups and tests. Changes are saved atomically. Missing settings use defaults; a syntactically invalid file is preserved and settings writes are disabled until it is repaired and the app restarted. Unknown keys are ignored; invalid key names use the default binding. Settings are independent of Swanium.

```toml
scale = 3
volume = 100
fullscreen = false
rotation = 0 # 0=normal, 1=right, 2=left; opening a ROM follows its orientation flag
bilinear = false
rotate_input_with_screen = true
bios = 0 # 0=direct, 1=WonderSwan, 2=WonderSwan Color, 3=SwanCrystal
recent_files = []

[keyboard]
A = "X"
B = "Z"

[gamepad]
A = 1 # SDL East
B = 0 # SDL South; -1 means unbound
```

Place user-supplied BIOS images in the configuration directory's `bios/` folder as `ws_irom.bin`, `wsc_irom.bin`, or `wc_irom.bin`. **Settings > ROM** selects the BIOS used on the next load/reset; a missing BIOS falls back to direct cartridge boot with a message. **Emu > BIOS Settings** boots the selected BIOS without a cartridge and briefly holds Start to open its setup screen. BIOS images are not distributed.

BIOS-mode internal EEPROM is saved atomically beside the BIOS as `bios/ws_irom.iep`, `bios/wsc_irom.iep`, or `bios/wc_irom.iep`. Personal data such as the name and birthday survives BIOS-only resets, ROM changes and application restarts. Each BIOS has its own console data, shared with cartridge sessions booted through that BIOS. Existing ROM-local `.iep` files are imported when the console save is absent and continue to be written for compatibility; direct boot continues to use the ROM-local file. Unreadable or damaged console EEPROM files stop the requested boot without replacing the current machine.

Save states use one slot per ROM path under `states/` in the configuration directory. They include CPU, RAM, peripherals, timing, framebuffer and BIOS overlay state, with version, ROM identity and integrity checks. They are Gooswan-specific; Swanium save states are not compatible. Existing cartridge save files remain beside the ROM.

### Test harness

```bash
./tools/sst [v20] <case-file.json>...     # SingleStepTests corpora
./tools/sst ws <rom> [suite] [fb|wav|fbwav]  # headless ROM runner (framebuffer / audio dump)
./tools/sst cpu_test | ppu_test | apu_test | eeprom_test | state_test
./app/gooswan --self-test                # TOML/settings/input behavior
GOOSWAN_CONFIG_DIR="$PWD/.goose/ui-smoke" ./app/gooswan --ui-smoke
./app/gooswan --dialog-test              # offscreen modal-cancellation regression
GOOSWAN_CONFIG_DIR="$PWD/.goose/cancel-test" ./app/gooswan --cancel-test # click Cancel in the native picker
./tools/sst bios_test <bios> mono|color <output.ppm> # optional user-owned BIOS check
sh tests/ws_test_suite.sh                 # ws-test-suite, opt-in (WS_TEST_SUITE=<dir>)
python3 tools/diff_swanium.py <rom> [frames]  # needs a sibling ../Swanium checkout
```

## Status

M1–M4 are complete. The M5 desktop GUI now includes menus, persistent TOML settings, keyboard/gamepad remapping, display controls, save states and BIOS boot. M6 accuracy parity remains in progress; Windows/Linux GUI behavior and physical-controller validation still need platform testing. See [ROADMAP.md](ROADMAP.md) and the session notes in [docs/sessions](docs/sessions).

| Test | Result |
|------|--------|
| SingleStepTests 8086 | 634,406 / 646,000 (residue: documented-undefined flags) |
| WSCpuTest Test All | pass |
| WSHWTest Test All | pass |
| WSTimingTest | 400 / 407 (7 documented quantisation cases) |
| ws-test-suite | 22 / 22 |

## Accuracy References

- [WSDev Wiki](https://ws.nesdev.org/wiki/WSdev_Wiki)
- [SingleStepTests](https://github.com/SingleStepTests) (8086, V20)
- [FluBBaOfWard/WSCPUTest](https://github.com/FluBBaOfWard/WSCPUTest)
- [FluBBaOfWard/WSTimingTest](https://github.com/FluBBaOfWard/WSTimingTest)
- [FluBBaOfWard/WSHWTest](https://github.com/FluBBaOfWard/WSHWTest)
- [asiekierka/ws-test-suite](https://github.com/asiekierka/ws-test-suite)
- [Swanium](https://github.com/bubio/Swanium)

## Architecture

```text
app/ (Goose gfx/ui, SDL3 host adapters, TOML settings, save files)
                     |
                     v  core/core.goose (public API)
core/: CPU (V30MZ), Bus, Interrupts, Timers, DMA, PPU, APU, EEPROM, Cartridge, RTC
```

- `core/` — the emulator core (`namespace core`), headless and platform-independent
- `app/` — the frontend, using only the core API
- `tools/` — the `sst` harness (SingleStepTests runner, headless ROM runner, white-box self-tests) and the Swanium diff tool
- `tests/`, `scripts/` — test data fetch, regression battery, CI builds
- `docs/` — research notes, decisions and session logs
