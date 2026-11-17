# Development guide

[Back to README](../README.md) · [User guide](user-guide.md)

## Toolchain and SDL3

The project downloads its pinned Goose compiler (`v2026.4`) on first use. No global Goose installation or `PATH` setup is needed. Requires `curl`, `tar` (or `unzip` on Windows), a SHA-256 tool (`shasum` or `sha256sum`), and a C compiler supported by Goose. On Windows, run the scripts from Git Bash with Visual Studio installed.

The compiler and its bundled libraries are kept in `.tools/goose/`, which is excluded from Git. Build caches default to the ignored project-local `.goose/` directory (`GOOSE_HOME` can override this). Both local builds and CI use `scripts/goose.sh`; the version and platform checksums are defined together in that script. To update Goose, change the version and all checksums there. Installed versions remain separate, and subsequent runs work offline.

```bash
sh scripts/goose.sh --version                 # download / verify the local compiler
sh scripts/goose.sh build app/gooswan.goose    # frontend -> app/gooswan
sh scripts/goose.sh build tools/sst.goose      # test harness / headless runner -> tools/sst
```

SDL3 comes from the pinned Goose release's bundled `gfx` package and is statically linked into Gooswan. The pinned release's gfx documentation identifies SDL as `release-3.4.16`. Do not install a separate SDL3 SDK with Homebrew, apt or another package manager for this build. Updating Goose and the platform checksums in `scripts/goose.sh` also updates the bundled native libraries. Distributed apps do not require an SDL3 DLL or dylib next to them.

On Linux, SDL loads the system's windowing/audio libraries at runtime, and graphics require a Vulkan driver. CI installs `mesa-vulkan-drivers` for its headless lavapipe checks. A Goose compiler built from upstream source without bundled libraries has different build prerequisites; that is outside this project's pinned-toolchain workflow.

## Regression checks

Full check (core purity, lint, both builds and the regression battery). Runs on Linux, macOS and Git Bash on Windows; the battery needs `nasm`, `curl` and `unzip` for the test data:

```bash
sh scripts/fetch_test_roms.sh    # builds WSHWTest / WSTimingTest into tests/roms
sh scripts/fetch_corpus.sh       # SingleStepTests 8086 corpus into tests/data
sh scripts/build.sh --test
```

`scripts/lint.sh` fails on any `goose check` warning or a source not in `goose format` layout.

## Packaging

Build a native desktop distribution (Python 3 is required for packaging):

```bash
sh scripts/build.sh
sh scripts/package_zip.sh app/gooswan macos arm64   # Intel Mac: x86_64
# Windows (Git Bash): sh scripts/package_zip.sh app/gooswan.exe windows x86_64
# Linux: sh scripts/package_zip.sh app/gooswan linux amd64
python3 scripts/check_package.py dist/releases/gooswan-1.1.0-macos-arm64.zip macos --arch arm64
open dist/macos-arm64/Gooswan.app
```

Use the actual `VERSION` in verification filenames. All outputs are versioned ZIPs in `dist/releases/`. macOS also refreshes `dist/macos-<arch>/Gooswan.app` and the original `dist/Gooswan.app` launch path. Packaging runs on the target OS; supported targets are Linux amd64, Windows x86_64, and macOS arm64/x86_64. Linux creates three ZIPs (deb, rpm and AppImage); Windows and each macOS architecture create one. Every ZIP has the same wrapper:

```text
Gooswan/
  <Gooswan.exe | Gooswan.app | gooswan_*.deb | gooswan-*.rpm | Gooswan.AppImage>
  README.md
  THIRD_PARTY_NOTICES.md
  licenses/OFL.txt
  docs/user-guide.md
```

The AppImage wrapper also includes `licenses/APPIMAGE_NOTICES.txt`. The Japanese font and SDL window icon are embedded at compile time on every OS using Goose's `embed_file`; no sidecar assets are needed. The macOS bundle also includes its ICNS, documentation and licenses. deb/rpm install `/usr/bin/gooswan`, a desktop entry and icon under `/usr/share`, documentation under `/usr/share/doc/gooswan`, and font licensing under `/usr/share/licenses/gooswan`. AppImage contains the same tree and a relocatable `AppRun` launcher. Its runtime license is included inside the image too.

macOS packaging uses Xcode Command Line Tools (`vtool`, `codesign`, `ditto`). `scripts/build.sh` targets macOS 13.5 by default (`MACOSX_DEPLOYMENT_TARGET` can override it); packaging records the binary's actual minimum OS version and applies an ad-hoc signature. Developer ID signing and notarization are not configured. Windows packaging embeds ICO, VERSIONINFO and an asInvoker/PerMonitorV2 manifest with Windows resource APIs, then selects the GUI subsystem in the distribution copy. Development binaries retain their console for tests.

Linux packaging requires `dpkg-dev`, `rpm`, `cpio`, `file`, and `desktop-file-utils` in addition to the normal build tools. `scripts/appimage_tools.py` downloads official appimagetool 1.9.1 and type2-runtime 20251108, verifies fixed SHA-256 values even for cached copies, and uses `.tools/appimage/`. Passing `--runtime-file` prevents appimagetool from downloading a changing runtime. FUSE is not needed during packaging or CI. The embedded SDL remains static; `dpkg-shlibdeps` and RPM's automatic dependency generator scan linked libraries, and packaging separately declares SDL's dynamically opened window/audio/Vulkan libraries. Driver implementations remain system-provided.

