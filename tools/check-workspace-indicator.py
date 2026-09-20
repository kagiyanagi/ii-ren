#!/usr/bin/env python3
"""Assert the bar's active-workspace indicator lands on the workspace it points at.

The indicator slides and stretches between workspaces and is the most-watched
motion in the shell, so the ways it can be wrong are all invisible on the desktop
this gets written on: a laptop with five equal-width workspaces, icons off,
dynamicWorkspaces off, exercises none of the arithmetic below.

Two shapes it used to get wrong.

*Mixed coordinate systems.* Position came from `pairMin * iconBoxWrapperSize` --
slots of one fixed size -- plus a correction summed over *raw* child indices. A
workspace is only that size when it is empty: it grows with the app icons in it,
and under `dynamicWorkspaces` an empty one takes no room at all while still
holding a child index. Icons on and dynamic workspaces on, the two halves
disagreed and the pill sat beside its workspace.

*Two timings on one pill.* Position and length are the two ends of one shape.
They now share every term -- the same `slotEdge()` and the same `visualInset`,
which carries the only Behavior -- so they cannot arrive at different times.
`ii-background-root` shipped the other version of this bug and its notes say how
it reads.

The geometry is reimplemented here rather than imported (QML cannot be), so the
structural asserts in part 1 are what keep this file honest: they fail the moment
the QML stops having the shape part 2 models.

Run: python3 tools/check-workspace-indicator.py
"""
import math
import pathlib
import re
import sys

QML = (pathlib.Path(__file__).parent.parent
       / "dots/.config/quickshell/ii/modules/ii/bar/Workspaces.qml")
src = QML.read_text()

# --- 1. structural: the QML still has the shape this file models --------------

STRUCTURE = [
    (r"function slotSize\(k: int\): real",
     "slotSize() is gone -- the indicator is measuring slots some other way"),
    (r"function slotEdge\(v: real\): real",
     "slotEdge() is gone -- the indicator is measuring slots some other way"),
    (r"function slotsBefore\(index: int\): int",
     "slotsBefore() is gone -- raw and visible workspace indices are mixed again"),
    (r"if \(!item\?\.visible\)\s*\n\s*continue;",
     "slotSizes counts hidden workspaces again -- they take no room in the strip"),
    (r"if \(!item\?\.visible\) continue;",
     "hoverIndex counts hidden workspaces again -- clicks land on the wrong one"),
    (r"size > 0 \? size : root\.iconBoxWrapperSize",
     "the NaN guard in slotSizes is gone; Math.max does not replace it"),
    (r"n === 0 \|\| !isFinite\(v\)",
     "slotEdge no longer guards a non-finite index -- one NaN blanks the bar"),
    (r"property real indicatorPosition: root\.slotEdge\(leadSlot\) \+ visualInset",
     "the active indicator's position is not slotEdge(lead) + inset any more"),
    (r"property real indicatorLength: Math\.max\(0, root\.slotEdge\(trailSlot \+ 1\)"
     r" - root\.slotEdge\(leadSlot\) - visualInset \* 2\)",
     "the active indicator's length is not the gap between two slot edges any more"),
    (r"property real indicatorPosition: root\.slotEdge\(hoverSlot\) \+ hoverInset",
     "the hover indicator stopped using the shared slot geometry"),
]
for pattern, complaint in STRUCTURE:
    assert re.search(pattern, src), complaint

# Position and length are one shape. `visualInset` is the only term of theirs
# that steps rather than travelling, so it carries the only Behavior -- and it
# must be the spec the motion table gives position and size. A Behavior on
# either end separately is how the two ends drift apart.
inset_behavior = re.search(
    r"Behavior on visualInset \{\s*\n\s*animation: Appearance\.animation\.(\w+)\.", src)
