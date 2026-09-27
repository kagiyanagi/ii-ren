# settings-EasterEggWindow — notes

- Opened through a throwaway probe: `.audit-egg.qml` in the shell dir, holding
  `EasterEggWindow { Component.onCompleted: visible = true }`, run with `qs -p`, then
  deleted. The shot is idle beside a held press (warp). Hyprland tiled the probe window to
  950x969, so the 800x600 size is only a request.
- `check-design.py` in bare mode still counts its 20 literal durations. They are AOSP
  transcriptions, cited in the header, and were left alone on purpose.
- The wobble's `Rotation` pivoted on `iconSize / 2`. A text item is taller than its font
  size, so the centre sat above the glyph. It pivots on the item's own box now.
