# Gooswan application icon

`AppIcon.png` is the current master artwork, edited with the built-in image generation tool. It depicts **two distinct birds with overlapping bodies/wings**: the Goose language goose at the left/front and the Swanium swan at the right/back. Their heads face outward and their feathers overlap at the center.

References:

- Swanium: `/Users/bubio/dev/_Emu/Swanium/assets/icons/AppIcon.png` — swan silhouette, blue beveled tile and luminous cyan material.
- [Goose language logo](https://aardappel.github.io/goose/docs/logo/logo_black_fg_white_bg_mini.png) — goose silhouette with round eye, triangular bill and horizontal feather streaks.

The reference repositories were not modified. The master uses clean opaque white corners around the rounded tile.

## Final edit prompt

Use case: compositing / precise-object-edit.
Edit the supplied Gooswan application icon. Preserve its blue beveled rounded-square tile, luminous pale cyan material, clean white exterior corners, and refined Swanium-inspired style.
USER'S REQUEST: move the GOOSE to the LEFT, the SWAN to the RIGHT, and make their bodies/wings OVERLAP gracefully in the center, with excellent overall balance.
There must still be exactly TWO recognizable birds with two separate heads and necks.
LEFT bird: the Goose programming language goose, facing LEFT, with a round eye, short triangular bill, relatively straight rising neck, compact body and straight horizontal pointed feather streaks extending RIGHT into the center.
RIGHT bird: the Swanium swan, facing RIGHT, with almond-shaped eye, elegant downturned bill, dramatically arched S-shaped neck and rounded sweeping body, with upward-curved feather tips extending LEFT into the center.
Composition: their heads sit toward the upper left and upper right respectively, looking outward. Their bodies sit closer together in the lower center. Substantially overlap the wing/body area (about one-third of their bodies) to form a cohesive intertwined double-bird emblem instead of two isolated side-by-side marks. Put the goose's crisp horizontal feather layers in front of the swan's curved body at the central crossing. Use subtle tonal shading and a narrow darker-cyan occlusion edge at overlaps so BOTH bodies remain readable; do not fuse their anatomy into one shared torso. Keep only two necks, two heads. Aim for a graceful compact flowing composition with similar visual weight for each bird, centered within the tile, even generous margins and no awkward tangencies. The swan can stand slightly taller to accommodate its curved neck.
Do not simply mirror the existing pair: redesign the central overlapping bodies as described. No text, no additional objects, no extra birds. Output square 1024x1024, opaque white outside the tile.

## Derived files

The selected output was normalized to 1024 × 1024. Run `python3 scripts/generate_icons.py` on macOS to regenerate `Gooswan.icns`, the six-size `Gooswan.ico`, `gooswan.png` (256 pixels) and the SDL window icon `gooswan.bmp`. This uses only Python's standard library and macOS `sips`.
