# 2026-11-17 — FF4 audio stalls during periodic saves

Removed the frontend's save every 150 frames (about two seconds). Cartridge
and console EEPROM saves remain on ROM/BIOS switches, reset and normal exit.
The user guide now describes these save points and the loss of unsaved changes
after a crash or forced quit.

## Measurement

Used the user-provided Final Fantasy 4 ROM on CrucialX6, the current Crystal
BIOS/settings, and the real SDL CoreAudio output. Temporary diagnostic builds
and logs are in `.goose/audio-check/`; production audio code was not changed.
Diagnostics preserved the original saves by reading their existing contents
and writing separate `.audio-check` sidecars on the same SSD. Configuration
and BIOS EEPROM writes were isolated inside the checkout.

A passive SDL audio stream callback counted requests for additional data that
the producer could not supply immediately. The first second was excluded.
These are shortage callback counts, not counts of separate audible clicks;
SDL may overestimate missing input bytes for resampling. No output loopback
recording or subjective listening was performed.

- Periodic saves enabled: 89 shortage callbacks at 90.214 seconds during play.
  The interrupted run ended at 91.200 seconds with 94 including shutdown.
- 44 periodic saves took 52.27–87.41 ms, median 62.89 ms. 43 exceeded the
  approximately 53 ms audio queue target. Saving blocks the same thread that
  produces audio; the atomic file writer flushes to disk before renaming.
- Periodic saves disabled: 0 shortage callbacks at 115.157 seconds, with a
  minimum observed producer-side queue of 478 stereo frames (19.9 ms).
  The 9,060-frame run completed at 120.200 seconds. Its final report included
  two shortage callbacks at 120.030 and 120.051 seconds near shutdown, when
  emulation stops producing audio and the exit save runs. Thus the full
  start-to-close log is not a zero-shortage result.

The comparison strongly implicates synchronous periodic saving in the reported
intermittent clicks. It does not establish that every possible audio artifact
or downstream device issue is resolved.

## Validation

- `sh scripts/build.sh`: core purity, formatting, lint and both builds passed.
- `./app/gooswan --self-test`: 51 passed, 0 failed, including save persistence.
- `./tools/sst apu_test`: 83 passed, 0 failed.
- `git diff --check`: passed.
