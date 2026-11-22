# Application icons

`AppIcon.png` is the 1024 × 1024 master with a transparent exterior. The design uses Swanium's swan and the [Goose language logo](https://aardappel.github.io/goose/docs/logo/logo_black_fg_white_bg_mini.png) as references.

Regenerate derivatives on macOS with Xcode Command Line Tools installed.

```sh
python3 scripts/generate_icons.py
```

| File | Use |
| --- | --- |
| `Gooswan.icns` | macOS bundle icon, with ten standard and Retina representations. |
| `Gooswan.ico` | Windows executable icon, with six RGBA representations. |
| `gooswan.png` | Linux desktop entry and repository README. |
| `gooswan.bmp` | SDL window icon embedded at build time. |

The exporter clears alpha values at or below 16/255 and makes values at or above 239/255 opaque while preserving the intermediate edge values. Rebuild the app to embed the updated BMP. macOS package verification checks all ICNS representations against the master.
