# User guide

[Back to README](../README.md)

## Starting the app

Extract the entire release ZIP. On macOS, move `Gooswan.app` to Applications. On Windows, open `Gooswan/Gooswan.exe`. On Linux, run `Gooswan/gooswan` directly, or run `sh Gooswan/install.sh` to install for the current user without sudo. The installer places the app in `~/.local/lib/gooswan/`, a command-line launcher in `~/.local/bin/`, and a desktop entry/icon under `$XDG_DATA_HOME` (default `~/.local/share/`). Add `~/.local/bin` to PATH for terminal use.

Keep `assets/` beside the Windows/Linux executable. SDL3 is included in the application; you do not need to install it separately. On Linux, a working desktop session and a Vulkan-capable graphics driver are needed for the SDL GPU renderer. The Linux release targets the glibc baseline of Ubuntu 22.04 (Debian 12 is also supported).

The macOS app is ad-hoc signed but not notarized. If Gatekeeper blocks a download you trust, run:

```bash
xattr -dr com.apple.quarantine /Applications/Gooswan.app
```

ROMs and BIOS images are not distributed. Open your `.ws` or `.wsc` ROM from **File > Open ROM**; normal direct cartridge boot does not require a BIOS. For the source build, you can also launch from a terminal:

```bash
./app/gooswan                     # open a ROM from File > Open ROM
./app/gooswan path/to/game.wsc
./app/gooswan --help              # show CLI usage (-h also works), then exit
```

## Controls and menus

Default controls:

- Arrow keys = X-pad
- `W A S D` = Y-pad
- `X` = A, `Z` = B
- `Enter` = Start
- Gamepad: D-pad = X-pad, South = B, East = A, Start = Start
- `Esc` = close settings/About or leave fullscreen

The File / Emu / View menus expose ROM history, save/load state, settings, pause/reset, 1–4x window scales, fullscreen, left/right rotation, and nearest/bilinear sampling. The game image retains its aspect ratio. Keyboard and gamepad buttons can be rebound in **Settings > Input**; Escape cancels capture. Ctrl+O/S/L/P/R opens a ROM, saves/loads state, pauses, or resets. Ctrl+, opens settings, Ctrl+Q quits, and F11 toggles fullscreen. Command also works in place of Ctrl on macOS.

Vertical games are detected from the cartridge footer and rotate the screen automatically. By default, the pads rotate with the screen (`rotate_input_with_screen` in settings).

## Save data

Keep ROMs in a writable folder. Save data is written next to the ROM on ROM/BIOS switches, reset and normal exit: `<rom>.sav`, `<rom>.eep`, `<rom>.iep`, and `<rom>.rtc` for carts with a clock. Changes remain in memory during play, so a crash or forced quit can lose changes since the last save.

## Settings and BIOS

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