assert inset_behavior, "visualInset lost its Behavior -- the pill's inset pops again"
assert inset_behavior.group(1) == "elementMove", (
    f"visualInset animates on {inset_behavior.group(1)}; position and size take "
    "elementMove (DESIGN.md 2.3)")
assert "Behavior on indicatorPosition" not in src.split("id: hoverIndicator")[0], (
    "the active indicator animates its position separately again -- that is a "
    "second spec on one of the pill's two ends")

# Both ends of the hover pill travel on one spec too.
hover_specs = re.findall(
    r"Behavior on indicator(?:Position|Length) \{\s*\n\s*id: \w+\s*\n\s*"
    r"animation: Appearance\.animation\.(\w+)\.", src)
assert len(hover_specs) == 2 and len(set(hover_specs)) == 1, (
    f"the hover pill's ends animate on {set(hover_specs) or 'nothing'} -- one spec, both ends")

S = int(re.search(r"property int iconBoxWrapperSize: (\d+)", src).group(1))

# --- 2. the geometry ----------------------------------------------------------


def slot_sizes(widths, visible):
    """Workspaces.qml's `slotSizes`: visible children's real sizes, NaN-safe."""
    out = []
    for w, vis in zip(widths, visible):
        if not vis:
            continue
        out.append(w if w > 0 else S)  # `>` and not Math.max: NaN fails it
    return out


def slot_size(sizes, k):
    if not sizes:
        return S
    return sizes[max(0, min(len(sizes) - 1, k))]


def slot_edge(sizes, v):
    n = len(sizes)
    if n == 0 or not math.isfinite(v):
        return 0
    whole = math.floor(v)
    edge = 0
    if whole <= 0:
        edge = whole * sizes[0]
    else:
        edge = sum(sizes[:min(whole, n)])
        if whole > n:
            edge += (whole - n) * sizes[n - 1]
    return edge + (v - whole) * slot_size(sizes, whole)


def slots_before(visible, index):
    return sum(1 for i in range(index) if visible[i])


def hover_index(widths, visible, position):
    """The MouseArea's `hoverIndex`: raw index under the pointer."""
    accumulated, last = 0, 0
    for i, (w, vis) in enumerate(zip(widths, visible)):
        if not vis:
            continue
        last = i
        if position < accumulated + w:
            return i
        accumulated += w
    return last


def pill(sizes, lead, trail, inset):
    pos = slot_edge(sizes, lead) + inset
    length = max(0, slot_edge(sizes, trail + 1) - slot_edge(sizes, lead) - inset * 2)
    return pos, length


# --- 3. the shapes the desktop this was written on cannot produce -------------

# Uneven widths are the normal case with app icons on: a workspace holding three
# icons is wider than an empty one.
LAYOUTS = [
    ([S] * 10, [True] * 10),                                  # the boring case
    ([S, 44, S, 62, S, S, 30, S, S, S], [True] * 10),         # icons, static workspaces
    ([S, 44, S, 62, S, S, 30, S, S, S],                       # dynamic: 4 of 10 shown
     [True, False, True, False, False, True, True, False, False, False]),
    ([S] * 10, [i == 3 for i in range(10)]),                  # dynamic, one workspace
    ([S, 40], [True, True]),                                  # two
    ([S] * 10, [False] * 10),                                 # nothing shown yet
    ([float("nan")] * 4 + [S] * 6, [True] * 10),              # widths not measured yet
    ([0] * 10, [True] * 10),                                  # mid-construction
]

INSETS = [S * 0.07 - 0.5, S * 0.07, S * 0.14, S * 0.1]

