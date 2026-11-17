# Color 2bpp transparency — Dark Eyes: Battle Gate

Dark Eyes' dialogue showed displaced white copies of its black text and a
cyan message background. The game runs in color 2bpp mode (port 0x60 = 0x82).
Gooswan treated pixel zero as transparent in every color mode, allowing
SCR1 to show through SCR2 where the latter should have been opaque.

Only 4bpp makes pixel zero transparent regardless of palette. In 2bpp,
including color 2bpp, palette bit 2 controls pixel-zero transparency:
palettes 0–3 and 8–11 are opaque; 4–7 and 12–15 are transparent. This agrees
with [ares' PPU::opaque](https://github.com/ares-emulator/ares/blob/master/ares/ws/ppu/memory.cpp).

`ppu_transparent` now applies that rule. Synthetic rendering tests cover
SCR2 masking SCR1 in color 2bpp with both palette groups, plus the continued
unconditional transparency of pixel zero in 4bpp. The old color-2bpp test
incorrectly expected palette 0's zero pixel to be transparent and was corrected.

A headless run of the user-provided ROM reproduces the dialogue issue before
this change and shows complete black text on a white panel afterward. The
9000-frame reproduction uses this key script (`sst run`):

```
3000:512,3100:0,3500:1024,3600:0,4000:512,4100:0,4500:1024,4600:0,5000:1024,5100:0,6100:512,6200:0,7000:1024,7010:0,7500:1024,7510:0,8000:1024,8010:0,8500:1024,8510:0
```

No game-specific offsets or ROM modifications are used.

Validation: `sh scripts/build.sh --test` passes (PPU 45/45; CPU, APU,
EEPROM, state and frontend self-tests; 8086 corpus baseline; WSHWTest;
all three framebuffer goldens; WSTimingTest baseline 400 passed / 7 known
failures). The macOS arm64 app/ZIP were rebuilt and `check_package.py` passes.
