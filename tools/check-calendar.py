#!/usr/bin/env python3
"""The sidebar calendar's grid stays cheap, and its event card grows out of the
day it describes and stays on screen.

- **No layer per day.** The grid is 42 cells. They were `RippleButton`s, which
  keep `layer.enabled` and an `OpacityMask` per instance for the ripple: 49
  offscreen passes, with the weekday header counted, in a repeated delegate
  (DESIGN.md 8). `check-effect-budget.py` cannot see it, because the layer lives
  in `RippleButton.qml` and not in the delegate's file. This is the dock's blind
  spot again, so the ceiling is stated per cell.
- **One card, on the popup motion.** There was one `LazyLoader` per cell, active
  only past scale 0.9. So the first third of the enter and the tail of the exit
  were never drawn. The card is one instance now, on `ArrowPopupMotion`.
- **The clamp.** The card hangs off a zero-size pivot at the day's top centre, so
  it scales out of the day. It is shifted inside the window near an edge, and
  the shift is lifted out of the QML and swept here.

    python3 tools/check-calendar.py
"""

import re
from pathlib import Path

DIR = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/sidebarDashboard/calendar"
day = re.sub(r"//.*", "", (DIR / "CalendarDayButton.qml").read_text())
card = (DIR / "CalendarPopup.qml").read_text()
widget = (DIR / "CalendarWidget.qml").read_text()

root = re.search(r"^(\w+) \{", day, re.M).group(1)
assert root != "RippleButton", "a day cell is a RippleButton again: a layer and an OpacityMask per cell"
for effect in ("layer.enabled", "OpacityMask", "MultiEffect", "ShaderEffect", "Shadow", "Loader"):
    assert effect not in day, f"{effect} in CalendarDayButton, which repeats 42 times"

assert widget.count("CalendarPopup {") == 1, "the calendar should own exactly one event card"
assert "ArrowPopupMotion" in card, "the event card must open and close on ArrowPopupMotion"
assert "mapFromItem(cell, cell.width / 2, 0)" in card, "the pivot must sit on the day's top centre"
assert re.search(r"^\s+onClicked:", day, re.M), "the tap must fire on clicked, so a drag off the day cancels"

# The clamp, in the pivot's coordinates: card.x is relative to the pivot at root.x.
expr = re.search(r"^\s+x: (Math\.max\(gutter - root\.x.*)$", card, re.M).group(1)
py = (expr.replace("(root.parent?.width ?? 0)", "W").replace("root.x", "rx")
      .replace("Math.max", "max").replace("Math.min", "min"))
clamp = eval(f"lambda W, rx, width, gutter: {py}")

GUTTER = 10  # Appearance.sizes.elevationMargin
failures = 0
for W in (300, 340, 400):
    for width in range(60, W - 2 * GUTTER + 1, 20):
        for rx in range(0, W + 1):
            left = rx + clamp(W, rx, width, GUTTER)
            ok = GUTTER - 1e-9 <= left <= W - GUTTER - width + 1e-9
            if left > GUTTER and left + width < W - GUTTER:
                ok = ok and abs(left + width / 2 - rx) < 1e-9  # room: centred on the day
            if not ok:
                failures += 1
assert failures == 0, f"{failures} clamp positions leave the window or drift off the day"

print("ok: calendar cells carry no effect, one card on ArrowPopupMotion, clamp holds")