for widths, visible in LAYOUTS:
    sizes = slot_sizes(widths, visible)
    n = len(sizes)

    # One entry per *visible* workspace and nothing else. A hidden delegate is
    # skipped by the GridLayout but keeps whatever width it last had, so a loop
    # that counts it is not off by a zero -- it is off by a whole workspace.
    assert n == sum(visible), \
        f"slotSizes has {n} entries for {sum(visible)} visible workspaces"
    assert sizes == [w if w > 0 else S for w, vis in zip(widths, visible) if vis], \
        f"slotSizes {sizes} is not the visible widths of {widths}"

    # Nothing is ever NaN or infinite, whatever the pointer and the springs do.
    for v in [-1.3, -0.06, 0, 0.5, 1, 2.4, n - 1, n, n + 0.06, n + 3,
              float("nan"), float("inf"), float("-inf")]:
        for inset in INSETS:
            pos, length = pill(sizes, min(v, v), max(v, v), inset)
            assert math.isfinite(pos), f"position {pos} for v={v}, {sizes}"
            assert math.isfinite(length), f"length {length} for v={v}, {sizes}"
            assert length >= 0, f"negative length {length} for v={v}, {sizes}"

    if n == 0:
        continue

    # Settled on slot k, the pill spans exactly that workspace, inset on both
    # sides. This is the assertion the old arithmetic failed whenever the
    # workspaces were not all the same width.
    for inset in INSETS:
        for k in range(n):
            pos, length = pill(sizes, k, k, inset)
            left = slot_edge(sizes, k)
            right = slot_edge(sizes, k + 1)
            assert abs(pos - (left + inset)) < 1e-9, \
                f"slot {k} of {sizes}: pill starts at {pos}, workspace at {left}"
            assert abs((pos + length) - (right - inset)) < 1e-9, \
                f"slot {k} of {sizes}: pill ends at {pos + length}, workspace at {right}"

    # Mid-stretch, the pill covers both the slot it left and the one it is
    # heading for, and never less than the wider of the two.
    for a in range(n):
        for b in range(n):
            lead, trail = min(a, b), max(a, b)
            pos, length = pill(sizes, lead, trail, 0)
            assert abs(pos - slot_edge(sizes, lead)) < 1e-9
            assert abs((pos + length) - slot_edge(sizes, trail + 1)) < 1e-9

    # Slot edges are the running total of the real widths -- no fixed-size
    # slot arithmetic left anywhere in the path.
    running = 0
    for k, w in enumerate(sizes):
        assert abs(slot_edge(sizes, k) - running) < 1e-9, \
            f"edge of slot {k} is {slot_edge(sizes, k)}, widths say {running}"
        running += w
    assert abs(slot_edge(sizes, n) - sum(sizes)) < 1e-9

    # The overshoot at either end extrapolates instead of piling up on the edge:
    # the expressive spatial curve goes past its target and the pill has to
    # follow it out, not fold flat against the first or last workspace.
    assert slot_edge(sizes, -0.1) < 0, "undershoot past the first workspace clamps flat"
    assert slot_edge(sizes, n + 0.1) > sum(sizes), "overshoot past the last one clamps flat"

    # A click lands on the workspace under the pointer, and the hover pill lands
    # on the same one. Hidden workspaces take no room in either.
    # A hidden workspace keeps the width the layout last gave it -- it does not
    # drop to zero -- so the stale value has to be here, or a walk that forgets
    # to skip hidden children still lands on the right workspace by luck.
    raw_of_slot = [i for i, vis in enumerate(visible) if vis]
    rendered = [float(S) for _ in visible]
    for slot, raw in enumerate(raw_of_slot):
        rendered[raw] = sizes[slot]

    x = 0.0
    for slot, raw in enumerate(raw_of_slot):
        w = sizes[slot]
        for probe in (x + 0.5, x + w / 2, x + w - 0.5):
            hit = hover_index(rendered, visible, probe)
            assert hit == raw, \
                f"pointer at {probe} in slot {slot} hit workspace {hit}, wanted {raw}"
            assert slots_before(visible, hit) == slot, \
                f"workspace {hit} is not visible slot {slot}"
        x += w

print(f"workspace indicator: {len(LAYOUTS)} layouts x {len(INSETS)} insets ok")
sys.exit(0)
