# Testing and accuracy

[Development guide](development.md) · [Packaging](packaging.md) · [Roadmap](../ROADMAP.md)

## Regression suite

Install `nasm`, `curl`, `unzip` and `gunzip`, then run these commands from the repository root. On Windows use Git Bash.

```sh
sh scripts/fetch_test_roms.sh    # pinned WSHWTest and WSTimingTest sources and ROMs
sh scripts/fetch_corpus.sh       # SingleStepTests 8086 data
sh scripts/build.sh --test
python3 tests/package_test.py
```

The fetchers keep data under `tests/roms/` and `tests/data/`. The build runs core and frontend self-tests, checks the CLI, runs the 8086 corpus and WSHWTest, compares three framebuffer hashes, and reads all 29 pages of WSTimingTest. CI runs this battery on Linux amd64, Windows x64 and both macOS architectures. Linux CI also runs headless GUI checks using Mesa lavapipe.

| Suite | Baseline | Coverage |
| --- | --- | --- |
| SingleStepTests 8086 | 634,406 / 646,000 | CI. Remaining differences are undefined flags after DIV/IDIV/IMUL and AAM with base zero. |
| WSHWTest Test All | Pass | CI. Includes hardware I/O, interrupt, timer and sound tests. |
| Framebuffer hashes | 3 / 3 | CI. Two WSHWTest screens and one WSTimingTest screen. |
| WSTimingTest | 407 / 407 | CI. All 29 pages run against the pinned ROM. |
| WSCpuTest v0.7.1 Test All | Pass | Recorded developer baseline for the V30MZ profile. |
| SingleStepTests V20 native | 2,980,747 / 3,125,000 | Recorded developer baseline for the separate V20 profile. |
| ws-test-suite | 21 / 22 | Optional local run. `mono/sound/quirks.ws` fails one marker on both the previous build and the CPU timing update. |

## Focused checks

```sh
./tools/sst cpu_test             # also ppu_test, apu_test, eeprom_test, state_test
./tools/audio_test               # resampler and stream setup without an audio device
./app/gooswan --self-test        # frontend settings, input, and media persistence
./app/gooswan --dialog-test      # offscreen modal-cancellation regression
GOOSWAN_CONFIG_DIR="$PWD/.goose/ui-smoke" ./app/gooswan --ui-smoke
./app/gooswan tests/roms/WSHWTest.wsc 300 check
```

The last command compares the presented image against the emulated framebuffer. On Linux with lavapipe, set `GOOSE_GFX_HEADLESS=1` and `SDL_AUDIODRIVER=dummy` for headless presentation and GUI tests. For a manual native file-picker cancellation check, run `--cancel-test` with an isolated `GOOSWAN_CONFIG_DIR`.

### Optional test inputs

```sh
sh tests/fetch_v20.sh 01
./tools/sst v20 tests/data-v20/01.json
./tools/sst ws /path/to/WSCpuTest.wsc
./tools/sst ws tests/roms/WSTimingTest.ws pg0 fb
WS_TEST_SUITE=/path/to/ws-test-suite/roms sh tests/ws_test_suite.sh
./tools/sst bios_test /path/to/bios.bin color output.ppm
```

The headless runner accepts an optional suite selector and a dump mode (`fb`, `wav`, or `fbwav`). The ws-test-suite directory must contain the `mono/`, `color/` and `wonderful/` trees. For BIOS testing, use your own image and select `mono` or `color`.

To compare a ROM with Swanium, place the Swanium checkout beside Gooswan and build the probe with Cargo. The comparison reports framebuffer, WRAM and audio differences with the same inputs and frame count.

```sh
cargo build --release --manifest-path tools/swprobe/Cargo.toml
python3 tools/diff_swanium.py /path/to/game.wsc 600
```

## CPU timing

[`core/cpu_timing.goose`](../core/cpu_timing.goose) models 256 cycles per scanline and 159 scanlines per frame. It estimates instruction timing using addressing forms, repeat counts and taken branches. WSTimingTest measures loops with the HBlank timer, so a counter read near a scanline boundary can change the result.

- AAA/AAS use nine clocks. Shifts and rotates use the operand form to determine their cost, including the CL and immediate forms with a masked count of zero. [NEC V30MZ Hardware User's Manual, Appendix A](https://www.ardent-tool.com/CPU/docs/NEC/V20-V30/v30mz.pdf)
- A single-register effective address can incur a one-cycle dependency when the preceding instruction changes that register. The fitted two-register cost already accounts for the overlap observed in WSTimingTest. LEA does not pay the dependency.
- A short backward conditional branch keeps its one-cycle prefetch saving when another transfer occurred in the sequence. This covers the chained-branch case.
- The HBlank counter reflects any scanline boundary crossed before the IN bus sample. This makes the RETF immediate case report its last scanline.

The timing model estimates instruction costs. WSTimingTest verifies the measured loops. [WSTimingTest source and measurement notes](https://github.com/FluBBaOfWard/WSTimingTest)

The mono TX-ready interrupt is level-triggered while serial and the send IRQ are enabled. This covers WSTimingTest's HLT and external interrupt loops. Hardware IRQ entry is charged 40 cycles and HLT 12 in the fitted model. Serial byte transfer and baud timing remain unmodelled.

## Audio comparison

The FF4 regression used the same APU input events in Gooswan and Swanium and found matching PCM for the tested sequence and conversion rates. Gooswan's sweep period follows the `time + 1` behaviour covered by WSHWTest. This comparison covers the tested sequence and the digital output before device delivery. Use `apu_test` and `audio_test` when changing channel timing, queueing or resampling.

## Reference sources

- Hardware register and timing reference. [WSdev Wiki](https://ws.nesdev.org/wiki/WSdev_Wiki)
- Hardware-captured CPU cases. [8086 corpus](https://github.com/SingleStepTests/8086) · [V20 corpus](https://github.com/SingleStepTests/v20)
- WonderSwan test ROMs. [WSCpuTest](https://github.com/FluBBaOfWard/WSCPUTest) · [WSHWTest](https://github.com/FluBBaOfWard/WSHWTest) · [WSTimingTest](https://github.com/FluBBaOfWard/WSTimingTest) · [ws-test-suite](https://github.com/asiekierka/ws-test-suite)
- Behavioural reference and differential comparison. [Swanium](https://github.com/bubio/Swanium)
