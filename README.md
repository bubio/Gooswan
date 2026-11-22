# Gooswan

<p align="center">
  <img src="https://raw.githubusercontent.com/bubio/Gooswan/main/assets/icons/gooswan.png" alt="Gooswan" width="128" height="128">
</p>

A WonderSwan / WonderSwan Color emulator for macOS, Windows and Linux, written in [Goose](https://github.com/aardappel/goose). Supports keyboard/gamepad controls, vertical games, save states, display scaling and [Swan Revival Link Play](docs/user-guide.md#swan-revival-link-play).

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

## Download

Download the ZIP for your system from [Releases](https://github.com/bubio/Gooswan/releases/latest) and extract it.

| Platform | Release archive |
| --- | --- |
| macOS 13.5+ (Apple Silicon) | `gooswan-<version>-macos-arm64.zip` |
| macOS 13.5+ (Intel) | `gooswan-<version>-macos-x86_64.zip` |
| Windows x64 | `gooswan-<version>-windows-x86_64.zip` |
| Linux x64 | `gooswan-<version>-linux-x86_64-{deb,rpm,appimage}.zip` |

The [user guide](docs/user-guide.md) covers installation, first launch and verifying the download. Bring your own `.ws` or `.wsc` ROM. A BIOS is optional.

## Play

Open a ROM with **File > Open ROM**. The default keyboard controls are the arrow keys for X-pad, W/A/S/D for Y-pad, X for A, Z for B, and Enter for Start. Remap keyboard and gamepad controls in **Settings > Input**. Keep ROMs in a writable folder for cartridge saves.

See the [user guide](docs/user-guide.md#controls-and-menus) for shortcuts, display options, BIOS setup and save data.

## Build and develop

```sh
sh scripts/build.sh
./app/gooswan                 # Windows: ./app/gooswan.exe
```

The build fetches the pinned Goose compiler with bundled SDL3. The [development guide](https://github.com/bubio/Gooswan/blob/main/docs/development.md) lists prerequisites and explains the source layout. The [testing guide](https://github.com/bubio/Gooswan/blob/main/docs/testing.md) covers regression checks and accuracy. See the [packaging guide](https://github.com/bubio/Gooswan/blob/main/docs/packaging.md) to build native release ZIPs.
