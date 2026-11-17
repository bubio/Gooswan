# Gooswan

<p align="center">
  <img src="assets/icons/gooswan.png" alt="Gooswan" width="128" height="128">
</p>

A WonderSwan / WonderSwan Color emulator for macOS, Windows and Linux, written in [Goose](https://github.com/aardappel/goose). Supports keyboard/gamepad controls, vertical games, save states and display scaling.

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

## Download and play

Download your platform's ZIP from [**Releases**](https://github.com/bubio/Gooswan/releases/latest) and extract it. Each ZIP contains a `Gooswan/` folder with the application, README, user guide and licenses. Filenames include the release version (`<version>` below).

| Platform | ZIP | Application / launch |
|----------|-----|----------------------|
| macOS (Apple Silicon, 13.5+) | `gooswan-<version>-macos-arm64.zip` | Move `Gooswan/Gooswan.app` to Applications and open it |
| macOS (Intel, 13.5+) | `gooswan-<version>-macos-x86_64.zip` | Move `Gooswan/Gooswan.app` to Applications and open it |
| Windows (x64) | `gooswan-<version>-windows-x86_64.zip` | Open `Gooswan/Gooswan.exe` |
| Linux (x64, deb) | `gooswan-<version>-linux-x86_64-deb.zip` | Install the enclosed `.deb` with `sudo apt install ./Gooswan/gooswan_<version>_amd64.deb` |
| Linux (x64, rpm) | `gooswan-<version>-linux-x86_64-rpm.zip` | Install the enclosed `.rpm` with `sudo dnf install ./Gooswan/gooswan-<version>-1.x86_64.rpm` |
| Linux (x64, AppImage) | `gooswan-<version>-linux-x86_64-appimage.zip` | Run `chmod +x Gooswan/Gooswan.AppImage`, then open it |

SDL3, the Japanese font and the window icon are embedded in the application. The Windows EXE and macOS app can be moved on their own; Linux packages install their own desktop entry and icon. Keep the accompanying license documents when redistributing. ROMs and BIOS images are not included; a BIOS is optional.

Linux builds use Ubuntu 22.04 (glibc 2.35) as their minimum build baseline. CI checks deb installation on Ubuntu 22.04 and Debian 12, rpm installation on Fedora 43, and AppImage execution on Ubuntu 22.04 and Fedora 43. A Vulkan-capable graphics driver and desktop window/audio libraries are required; deb/rpm declare the runtime library dependencies. AppImage uses the system desktop libraries and driver. If FUSE is unavailable, use `APPIMAGE_EXTRACT_AND_RUN=1 ./Gooswan/Gooswan.AppImage`.

`SHA256SUMS` accompanies the six ZIPs in each release. On Linux, run `sha256sum --check SHA256SUMS` with all six ZIPs in the same directory (macOS: `shasum -a 256 --check SHA256SUMS`).

The macOS app is not notarized. If Gatekeeper blocks a trusted download:

```bash
xattr -dr com.apple.quarantine /Applications/Gooswan.app
```

## Build from source and play

Download the source ZIP or clone this repository. You need a C compiler (Xcode Command Line Tools on macOS, GCC/Clang on Linux, or Visual Studio with C++ tools on Windows), `curl`, `tar`/`unzip`, and `shasum`/`sha256sum`. On Windows, run the commands in Git Bash.

From the project directory:

```bash
sh scripts/build.sh
./app/gooswan                 # Windows: ./app/gooswan.exe
```

The build downloads and verifies the pinned Goose compiler (`v2026.4`), including SDL3. No global Goose or SDL3 installation is required. To create a macOS `.app` or a distribution ZIP, see the [build and packaging guide](https://github.com/bubio/Gooswan/blob/main/docs/development.md#packaging).

## Play

Open a `.ws` or `.wsc` ROM with **File > Open ROM** (`Ctrl+O`, or `Command+O` on macOS).

| Control | Default key |
|---------|-------------|
| X-pad | Arrow keys |
| Y-pad | W / A / S / D |
| A / B | X / Z |
| Start | Enter |

Gamepad defaults: D-pad = X-pad, South = B, East = A, Start = Start. Remap controls in **Settings > Input**. The menus provide save/load state, pause/reset, fullscreen (`F11`), scaling and rotation.

Cartridge saves are stored beside the ROM; keep ROMs in a writable folder. See the [user guide](docs/user-guide.md) for settings, BIOS, save locations and shortcuts. [Development details](https://github.com/bubio/Gooswan/blob/main/docs/development.md) cover tests, accuracy and architecture.
