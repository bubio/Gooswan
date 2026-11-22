# User guide

[Back to README](../README.md)

## Install and launch

Choose your platform's ZIP from [Releases](https://github.com/bubio/Gooswan/releases/latest) and extract it. Replace `<version>` in the commands with the downloaded version.

| Package | Install or launch |
| --- | --- |
| macOS | Move `Gooswan/Gooswan.app` to Applications and open it. |
| Windows | Open `Gooswan/Gooswan.exe`. |
| Linux deb | Run `sudo apt install ./Gooswan/gooswan_<version>_amd64.deb`. |
| Linux rpm | Run `sudo dnf install ./Gooswan/gooswan-<version>-1.x86_64.rpm`. |
| Linux AppImage | Run `chmod +x Gooswan/Gooswan.AppImage`, then open it. If FUSE is unavailable, run `APPIMAGE_EXTRACT_AND_RUN=1 ./Gooswan/Gooswan.AppImage`. |

The deb and rpm packages install a desktop entry and the `gooswan` command. Use `sudo apt remove gooswan` or `sudo dnf remove gooswan` to uninstall. The app embeds SDL3, the Japanese font and the window icon. Keep the license documents when redistributing.

Linux needs a working desktop session and a Vulkan-capable graphics driver. Builds use Ubuntu 22.04's glibc 2.35 baseline. CI checks deb on Ubuntu 22.04 / Debian 12, rpm on Fedora 43, and AppImage on Ubuntu 22.04 / Fedora 43. AppImage uses the system window/audio libraries and driver. The deb and rpm packages declare runtime library dependencies.

The macOS app is ad-hoc signed but not notarized. If Gatekeeper blocks a download you trust, run the following command.

```bash
xattr -dr com.apple.quarantine /Applications/Gooswan.app
```

### Verify the release ZIPs

Place the six ZIPs alongside the release's `SHA256SUMS` file. Run `sha256sum --check SHA256SUMS` on Linux or `shasum -a 256 --check SHA256SUMS` on macOS.

## Open a game

ROMs and BIOS images are not distributed. Open your `.ws` or `.wsc` ROM from **File > Open ROM**. Direct cartridge boot runs without a BIOS. The source build also accepts a ROM path in the terminal.

```bash
./app/gooswan                     # open a ROM from File > Open ROM
./app/gooswan path/to/game.wsc
./app/gooswan --help              # show CLI usage (-h also works), then exit
```

## Controls and menus

### Default controls

- Arrow keys = X-pad
- `W A S D` = Y-pad
- `X` = A, `Z` = B
- `Enter` = Start
- Gamepad: D-pad = X-pad, South = B, East = A, Start = Start
- `Esc` = close Settings, About, Recent ROMs or Link Play, or leave fullscreen

The File / Emu / View menus expose ROM history, save/load state, settings, pause/reset, 1–4x window scales, fullscreen, left/right rotation, and nearest/bilinear sampling. The game image retains its aspect ratio. Keyboard and gamepad buttons can be rebound in **Settings > Input**. Press Escape to cancel capture. Ctrl+O/S/L/P/R opens a ROM, saves/loads state, pauses, or resets. Ctrl+, opens settings, Ctrl+Q quits, and F11 toggles fullscreen. Command also works in place of Ctrl on macOS.

Vertical games are detected from the cartridge footer and rotate the screen automatically. By default, the pads rotate with the screen (`rotate_input_with_screen` in settings).

## Swan Revival Link Play

1. On each player's computer, sign in on the [Swan Revival account page](https://swanrevival.com/account/), set a player name and generate a one-time device code. In Gooswan, open **Emu > Link Play**, enter the code and select **Link account**. MesenCE players can link their account from **Settings > WonderSwan > WonderGate**.
2. Open the same game on both computers. Create a room for it in the [Swan Revival lobby](https://swanrevival.com/link-play/) and share the room code with the other player.
3. In Gooswan, enter the room code under **Emu > Link Play** and select **Join**. In MesenCE with RevivalGate release 7 or later, use **Tools > Link play (WonderSwan)**. Joining restarts the game with the cable attached.
4. On both computers, navigate to the game's communication menu and select **Ready** in the link dialog. When the cable connects, return to the game to start the match.

Use **Leave or cancel** to disconnect. Resetting or opening a different game leaves the room. Save states are unavailable while the cable is attached. On Windows, keep `gooswan-link.exe` beside `Gooswan.exe` when moving the application. The Swan Revival device token is stored separately from settings in the configuration directory.

## Save data

Keep ROMs in a writable folder. Cartridge and console data are written on ROM or BIOS switches, reset and normal exit. A crash or forced quit can lose changes made since the last write.

| File next to the ROM | Contents |
| --- | --- |
| `<rom>.sav` | Cartridge SRAM |
| `<rom>.eep` | Cartridge EEPROM |
| `<rom>.iep` | Internal console EEPROM for direct boot, also written as a compatibility copy in BIOS mode |
| `<rom>.rtc` | Clock registers for cartridges with an RTC |

Save states use one slot per ROM path under `states/` in the configuration directory. A state contains CPU, RAM, peripherals, timing, framebuffer and BIOS overlay data, with checks for version, ROM identity and integrity. The current format is version 2. Version 1 and Swanium states are incompatible. Ordinary cartridge saves remain compatible.

## Settings and BIOS

Settings are stored as **`settings.toml`** in the application configuration directory shown below.

- macOS: `~/Library/Application Support/gooswan/`
- Linux: `$XDG_CONFIG_HOME/gooswan/` (default `~/.config/gooswan/`)
- Windows: `%APPDATA%/gooswan/`

`GOOSWAN_CONFIG_DIR` overrides this directory for portable setups and tests. Changes are saved atomically. Missing settings use defaults. If the TOML syntax is invalid, the app preserves the file and disables settings writes until you repair it and restart. The app ignores unknown keys and uses the default binding for invalid key names. Settings are independent of Swanium.

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

Place user-supplied BIOS images in the configuration directory's `bios/` folder as `ws_irom.bin`, `wsc_irom.bin`, or `wc_irom.bin`. **Settings > ROM** selects the BIOS used on the next load or reset. A missing BIOS falls back to direct cartridge boot with a message. **Emu > BIOS Settings** boots the selected BIOS without a cartridge and briefly holds Start to open its setup screen.

BIOS-mode internal EEPROM is saved atomically beside the BIOS as `bios/ws_irom.iep`, `bios/wsc_irom.iep`, or `bios/wc_irom.iep`. Personal data such as the name and birthday survives BIOS-only resets, ROM changes and application restarts. Each BIOS has its own console data, shared with cartridge sessions booted through that BIOS. Existing ROM-local `.iep` files are imported when the console save is absent and continue to be written for compatibility. Direct boot continues to use the ROM-local file. Unreadable or damaged console EEPROM files stop the requested boot without replacing the current machine.