RPM's `Release: 1` is a package revision, separate from `VERSION`. The project does not currently declare a first-party license, so the RPM metadata uses `LicenseRef-Gooswan` rather than assigning an open-source license; third-party notices and OFL are installed with the package.

CI builds all four native targets, runs the regression suite, then verifies all six ZIPs after extraction outside the checkout. It moves each payload away from its wrapper docs before launch and checks the CPU architecture, embedded assets and platform metadata. Linux additionally runs packaged GUI smoke tests with lavapipe, installs/removes deb on Ubuntu 22.04 and Debian 12 and rpm on Fedora 43, and exercises the real AppImage runtime on Ubuntu 22.04 and Fedora 43. Clean-distribution checks run as root only inside disposable containers; locally they can be invoked with the same `docker run` command as CI, after placing the Linux ZIPs in `release-assets/`.

The final validation job requires exactly six expected filenames and writes `SHA256SUMS`. On a published release, the tag must equal `VERSION` or `vVERSION`. Publishing downloads the same validated artifact, checks its checksums, then attaches six ZIPs and `SHA256SUMS`. This follows GitHub's [workflow artifact sharing](https://docs.github.com/en/actions/tutorials/store-and-share-data) mechanism. The bundle is also available as the `release-bundle` workflow artifact on ordinary CI runs.

```bash
# After collecting all six ZIPs into one directory:
python3 scripts/release_assets.py dist/releases
# Optional tag consistency check:
python3 scripts/release_assets.py dist/releases --tag v1.1.0
```

Icons live in `assets/icons/`; regenerate ICNS/ICO/PNG/BMP derivatives from `AppIcon.png` on macOS with `python3 scripts/generate_icons.py`. Rebuild afterward to refresh embedded assets.

## Test harness and GUI checks

`./app/gooswan <rom> <frames> check` runs a fixed number of frames and verifies the presented picture against the emulated framebuffer (works headless with `GOOSE_GFX_HEADLESS=1` and lavapipe).

```bash
./tools/sst [v20] <case-file.json>...     # SingleStepTests corpora
./tools/sst ws <rom> [suite] [fb|wav|fbwav]  # headless ROM runner (framebuffer / audio dump)
./tools/sst cpu_test                    # also: ppu_test, apu_test, eeprom_test, state_test
./app/gooswan --self-test                # TOML/settings/input behavior
./tools/audio_test                      # native-rate adapter and stateful linear interpolation, no device needed
GOOSWAN_CONFIG_DIR="$PWD/.goose/ui-smoke" ./app/gooswan --ui-smoke
./app/gooswan --dialog-test              # offscreen modal-cancellation regression
GOOSWAN_CONFIG_DIR="$PWD/.goose/cancel-test" ./app/gooswan --cancel-test # click Cancel in the native picker
./tools/sst bios_test <bios> mono|color <output.ppm> # optional user-owned BIOS check
sh tests/ws_test_suite.sh                 # ws-test-suite, opt-in (WS_TEST_SUITE=<dir>)
python3 tools/diff_swanium.py <rom> [frames]  # needs a sibling ../Swanium checkout
```

## Status and accuracy

M1–M4 are complete. The M5 desktop GUI now includes menus, persistent TOML settings, keyboard/gamepad remapping, display controls, save states and BIOS boot. M6 accuracy parity remains in progress; CI verifies native builds and relocated packages on Linux, Windows and both macOS architectures, with headless GUI smoke tests on Linux. Native interactive Windows/Linux GUI behavior and physical-controller validation still need platform testing. See [ROADMAP.md](https://github.com/bubio/Gooswan/blob/main/ROADMAP.md) and the [session notes](https://github.com/bubio/Gooswan/tree/main/docs/sessions).

| Test | Result |
|------|--------|
| SingleStepTests 8086 | 634,406 / 646,000 (residue: documented-undefined flags) |
| WSCpuTest Test All | pass |
| WSHWTest Test All | pass |
| WSTimingTest | 400 / 407 (7 documented quantisation cases) |
| ws-test-suite | 22 / 22 |

## Accuracy references

- [WSDev Wiki](https://ws.nesdev.org/wiki/WSdev_Wiki)
- [SingleStepTests](https://github.com/SingleStepTests) (8086, V20)
- [FluBBaOfWard/WSCPUTest](https://github.com/FluBBaOfWard/WSCPUTest)
- [FluBBaOfWard/WSTimingTest](https://github.com/FluBBaOfWard/WSTimingTest)
- [FluBBaOfWard/WSHWTest](https://github.com/FluBBaOfWard/WSHWTest)
- [asiekierka/ws-test-suite](https://github.com/asiekierka/ws-test-suite)
- [Swanium](https://github.com/bubio/Swanium)

## Architecture

Gooswan separates a platform-independent core from an SDL3 frontend. Its structural and behavioural reference is [Swanium](https://github.com/bubio/Swanium), the same machine implemented in Rust. Changes are validated against hardware-captured CPU corpora and public test ROMs.

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

The compact Nuklear UI uses the bundled M PLUS 1p Japanese font, readable selection indicators, grouped settings tabs and scrollable ROM history; its layout follows UsaProject.
