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
- **It turns over at midnight.** The grid was built from a bare `new Date()`,
  which no binding can see change, so today's highlight and the month stayed
  where the shell started until a restart. It is built from `DateTime.today`
  now, and the layout is run under `node` for a day either side of a month end.

    python3 tools/check-calendar.py
"""

import json
import re
import subprocess
from pathlib import Path

DIR = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/sidebarDashboard/calendar"
day = re.sub(r"//.*", "", (DIR / "CalendarDayButton.qml").read_text())
card = re.sub(r"//.*", "", (DIR / "CalendarPopup.qml").read_text())
widget = re.sub(r"//.*", "", (DIR / "CalendarWidget.qml").read_text())

root = re.search(r"^(\w+) \{", day, re.M).group(1)
assert root != "RippleButton", "a day cell is a RippleButton again: a layer and an OpacityMask per cell"
for effect in ("layer.enabled", "OpacityMask", "MultiEffect", "ShaderEffect", "Shadow", "Loader"):
    assert effect not in day, f"{effect} in CalendarDayButton, which repeats 42 times"

assert widget.count("CalendarPopup {") == 1, "the calendar should own exactly one event card"
assert not re.search(r"parent:.*QsWindow", widget + card), \
    "the card's parent is a binding on QsWindow again: it re-fires mid window rebuild and segfaults"
assert re.search(r"active:\s*false", widget) and "cardLoader.active = false" in widget, \
    "the card must exist only while shown, not through every sidebar open"
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

assert re.search(r"viewingDate:.*getDateInXMonthsTime\(monthShift, DateTime\.today\)", widget), \
    "the grid must be built from DateTime.today, or it stops at the day the shell started"
assert re.search(r"readonly property date today:.*dayKey", (DIR.parents[3] / "services/DateTime.qml").read_text(), re.S), \
    "DateTime.today must hang off the day-only key, or the grid rebuilds on every clock tick"

# The day after the shell started: the highlight sits on that day, in that month.
js = (DIR / "calendar_layout.js").read_text() + """
const out = [];
for (const [y, m, d] of [[2026, 9, 31], [2026, 10, 1], [2026, 11, 31], [2027, 0, 1]]) {
    const v = getDateInXMonthsTime(0, new Date(y, m, d));
    const cells = getCalendarLayout(v, true, 0).flat().filter(c => c.today === 1);
    out.push([v.getMonth(), cells.map(c => [c.day, c.month, c.year])]);
}
console.log(JSON.stringify(out));
"""
got = json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)
assert got == [[9, [[31, 9, 2026]]], [10, [[1, 10, 2026]]], [11, [[31, 11, 2026]]], [0, [[1, 0, 2027]]]], \
    f"the layout does not follow the date it is given: {got}"

print("ok: calendar cells carry no effect, one card on ArrowPopupMotion, clamp holds, turns over at midnight")
