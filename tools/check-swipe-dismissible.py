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

The third half is the drag that ends without a release. `onReleased` is the
only thing that takes `dragging` back, and it reaches neither of the two
endings a real gesture actually hits: the row losing `interactive` under the
finger, and the grab being taken away -- which is what a wheel turn during a
swipe does, and what the list does the moment it starts scrolling under one.
`onCanceled` covered the second by re-emitting `released()`, and that signal
takes a MouseEvent, so QML threw "Insufficient arguments" and abandoned the
handler on that line, every time. `dragging` stayed true, the snap-back
Behavior is gated on it, and the card stopped dead wherever the gesture died.
The code reads correctly, the failure is a log line nobody reads, and the only
symptom is a notification sitting half-swiped until it is dismissed.

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

# --- 3. the broadcast is always handed back ----------------------------------

# `dragDistance` lives on the shared parent and moves every neighbour by 0.3 /
# 0.1 of it. Two ways the dragging row can stop without a `dragReleased`, both
# of which used to leave that value standing for the life of the list -- rows
# stuck half a swipe aside, with no gesture left to take them back.

if not re.search(r"Component\.onDestruction:\s*\{[^}]*resetDrag\(\)", SRC, re.S):
    fail("SwipeDismissible does not reset the shared drag on destruction -- a row "
         "destroyed mid-drag (a popup expiring under the finger) leaves dragDistance "
         "set, and every neighbour keeps its nudge")

# --- 4. a drag that ends without a release ------------------------------------

# `onReleased` is the only thing that takes `dragging` back, and two endings
# never reach it. Both leave the flag standing, and the callers below switch
# their snap-back animation off while it is -- so the row stops dead at the
# offset the gesture died at and stays there for as long as it lives.

BLOCK = r"(\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\})"


def handler_body(name: str) -> str:
    """A handler's body, with one level of `root.fn()` indirection inlined."""
    m = re.search(rf"{name}:\s*(?:\([^)]*\)\s*=>\s*)?(?:{BLOCK}|([^\n]+))", DRAG_MANAGER_SRC)
    if not m:
        return ""
    body = m.group(1) or m.group(2)
    for fn in sorted(set(re.findall(r"root\.(\w+)\(\)", body))):
        called = re.search(rf"function {fn}\([^)]*\)[^{{]*{BLOCK}", DRAG_MANAGER_SRC)
        if called:
            body += called.group(1)
    return body


for handler, why in (
    ("onInteractiveChanged",
     "a row that loses interactivity mid-drag -- a group collapsing under the finger --"
     " never releases, because `onReleased` early-returns on that same flag"),
    ("onCanceled",
     "a stolen grab never releases at all: a wheel turn during a swipe takes it, and so"
     " does the list the moment it starts scrolling under one"),
):
    body = handler_body(handler)
    if not body:
        fail(f"DragManager has no {handler} -- {why}")
        continue
    if "resetDrag()" not in body or not re.search(r"dragging\s*=\s*false", body):
        fail(f"DragManager's {handler} does not end the drag: {why}")
    # What this replaced: `onCanceled` re-emitted `released()` to stand in for
    # the MouseEvent `canceled` does not carry. `released` is declared with one
    # argument, so QML answered every cancelled grab with "Insufficient
    # arguments" -- a thrown exception, which abandoned the rest of the handler.
    # It reads correctly, it fails only at runtime, and it says so in a log line
    # nobody was reading.
    for signal in ("released", "pressed", "clicked", "positionChanged", "canceled"):
        if re.search(rf"(?<![.\w]){signal}\(\s*\)", body):
            fail(f"DragManager's {handler} emits `{signal}()` with no MouseEvent -- QML "
                 "throws Insufficient arguments and abandons the rest of the handler")

# Wherever the pair appears, the flag goes first: the offset is what the
# callers animate, and taking it away while their Behavior is still switched
# off sends the row home in one frame instead.
for block in re.findall(BLOCK, DRAG_MANAGER_SRC):
    ended = re.search(r"dragging\s*=\s*false", block)
    if "resetDrag()" in block and ended and block.index("resetDrag()") < ended.start():
        fail("DragManager clears the drag offset before `dragging` -- the snap-back "
             "Behavior is gated on that flag, so the row jumps home unanimated")

# The flag the rule above exists for. If a row stops gating its snap-back on
# it, the ordering is measuring nothing for that row.
for rel in ("NotificationGroup.qml", "NotificationItem.qml"):
    if not re.search(r"Behavior on anchors\.leftMargin \{\s*\n\s*enabled: !\w+\.dragging",
                     (WIDGETS / rel).read_text()):
        fail(f"{rel} no longer gates its leftMargin Behavior on `dragging` -- the row "
             "either animates under the finger or snaps home without animating")

if failures:
    print("FAIL: SwipeDismissible's dismiss contract")
    for f in failures:
        print(f"  {f}")
    sys.exit(1)

print("ok: dragConfirmThreshold is 70, neighbour fractions are 0.3/0.1 (DESIGN.md 3.6)")
print(f"ok: all {len(DANGEROUS)} reaches into qmlParent are gated on {GUARD}")
print("ok: qmlParent is overridable and the own-row case does not depend on it")
print("ok: the shared drag is handed back on destruction and on losing interactivity")
print("ok: a cancelled grab ends the drag, in that order, and emits no argument-less signal")
