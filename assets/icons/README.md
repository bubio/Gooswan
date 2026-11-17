# Gooswan application icon

`AppIcon.png` is the approved 1024 × 1024 master: a charcoal tile, white Swanium swan, and large cyan Goose language logo superimposed across the center. Both birds face left. The swan's upward-curving feathers remain white; the goose's thin horizontal feathers are cyan.

The design was created with the built-in image generation tool using Swanium's icon and the [Goose language logo](https://aardappel.github.io/goose/docs/logo/logo_black_fg_white_bg_mini.png) as references. The palette uses the black/white and bright cyan from the user-supplied WonderSwan Color logo reference. The reference repositories were not modified.

## Approved design prompt

Create a refined alternative color/material design for the overlapping two-bird composition. Preserve the exact silhouettes: large left-facing Swanium swan behind, large left-facing Goose language logo superimposed across the lower center. Use near-black charcoal (#20252B) for the rounded tile, porcelain white (#F3F4F2) for the complete swan including all upward-curved feathers, and vivid cyan (#00A5DF) for the complete goose including its horizontal feather streaks. Keep dark eyes, mostly flat color, very subtle depth and a delicate overlap shadow. Avoid inflated glossy plastic shading. No lettering or extra objects. Use transparent alpha outside the tile.

## Final transparency edit prompt

Use case: background-extraction. Edit the supplied APPROVED Gooswan icon. Preserve every pixel of the design inside the rounded-square charcoal tile: white Swanium swan in back, cyan Goose logo in front, exact placement and shapes. Clean ONLY the alpha matte OUTSIDE the tile. All exterior pixels must be fully transparent alpha=0, including the stray gray/blue colored flecks along the top and bottom edges and any detached pixels near corners. Remove the exterior speckles entirely. Preserve a smooth clean antialiased tile boundary without halo. Do not redraw, recolor, move, resize, sharpen or otherwise change the two birds or charcoal tile. Output a genuine transparent PNG, square, with no matte color or checkerboard baked into corners. This is production cutout cleanup, not a new design.

## Alpha export and derived formats

The generated matte contained near-transparent exterior noise. `scripts/normalize_icon_alpha.swift` finalizes alpha for icon export: values at or below 16/255 become transparent and values at or above 239/255 become opaque, preserving intermediate antialiased edge values. It does not redesign or recolor the artwork. The final master was normalized before resizing to 1024 pixels.

Run `python3 scripts/generate_icons.py` on macOS with Xcode Command Line Tools (Swift/AppKit and sips). It requires an alpha-capable master, normalizes the export matte, and produces:

- `Gooswan.icns`: Apple `iconutil` output from the ten standard/Retina iconset slots (16–1024 pixels). Small representations use the native ICNS encoding rather than hand-packed PNG chunks.
- `Gooswan.ico`: six RGBA PNG representations (16, 32, 48, 64, 128, 256 pixels), advertised as 32-bit for Windows.
- `gooswan.png`: 256-pixel Linux/README icon.
- `gooswan.bmp`: 32-bit BMP with alpha masks, embedded at compile time for SDL window icons.

The macOS bundle uses the ICNS; Windows packaging embeds the ICO; SDL windows use the embedded BMP; Linux packages install the PNG with the desktop entry. Rebuild the executable after updating the BMP. Native packaging picks up the platform icons on each platform.

The macOS package checker runs `scripts/check_icons.swift` to decode every iconset slot and compare its pixels against the master resized to that resolution. This catches small-icon corruption that a valid ICNS header and correct image dimensions do not detect.
