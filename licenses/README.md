# Licenses

This repository contains code from other repositories. Files containing such code should include a license notice, and a copy should be stored in this folder.

## Apache-2.0

`Apache-2.0.txt`

- `dots/.config/quickshell/ii/modules/common/widgets/shaders/weather*.frag` —
  the rain, fog, snow and sun wallpaper effects, ported from the AGSL in AOSP's
  `frameworks/libs/systemui/weathereffects/graphics/assets/shaders/`. Each
  shader names the upstream file it came from.
- `dots/.config/quickshell/ii/assets/images/weather/` — the tileable noise
  (`fog.png`, `clouds.png`) and the per-effect colour-grading LUTs
  (`rain_lut.png`, `fog_lut.png`, `snow_lut.png`, `sun_lut.png`), copied
  unchanged from `weathereffects/graphics/assets/textures/`.
