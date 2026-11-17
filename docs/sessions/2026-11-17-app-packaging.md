# Desktop application distribution

The existing Nuklear/SDL GUI remains the frontend. Swanium's native app
packaging was the reference for this distribution work; Swanium was read only.

- Added original Gooswan goose/handheld artwork and committed ICNS, multi-size
  ICO, PNG and SDL BMP derivatives. The generation prompt and reproduction
  command are in `assets/icons/README.md`.
- macOS ZIPs contain `Gooswan.app`, with bundle metadata, an icon, fonts/notices
  under Resources and an ad-hoc signature. Minimum macOS version comes from the
  actual Mach-O build command. `scripts/build.sh` defaults to macOS 13.5,
  following Swanium; the final ARM64 binary reports minos 13.5. Local packaging also creates `dist/Gooswan.app`.
  ARM64 and Intel remain separate artifacts, matching the existing Goose matrix.
- Windows distribution copies embed the icon through Windows resource APIs
  and select the GUI PE subsystem. The development binary retains console
  behavior for regression tests. No external resource editor is downloaded.
- Linux ZIPs include the executable, window icon, desktop entry and a per-user
  installer. Installation keeps resources with the executable and uses an
  absolute desktop Exec path, independent of the desktop session's PATH.
- The bundled font is now found under macOS Contents/Resources. SDL window
  icons are loaded from a package or source checkout on Windows/Linux.
- Added `VERSION` (1.0.0, aligned with the existing release tag) for application bundle metadata.
- CI packages on each native runner, extracts outside the checkout, checks
  required files, and runs help/self-tests. It checks macOS signatures and
  Windows GUI subsystem/icon resources. Linux also tests per-user installation
  and runs GUI smoke through the installed launcher with lavapipe.
  Artifacts are complete ZIPs; publishing uploads those same checked ZIPs.
  Icon, packaging, README and version changes now trigger CI.

Validation on macOS ARM64:

- Core purity, Goose warning/format lint, both native builds, C99
  `-Wall -Wextra -Werror`, shellcheck, actionlint and Python compilation passed.
- The full regression battery passed: CPU 12, PPU 39, APU 83, EEPROM 25,
  state 24, frontend 51; CLI checks; corpus 634406/646000; hardware/framebuffer
  goldens; timing 400 passed with the same seven known deferred cases.
- Native macOS package extraction, signature verification, CLI/help and frontend
  self-tests passed outside the checkout. Relocated packaged GUI smoke passed
  20 checks. The first sandboxed GUI attempt aborted; running the same test
  with desktop access succeeded.
- Linux ZIP layout and per-user installation (including paths with spaces)
  passed using a fixture executable on macOS. This is a layout/installer check,
  not a Linux execution test.
- Windows resource/subsystem processing and Linux native runtime/GUI checks
  require their respective CI runners; they were not executed on this Mac.
  No remote CI run or release publication was initiated.

## Icon fusion follow-up

At user request, replaced the initial goose/handheld illustration with a fusion
of Swanium's blue beveled tile and luminous cyan style, and the provided Goose
language logo's left-facing goose and pointed horizontal feathers. Used the
built-in image generation tool with both images as references. The final master
uses clean white exterior corners after transparent variants produced fringe
artifacts. Updated all ICNS/ICO/PNG/BMP derivatives and regenerated the local
macOS app and ZIP. Signature and relocated package self-tests passed. Generation
and cleanup prompts and the upstream logo URL are in `assets/icons/README.md`.

### Two-bird correction

The user clarified that Goose and Swan must both be present, rather than one
Goose silhouette in Swanium's material. Replaced the master with two distinct
birds facing each other: Swanium's curved-neck swan on the left and Goose's
straight-feathered goose on the right. Regenerated all icon formats, the local
macOS application and its distribution ZIP. Signature verification and all 51
relocated frontend self-tests passed. The final prompt is recorded in the icon
README.

### Overlapping pair refinement

At user request, moved Goose to the left/front and Swan to the right/back,
with outward-facing heads and bodies/wings overlapping in the center. Retained
two distinct heads/necks and used subtle occlusion shading to separate the
bodies. Updated all icon formats and regenerated the local macOS app and ZIP.
Signature verification and 51 relocated frontend self-tests passed. The final
edit prompt is in the icon README.
