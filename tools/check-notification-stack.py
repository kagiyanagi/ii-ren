#!/usr/bin/env python3
"""The sidebar's notification groups join into one stack, and a group header shows its
whole app name when it fits.

- TextMetrics.width is rounded to an int. "kitty" is 26.11px wide in the shipped font,
  so a cap of `metrics.width` gave it 26 and it elided to "ki...". The cap has to be
  the ceiling of `advanceWidth`, which is what the Text itself measures.
- Outside a popup the groups are a stack: the ends take the outer corners and the joins
  go small. A popup's toast, or a card that is being swiped, is standalone on all four
  corners. If the joins leak into the popup, every toast gets square corners, and a
  still frame of the popup shows nothing wrong until two toasts stack.
"""
import re
from pathlib import Path

W = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"
group = (W / "NotificationGroup.qml").read_text()
view = (W / "NotificationListView.qml").read_text()

for m in re.finditer(r"Layout\.maximumWidth:\s*(.+)", group):
    expr = m.group(1)
    assert not re.search(r"[Mm]etrics\.width\b", expr), \
        f"NotificationGroup: `maximumWidth: {expr}` reads TextMetrics.width, which is rounded down as often as up"
assert re.search(r"Math\.ceil\(\s*appNameMetrics\.advanceWidth\s*\)", group), \
    "NotificationGroup: the app name cap is no longer ceil(advanceWidth)"

def prop(name):
    m = re.search(rf"property \w+ {name}:\s*(.+)", group)
    assert m, f"NotificationGroup: `{name}` is gone"
    return m.group(1)

standalone = prop("standalone")
assert "root.popup" in standalone and "dragManager.dragging" in standalone, \
    f"NotificationGroup: standalone is `{standalone}`; a popup and a swiped card must both be standalone"
for side, end in (("topRadius", "stackTop"), ("bottomRadius", "stackBottom")):
    expr = prop(side)
    cond = expr.split("?")[0]
    assert "root.standalone" in cond and f"root.{end}" in cond, \
        f"NotificationGroup: {side} is `{expr}`; it must take the outer radius when standalone or at its end"
    assert re.search(rf"Behavior on {side}\s*\{{\s*animation: Appearance\.animation\.elementMove\w*", group), \
        f"NotificationGroup: {side} does not animate on a spatial elementMove* spec (a corner is a shape)"

assert re.search(r"stackTop:\s*group\.index === 0", view), "NotificationListView: the first group is not the stack's top"
assert re.search(r"stackBottom:\s*group\.index === root\.count - 1", view), "NotificationListView: the last group is not the stack's bottom"

print("ok: the app name is capped at ceil(advanceWidth), and only the sidebar's groups join")
