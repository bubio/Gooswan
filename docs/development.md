# Development guide

[README](../README.md) · [User guide](user-guide.md) · [Testing](testing.md) · [Packaging](packaging.md)

## Build

Install a C compiler (Xcode Command Line Tools, GCC/Clang, or Visual Studio with C++ tools), `curl`, `tar` or `unzip`, and `shasum` or `sha256sum`. Use Git Bash on Windows.

```sh
sh scripts/build.sh
./app/gooswan                 # Windows: ./app/gooswan.exe
```

The build checks that the core can compile on its own and does no host I/O. It also checks Goose warnings and formatting, then builds the app, the headless runner and the native audio test. Use `sh scripts/goose.sh format core app tools` to apply the formatter, or `sh scripts/goose.sh build app/gooswan.goose` to rebuild just the app.

## Toolchain

`scripts/goose.sh` downloads the pinned Goose release into `.tools/goose/` and checks its platform checksum. Subsequent builds can use the cached compiler offline. The compiler uses `.goose/` for build caches by default. Set `GOOSE_HOME` to use a different cache. Update the release and its platform checksums together in `scripts/goose.sh`.

Goose's bundled `gfx` package statically links SDL3, so the build requires no separate SDL3 SDK. On Linux, SDL loads system desktop and audio libraries at runtime, and graphics need a Vulkan driver. CI uses Mesa lavapipe for headless checks.

## Repository layout

| Directory | Responsibility |
| --- | --- |
| [`core/`](../core) | Platform-independent V30MZ emulator, bus, DMA, PPU, APU and peripherals. The host API is in [`core/core.goose`](../core/core.goose). |
| [`app/`](../app) | SDL3 desktop frontend, Nuklear UI, TOML settings and persistence. |
| [`tools/`](../tools) | Headless ROM runner, SingleStepTests harness, core self-tests and Swanium comparison tools. |
| [`tests/`](../tests) | Regression fixtures, corpus fetch helpers and package tests. |
| [`scripts/`](../scripts) | Toolchain setup, builds, regression entry points and release packaging. |
| [`assets/`](../assets) and [`packaging/`](../packaging) | Fonts, icons and OS distribution files. |

The core takes ROM data, input and save bytes and produces a framebuffer, audio samples and save bytes. The frontend owns host I/O. [`app/gooswan.build`](../app/gooswan.build) selects Windows, Linux or macOS path handling. Linux and macOS share the POSIX resolver. SDL windowing, audio and TOML adapters are shared across targets.

For hardware behaviour and comparison against [Swanium](https://github.com/bubio/Swanium), use the [testing guide](testing.md). For remaining accuracy work, see the [roadmap](../ROADMAP.md).
