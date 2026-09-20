#!/usr/bin/env python3
"""Assert a notification group expands and collapses, both ways, on a spatial spec.

DESIGN.md 9 asks for "group expansion on default spatial", 2.1 puts size on a
spatial spec and 2.5 wants enter and exit to differ. The widget shipped all
three wrong at once, and none of it is visible to check-design.py:

  - `toggleExpanded()` set `implicitHeightAnim.enabled = false` before expanding,
    so the card *snapped* open and only animated shut. A disabled Behavior has no
    line for a regex to flag -- the bug is an absence.
  - the height and the row spacing both ran on `elementMoveFast`, which is the
    *default effects* spec. check-design.py has a rule for the opposite mistake
    (a spatial spec on opacity or colour) and none for this one, because an
    effects curve on a size is merely wrong, not broken.

So the contract is asserted here instead: one AnimSpec property, two different
specs assigned to it inside the toggle, a spatial one for the enter, and no
size/shape Behavior in the family left on the effects spec.

Run: python3 tools/check-notification-expansion.py
"""
import pathlib
import re
import sys

WIDGETS = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"
GROUP = WIDGETS / "NotificationGroup.qml"

# Appearance.animation.* specs whose curve is spatial -- they may overshoot, which
# is what a card growing open is allowed to do.
SPATIAL = {"elementMove", "elementMoveEnter", "elementMoveSmall", "elementResize", "clickBounce"}
# The default-effects spec. Correct for opacity and colour, wrong for a size.
EFFECTS_DEFAULT = "elementMoveFast"

# Properties in this family that are position, size or shape.
SPATIAL_PROPS = ("implicitHeight", "spacing", "rotation", "anchors.leftMargin")


def block(src: str, start: int) -> str:
    """Brace-matched text of the block that opens at or after `start`."""
    depth, i = 0, src.index("{", start)
    for j in range(i, len(src)):
        depth += (src[j] == "{") - (src[j] == "}")
        if depth == 0:
            return src[i:j + 1]
    return src[i:]


group = GROUP.read_text()

# One spec property, switched by the toggle rather than one Behavior turned off.
spec_prop = re.search(r"property AnimSpec (\w+):", group)
assert spec_prop, \
    "NotificationGroup: no `property AnimSpec` -- expansion cannot carry a per-direction spec"
spec = spec_prop.group(1)

toggle = re.search(r"function toggleExpanded\s*\(", group)
assert toggle, "NotificationGroup: toggleExpanded() is gone -- what drives the expansion now?"
body = block(group, toggle.end())

assert not re.search(r"\.enabled\s*=\s*false", body), \
    ("NotificationGroup.toggleExpanded: disables a Behavior, so one direction snaps. "
     "Switch the AnimSpec instead of switching the animation off (DESIGN.md 2.5)")

writes = " ".join(re.findall(rf"{spec}\s*=([^;]*);", body))
assigned = re.findall(r"Appearance\.animation\.(\w+)", writes)
assert len(set(assigned)) == 2, \
    (f"NotificationGroup.toggleExpanded: assigns {sorted(set(assigned)) or 'nothing'} to "
     f"{spec} -- expanding is an enter and collapsing an exit, so they need two specs (2.5)")
enter = [a for a in assigned if a in SPATIAL]
assert enter, \
    (f"NotificationGroup.toggleExpanded: neither of {sorted(set(assigned))} is a spatial spec. "
     "The card's height is a size and the expansion may overshoot (DESIGN.md 9, 2.1)")

# Nothing in the family animates a size or a shape on the default-effects spec.
for path in sorted(WIDGETS.glob("Notification*.qml")):
    src = path.read_text()
    for m in re.finditer(r"Behavior on ([\w.]+)", src):
        if m.group(1) not in SPATIAL_PROPS:
            continue
        text = re.sub(r"//.*", "", block(src, m.end()))
        assert EFFECTS_DEFAULT not in text, \
            (f"{path.name}: `Behavior on {m.group(1)}` runs on {EFFECTS_DEFAULT}, the default "
             f"*effects* spec. A size moves on a spatial one (DESIGN.md 2.1)")

print(f"ok: notification expansion switches {spec} both ways, and no size runs on {EFFECTS_DEFAULT}")
