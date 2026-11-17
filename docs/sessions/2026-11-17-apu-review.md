# 2026-11-17 — APU and output comparison with Swanium

Corrected Gooswan's sample-boundary and PCM/DMA ordering, then aligned noise
and device-rate interpolation with Swanium at the user's request. Reference:
sibling Swanium commit `40d3892812417d51b9f101493aae12b5dd2259b1`.

## Implementation

- APU advancement stops at each 128-cycle output boundary. Previously, a CPU
  instruction crossing a boundary supplied its later waveform value; a large
  tick could emit several copies of its final value.
- Feature clocks run in order DMA → sweep/noise → oscillators → output.
  Wave-only operation retains bulk advancement to the next output boundary.
  CPU port-access sweep prepayment remains intact.
- Sound DMA feeds the voice latch before that cycle's output sample. Wave-mode
  ticks clear voice-filter history even for intervals shorter than one sample.
- Noise now uses Swanium's countdown: the initial zero counter steps immediately,
  then reloads `2048 - pitch` and holds for that many further ticks. The gate
  clocks the LFSR even with channel 4 disabled. A reset immediately clears the
  LFSR and reloads the countdown, and the request bit self-clears. This follows
  the actual reference behavior, including its effective `2049 - pitch` interval
  after reload, rather than substituting a hardware-period interpretation.
- Noise state is now a countdown instead of elapsed cycles. Save-state format
  version 2 rejects version 1 states; ordinary cartridge saves are unchanged.
- The host adapter queries the opened SDL device rate and feeds that rate to
  SDL, after stateful stereo s16 linear interpolation. Phase, previous samples,
  first-sample handling and signed division match Swanium. Volume is applied
  after interpolation with Swanium's integer truncation. The product is widened
  to 64 bits to avoid overflow on full-scale transitions.
- Queue depth is converted back to 24 kHz source frames, retaining the same
  approximately 53 ms pacing target. Clear/reopen resets interpolation history.
  SDL still handles device format/channel conversion; stable-rate operation
  no longer relies on its rate interpolator. Device hot-swap was not tested.

## Same-input APU comparison

Running each complete emulator independently mixes CPU timing differences into
APU comparisons. The initial 1,500-frame whole-machine PCM RMS difference was
369.333, and fixing sample boundaries alone changed it to 369.313; these numbers
are not evidence of perceptual improvement.

A temporary Gooswan build instead recorded memory writes, port writes and
elapsed cycles. A Rust replay fed those same events into Swanium's public
Bus/APU without running its CPU. No user saves were loaded or overwritten by
these headless comparisons. Diagnostic sources and logs are under
`.goose/apu-review/`; production builds contain no tracing.

| FF4 sequence, 1,500 frames (~19.875 s) | Stereo frames | Different L/R samples | RMS difference |
| --- | ---: | ---: | ---: |
| No keys, original APU vs same-input Swanium | 477,000 | 1,264 / 954,000 | 11.847 |
| No keys, corrected sample boundaries | 477,000 | 0 / 954,000 | 0 |
| Start at frame 600, A at frame 900, before noise alignment | 477,000 | 47,366 / 954,000 | 29.782 |
| Same Start/A sequence, after noise alignment | 477,000 | 0 / 954,000 | 0 |

The Start/A sequence reaches music with noise. The final replay includes
18,971,229 tick events, 380,165 port writes and 9,733,386 memory writes.
The complete 24 kHz PCM matches, including the region that previously first
failed at stereo frame 233,084 (9.712 s).

## Device-rate comparison

Passed the final FF4 PCM through the production C host adapter using a device
substitute. Separately compiled and invoked Swanium's actual `resample.rs` on
its replay PCM. Both consumed chunks of 318 stereo input frames, carrying state
across calls. Compared complete output bytes, with volume 100:

| Rate | Output stereo frames | Result |
| --- | ---: | --- |
| 24,000 Hz | 477,000 | identical |
| 44,100 Hz | 876,486 | identical |
| 48,000 Hz | 953,999 | identical |
| 96,000 Hz | 1,907,997 | identical |

Hashes and counts are in `.goose/apu-review/parity/resample-comparison.json`.
These are digital comparisons before device delivery, not loopback recordings
or subjective listening. Full-scale overflow behavior in Swanium's 32-bit
interpolation product is not copied; the FF4 signal fits within that range.

## Remaining scope

This establishes equality for the tested FF4 event sequence and conversion
rates, not every APU configuration. Existing sweep-time reload differences
remain: Gooswan's `time + 1` behavior is covered by WSHWTest; Swanium uses
`time.saturating_sub(1)`. Swanium's wave-only fast path can retain disabled
channels' old samples while its general path contributes zero; that reference
inconsistency was not copied. Neither difference prevents equality in the
reported final comparison. Swanium source files were not changed.

## Validation

- `sh scripts/build.sh`: core purity, lint, formatting and all builds passed.
- `apu_test`: 100 passed, 0 failed, including eight noise parity checks and nine
  sample-boundary/DMA/voice restart checks added in this review.
- `state_test`: 25 passed, 0 failed; continuation includes an active noise clock,
  and version 1 rejection is explicit.
- `hostaudio_test`: 34 passed, 0 failed. Covers five conversion ratios, split
  versus whole input, signed volume, extreme transitions, queue duration,
  reset/reopen and device-query failure. Also passed AddressSanitizer and
  UndefinedBehaviorSanitizer with warnings treated as errors.
- Full regression: frontend persistence 51/51; 8086 634406/646000; WSHWTest Test
  All; framebuffer goldens 3/3; WSTimingTest's existing 400 passed / 7 failed.
- Real CoreAudio FF4 playback uses a diagnostic build with the current production
  APU and adapter, isolated settings/BIOS EEPROM and separate `.audio-check`
  cartridge files. It automatically presses Start and A to reach BGM. The
  actual opened device rate is 44,100 Hz. Playback completion is marked before
  the normal exit save so shutdown starvation is not counted as gameplay.
  The completed 120.000-second run recorded 5,125 device callbacks and zero
  shortage callbacks; the minimum observed source queue was 478 frames (19.9 ms).
- `git diff --check`: passed.

SDL device-rate handling was checked against the official documentation for
[SDL_GetAudioDeviceFormat](https://wiki.libsdl.org/SDL3/SDL_GetAudioDeviceFormat)
and [SDL_SetAudioStreamFormat](https://wiki.libsdl.org/SDL3/SDL_SetAudioStreamFormat).
