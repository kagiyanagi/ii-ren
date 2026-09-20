#!/usr/bin/env python3
"""SwipeDismissible's dismiss contract: the numbers DESIGN.md 3.6 names, and
the owner-coupling fix that let something other than a ListView row use it.

`SwipeDismissible` used to read `owner.parent.parent` and then call
`.resetDrag()` / write `.dragIndex` / `.dragDistance` on whatever that
resolved to, unconditionally. Fine inside a `StyledListView` (the ancestor two
hops up carries that contract); a crash the moment `owner` is not a list
delegate, because the guess still lands on a real Item, just one with none of
those members. `ii-clipboardToast` hit exactly this and hand-rolled its own
dismiss instead of using the shared widget (.audit/ii-clipboardToast/notes.md).

Neither half shows up in check-design.py: one is two numbers with no token to
check against, the other is a null-safety shape spread across three call
sites that a design-lint regex has no reason to look for.

Run: python3 tools/check-swipe-dismissible.py
"""
import re
import sys
from pathlib import Path

WIDGETS = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii/modules/common/widgets"
SRC_PATH = WIDGETS / "SwipeDismissible.qml"
LINES = SRC_PATH.read_text().splitlines()
SRC = "\n".join(LINES)

failures = []


def fail(msg):
    failures.append(msg)


# --- 1. the numbers DESIGN.md 3.6 names ---------------------------------------

if not re.search(r"property real dragConfirmThreshold:\s*70\b", SRC):
    fail("dragConfirmThreshold is no longer 70 -- DESIGN.md 3.6 names a 70px confirm threshold")

for fraction in ("0.3", "0.1"):
    # `*` right before it, not just the digits -- both numbers already appear
    # in this file's own docstring prose, which must not satisfy the check.
    if not re.search(rf"\*\s*{re.escape(fraction)}\b", SRC):
        fail(f"neighbour-follow fraction {fraction} is missing -- 3.6 wants neighbours at 0.3 and 0.1 of the drag")

# --- 2. every reach into the shared parent is guarded -------------------------

# The three ways this widget touches `qmlParent` beyond a plain, already-safe
# `?.` read: calling a function on it, or writing one of its two properties.
# None of the three may fire on a `qmlParent` that doesn't actually implement
# the shared-drag contract -- that's exactly the crash a lone, non-ListView
# owner used to hit.
DANGEROUS = [
    re.compile(r"root\.qmlParent\.resetDrag\(\)"),
    re.compile(r"root\.qmlParent\.dragIndex\s*="),
    re.compile(r"root\.qmlParent\.dragDistance\s*="),
]
GUARD = "hasSharedDragState"
WINDOW = 3  # lines of look-back for an enclosing `if (...guard...)`

for pattern in DANGEROUS:
    m = pattern.search(SRC)
    if not m:
        fail(f"pattern gone from the file: {pattern.pattern!r} -- update this checker if it moved")
        continue
    lineno = SRC.count("\n", 0, m.start())  # 0-indexed line of the match
    window = "\n".join(LINES[max(0, lineno - WINDOW):lineno + 1])
    if GUARD not in window:
        fail(f"{SRC_PATH.name}:{lineno + 1}: `{m.group(0)}` is not gated on `{GUARD}` -- "
             f"an owner with no shared-drag parent (or the wrong kind of parent) crashes here")

if re.search(r"readonly\s+property\s+var\s+qmlParent\b", SRC):
    fail("qmlParent is readonly again -- a caller outside a ListView can no longer "
         "supply its own shared-drag object, which is the whole point of the loosening")

if "root.dragDiffX" not in SRC:
    fail("xOffset's own-row branch no longer reads this instance's own dragDiffX -- "
         "an owner with no qmlParent would stop tracking its own drag")

# The own-row fix leans on DragManager still exposing this; a rename there
# would silently break it without either file's own diff looking wrong.
DRAG_MANAGER_SRC = (WIDGETS / "DragManager.qml").read_text()
if not re.search(r"property real dragDiffX\b", DRAG_MANAGER_SRC):
    fail("DragManager no longer exposes dragDiffX -- SwipeDismissible's own-row xOffset depends on it")

if failures:
    print("FAIL: SwipeDismissible's dismiss contract")
    for f in failures:
        print(f"  {f}")
    sys.exit(1)

print("ok: dragConfirmThreshold is 70, neighbour fractions are 0.3/0.1 (DESIGN.md 3.6)")
print(f"ok: all {len(DANGEROUS)} reaches into qmlParent are gated on {GUARD}")
print("ok: qmlParent is overridable and the own-row case does not depend on it")
