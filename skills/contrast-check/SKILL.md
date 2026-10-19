---
name: contrast-check
description: Check WCAG colour contrast for an Android/Compose app - one colour pair, every Material colour-scheme on/surface pair in Kotlin sources, or a list of hard-coded Color(0x...) literals that need a human look. Use when a design has low-contrast text, when adding a theme or dark mode, or when auditing low-vision accessibility.
license: Apache-2.0
---

# contrast-check

```bash
C=skills/contrast-check/scripts/contrast.py
python3 $C pair 0xFF777777 0xFFFFFFFF          # 4.48:1 FAIL (just under AA)
python3 $C pair 0xFF767676 0xFFFFFFFF          # 4.54:1 AA
python3 $C theme core/designsystem             # every onX / X pair in light/darkColorScheme
python3 $C literals feature/                   # hard-coded colours outside theme files
```

Thresholds: 4.5:1 normal text, 3:1 large text (≥ 18 sp, or ≥ 14 sp bold), 3:1 for icons and component boundaries. Alpha is composited over the background.

## What it cannot check

Text over an image (a rating badge on a poster, a caption on a photo): the background is whatever the image is. `literals` flags those for a human. Fix them by giving the text its own opaque scrim, not by darkening the colour. Check light **and** dark themes, and again with high-contrast text on (`device-toggles`).
