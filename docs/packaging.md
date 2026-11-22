# Packaging and releases

[Development guide](development.md) · [User guide](user-guide.md)

## Local packages

Run packaging on the target OS with Python 3. These commands build and verify a macOS arm64 ZIP.

```bash
sh scripts/build.sh
sh scripts/package_zip.sh app/gooswan macos arm64   # Intel Mac: x86_64
# Windows (Git Bash): sh scripts/package_zip.sh app/gooswan.exe windows x86_64
# Linux: sh scripts/package_zip.sh app/gooswan linux amd64
version=$(cat VERSION)
python3 scripts/check_package.py "dist/releases/gooswan-$version-macos-arm64.zip" macos --arch arm64
open dist/macos-arm64/Gooswan.app
```

## Package layout

All outputs are versioned ZIPs in `dist/releases/`. macOS also refreshes `dist/macos-<arch>/Gooswan.app` and the original `dist/Gooswan.app` launch path. Linux creates deb, rpm and AppImage ZIPs. Windows x86_64 and each macOS architecture create one ZIP apiece. All ZIPs use this directory layout.

```text
Gooswan/
  <Gooswan.exe | Gooswan.app | gooswan_*.deb | gooswan-*.rpm | Gooswan.AppImage>
  README.md
  THIRD_PARTY_NOTICES.md
  licenses/OFL.txt
  docs/user-guide.md
```

The AppImage wrapper also includes `licenses/APPIMAGE_NOTICES.txt`. Goose embeds the Japanese font and SDL window icon in the application at compile time. The macOS bundle also includes its ICNS, documentation and licenses. deb/rpm install `/usr/bin/gooswan`, a desktop entry and icon under `/usr/share`, documentation under `/usr/share/doc/gooswan`, and font licensing under `/usr/share/licenses/gooswan`. AppImage contains the same tree and a relocatable `AppRun` launcher. Its runtime license is included inside the image too.

## Platform requirements

- **macOS** uses Xcode Command Line Tools (`vtool`, `codesign`, and `ditto`). The build targets macOS 13.5 by default and accepts `MACOSX_DEPLOYMENT_TARGET` as an override. Packaging records the binary's minimum OS version and applies an ad-hoc signature. Developer ID signing and notarization are unconfigured.
- **Windows** uses native resource APIs to embed the ICO, VERSIONINFO and an asInvoker/PerMonitorV2 manifest. Packaging selects the GUI subsystem in the distribution copy. The development binary retains its console for tests.
- **Linux** needs `dpkg-dev`, `rpm`, `cpio`, `file`, and `desktop-file-utils`. [`scripts/appimage_tools.py`](../scripts/appimage_tools.py) verifies pinned AppImage tools and caches them in `.tools/appimage/`. FUSE is optional for both packaging and verification. Package tools scan linked ELF libraries, and the packages declare the window, audio and Vulkan libraries that SDL loads at runtime.

RPM's `Release: 1` tracks the package revision independently of the application version in `VERSION`. The RPM metadata uses `LicenseRef-Gooswan` and installs the third-party notices and font license.

## CI and publishing

CI builds all four native targets, runs the regression suite, then verifies all six ZIPs after extraction outside the checkout. It moves each payload away from its wrapper docs before launch and checks the CPU architecture, embedded assets and platform metadata. Linux additionally runs packaged GUI smoke tests with lavapipe, installs/removes deb on Ubuntu 22.04 and Debian 12 and rpm on Fedora 43, and exercises the real AppImage runtime on Ubuntu 22.04 and Fedora 43. To repeat the clean-distribution checks, place the Linux ZIPs in `release-assets/` and use the disposable container command from the [CI workflow](../.github/workflows/ci.yml).

The final validation job requires exactly six expected filenames and writes `SHA256SUMS`. On a published release, the tag must match the version in `VERSION`, with an optional `v` prefix. Publishing downloads the same validated artifact, checks its checksums, then attaches six ZIPs and `SHA256SUMS`. The bundle is also available as the `release-bundle` workflow artifact on ordinary CI runs.

```bash
# After collecting all six ZIPs into one directory:
python3 scripts/release_assets.py dist/releases
# Optional tag consistency check:
python3 scripts/release_assets.py dist/releases --tag "v$(cat VERSION)"
```

See the [icon export instructions](../assets/icons/README.md) when updating application artwork.
