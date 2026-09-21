#!/usr/bin/env python3
"""Assert the cheatsheet shows all of its content, and opens and closes on a spec.

Two shapes here that a screenshot of this machine cannot catch.

The first is reachability. A cheatsheet that hides bindings is not a cheatsheet, and
this one hid them in both directions: the keybinds flow was pinned to the viewport
(`contentHeight: height`), so a category taller than the window was cut off mid-row,
and the horizontal overflow could be dragged but had no scrollbar to say it was
there. Whether that happens depends on the screen, the font size and how many binds
the user's Hyprland config declares -- none of which the developer's desktop
exercises. So the content-bounds expressions are lifted out of the QML and evaluated
against category shapes that do not fit.

The second is the window itself. `Loader.active` destroys the surface, so an exit
animation hung off it never renders once -- the defect AltTab had, invisible in a
still frame and easy to reintroduce by "simplifying" the two booleans back into one.

Run: python3 tools/check-cheatsheet.py
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/ii/cheatsheet"
sheet = (ROOT / "Cheatsheet.qml").read_text()
keybinds = (ROOT / "CheatsheetKeybinds.qml").read_text()
timetable = (ROOT / "CheatsheetTimetable.qml").read_text()
tile = (ROOT / "ElementTile.qml").read_text()
category = (ROOT / "CheatsheetKeybindsCategory.qml").read_text()
table = (ROOT / "CheatsheetPeriodicTable.qml").read_text()

fail = []


def check(ok, msg):
    if not ok:
        fail.append(msg)


# --- 1. the window opens and closes on a spec, and outlives its own exit -------

check("property bool open" in sheet and "property bool rendered" in sheet,
      "intent and mapping have been merged back into one flag -- `Loader.active: false` "
      "destroys the window, so the exit animation never renders")
check(re.search(r"active: root\.rendered", sheet),
      "the loader is no longer driven by `rendered`")
check(re.search(r"onRevealChanged:.*root\.rendered = false", sheet),
      "nothing clears `rendered` when the exit lands, so the window is never unmapped")
check("transformOrigin: Item.Center" in sheet,
      "the card scales with no stated origin (DESIGN.md 2.6)")

# Enter decelerates over the full spec, exit accelerates at half of it (2.5).
check("emphasizedDecel" in sheet and "emphasizedAccel" in sheet,
      "the enter/exit pair is not asymmetric any more (2.5)")
check(re.search(r"elementMove\.duration / 2", sheet),
      "the exit no longer runs at half the enter duration (2.5)")
# Default spatial, not effects: this is the largest surface in the shell, and
# 2.4 puts something screen-sized at 500ms. 0.92 of a 1400px card was 112px of
# travel at the ladder's fastest rung, which is what read as a lurch.
check("Appearance.animation.elementMove.duration" in sheet,
      "the reveal duration is not the default spatial token any more (2.4)")
closed = re.search(r"readonly property real closedScale: ([\d.]+)", sheet)
check(closed and float(closed.group(1)) >= 0.95,
      "closedScale is back below 0.95 -- on a surface this size that is a lurch, not a grow")
# QQC2 hard-codes highlightMoveDuration: 250 in the style's own contentItem.
check('property: "highlightMoveDuration"' in sheet,
      "the page slide is back on QtQuick.Controls' literal 250ms")

# The 2s keyboard-focus timer measured as pure cost: Escape, Ctrl+Tab and
# Ctrl+PageUp/Down were all dead for two seconds after the sheet appeared.
check("keyboardFocusTimer" not in sheet,
      "the deferred keyboard-focus timer is back -- Escape does nothing until it fires")
check("WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand" in sheet,
      "the window takes no keyboard focus, so Escape and the tab keybinds never arrive")

# Law 8: the mask was a full-window framebuffer rounding nothing that shows.
check("layer.enabled" not in sheet and "OpacityMask" not in sheet,
      "the SwipeView mask is back -- a full-window layer for a radius under content "
      "that is either its own rounded card or fully transparent (law 8)")


# --- 2. the keybinds tab can reach every bind ---------------------------------

def expr(src, pattern, what):
    m = re.search(pattern, src)
    if not m:
        fail.append(f"{what} -- this check is stale")
        return None
    return m.group(1).strip()


content_h = expr(keybinds, r"contentHeight: (Math\.max\([^\n]+\))", "the keybinds contentHeight is gone")
content_w = expr(keybinds, r"contentWidth: (Math\.max\([^\n]+\))", "the keybinds contentWidth is gone")
check("ScrollBar.horizontal" in keybinds,
      "the horizontal overflow has no scrollbar again -- draggable, but nothing says so")

# --- 2b. no column runs past the bottom of the sheet -------------------------
#
# A category longer than the viewport is cut into blocks that each fit, so the
# sheet only ever scrolls sideways. The arithmetic is what decides that, and it
# depends on the screen, the keycap font size and how many binds the user
# declares -- this machine exercises exactly one of the possible shapes.

rows_expr = expr(keybinds, r"readonly property int rowsPerColumn: (Math\.max\(1, Math\.floor\(\n[^\n]+\)\))",
                 "the keybinds column capacity is gone")


def rows_per_column(view_h, header_h, row_h, row_gap):
    if rows_expr is None:
        return 0
    return eval(  # noqa: S307 - the input is the literal matched above
        rows_expr.replace("Math.max(", "max(").replace("Math.floor(", "floor(")
                 .replace("flickable.height", "view_h")
                 .replace("root.headerBlockHeight", "header_h")
                 .replace("root.rowHeight", "row_h")
                 .replace("root.rowSpacing", "row_gap"),
        {"max": max, "floor": math.floor, "view_h": view_h, "header_h": header_h,
         "row_h": row_h, "row_gap": row_gap},
    )


for view_h, header_h, row_h, row_gap in [
    (732, 32, 24, 4),    # this machine: 1080p, shipped font sizes
    (732, 32, 40, 4),    # a much larger keycap font
    (380, 32, 24, 4),    # a 720p screen
    (40, 32, 24, 4),     # a window too short to hold even one row
    (2100, 48, 30, 8),   # a 4K screen, larger everything
]:
    per = rows_per_column(view_h, header_h, row_h, row_gap)
    check(per >= 1, f"a {view_h}px viewport yields {per} rows per column -- a column with no rows")
    block = header_h + per * row_h + (per - 1) * row_gap
    check(block <= view_h or per == 1,
          f"a full block is {block}px in a {view_h}px viewport -- it would run off the bottom, "
          "which is the whole thing this layout exists to stop")

# The packing itself: every block fits, and a split category repeats its heading.
check("continued" in keybinds and "continued" in category,
      "a category cut across columns no longer says so, so the second column is a headerless list")
check("model: root.binds" in category,
      "the category filters its own binds again -- only the parent knows how tall a column is, "
      "so the parent has to own the packing")
for per_column, total in [(25, 28), (25, 25), (25, 1), (25, 100), (1, 5)]:
    blocks = [(i, min(per_column, total - i)) for i in range(0, total, per_column)]
    check(sum(n for _, n in blocks) == total, f"{total} binds at {per_column}/column lost some")
    check(all(n <= per_column for _, n in blocks), f"{total} binds at {per_column}/column overfilled a block")
    check(all((i > 0) == (k > 0) for k, (i, _) in enumerate(blocks)),
          "the continuation flag does not match the block index")


def js(text, viewport_w, viewport_h, rect_w, rect_h):
    """The two expressions, as Python. `childrenRect` is what the flow laid out."""
    return eval(  # noqa: S307 - the input is the two literals matched above
        text.replace("Math.max(", "max(")
            .replace("flow.childrenRect.height", "rect_h")
            .replace("flow.childrenRect.width", "rect_w")
            .replace("height", "viewport_h")
            .replace("width", "viewport_w"),
        {"max": max, "viewport_w": viewport_w, "viewport_h": viewport_h,
         "rect_w": rect_w, "rect_h": rect_h},
    )


if content_h and content_w:
    # (viewport, laid-out content) pairs. The third is this machine's shipped shape:
    # a 1920x1080 screen gives the tab 0.7 of each axis, the Window category runs to
    # ~1100px and the seven columns to ~1700px. Both overflowed, silently.
    for vw, vh, rw, rh in [
        (1344, 756, 1700, 1100),   # both axes over -- the shipped default
        (1344, 756, 900, 400),     # everything fits
        (1344, 756, 1344, 3000),   # one category far taller than the window
        (600, 400, 2400, 400),     # a small screen, wide content
        (1344, 756, 0, 0),         # no binds at all
    ]:
        ch = js(content_h, vw, vh, rw, rh)
        cw = js(content_w, vw, vh, rw, rh)
        check(ch >= rh, f"{rh}px of binds in a {vh}px viewport: contentHeight {ch} clips them")
        check(cw >= rw, f"{rw}px of binds in a {vw}px viewport: contentWidth {cw} clips them")
        check(ch >= vh and cw >= vw,
              f"content bounds {cw}x{ch} are smaller than the {vw}x{vh} viewport -- "
              "the flickable would scroll its own empty space")

# `a?.b * 0.7 ?? 0` parses as `(a?.b * 0.7) ?? 0`, and `??` does not catch NaN.
check(not re.search(r"screen\.\w+ \* [\d.]+ \?\?", keybinds),
      "the screen-size fallback is back outside the optional chain, where NaN slips past it")


# --- 3. the timetable survives a week with no days ----------------------------

day_col = expr(timetable, r"readonly property real dayColumnWidth: ([^\n]+\n[^\n]+)",
               "the timetable dayColumnWidth is gone")
check(day_col is not None and "hasDays" in (day_col or ""),
      "dayColumnWidth divides by days.length with no guard -- an empty week is n/0")

for days in range(0, 8):
    # The shipped constants, and the expression as the QML writes it.
    max_content, time_col, spacing = 1350, 100, 8
    width = 0 if days == 0 else min(180, (max_content - time_col - (days + 1) * spacing) / days)
    check(math.isfinite(width), f"{days} days gives a non-finite day column width")
    implicit = max_content if days == 0 else min(
        max_content, time_col + width * days + (days + 1) * spacing)
    check(math.isfinite(implicit) and implicit > time_col * 2,
          f"{days} days collapses the timetable to {implicit}px")

check("PagePlaceholder" in timetable,
      "an empty week has no placeholder -- it renders as a sliver with a lone clock (9)")
# The contrast of a label has to come from the colour actually painted: an event with
# no colour of its own gave getContrastingTextColor `undefined`, whose NaN luminance
# fails `< 0.5` and returns black, on a dark card.
check("getContrastingTextColor(modelData.color)" not in timetable,
      "event label contrast is computed from the raw model colour again, which may be undefined")
check(re.search(r"property color onFill: ColorUtils\.getContrastingTextColor\(eventCard\.fill\)", timetable),
      "the event label no longer takes its contrast from the fill on screen")
check("Behavior on y" in timetable,
      "the current-time line jumps to its new position instead of moving on a spatial spec")
# Law 11: an outline colour used as a fill is a divider whatever it is called.
check(not re.search(r"Layout\.preferredHeight: 1\b", timetable),
      "the header hairline is back (law 11)")
check("colOutlineVariant" not in timetable.replace("border.color: Appearance.colors.colOutlineVariant", ""),
      "colOutlineVariant is being used as a fill again, not just as the card border (law 11)")
for dead in ("allDayChipHeight", "allDayChipSpacing", "maxAllDayEventCount", "hasAllDayEvents"):
    check(dead not in timetable, f"{dead} is back -- it fed a column of transparent rectangles")


# --- 4. the element tiles are reference, not controls --------------------------

tile_code = re.sub(r"//[^\n]*", "", tile)
check("RippleButton" not in tile_code,
      "ElementTile is a RippleButton again -- a ripple and a hover film for no onClicked")
check("visible: root.filled" in tile,
      "the tile content is no longer gated on `filled`, so the spacers paint `-1` and `0`")
# A `visible: false` on the tile itself collapses the Row and takes the grid with it.
check(not re.search(r"^\s{4}visible:", tile, re.M),
      "the spacer tiles are hidden at the root -- a Row skips invisible children, "
      "so every element after a gap shifts left")
check(re.search(r"left: parent\.left\s*\n\s*right: parent\.right", tile),
      "the element name has no width again, so StyledText cannot elide and long names "
      "paint over the neighbouring tiles")
check("StyledFlickable" in table and "ScrollBar.horizontal" in table,
      "the periodic table is unscrollable again -- it does not fit a 1366px screen")


if fail:
    print(f"check-cheatsheet.py: {len(fail)} finding(s)\n")
    for f in fail:
        print(f"  FAIL  {f}")
    sys.exit(1)
print("check-cheatsheet.py: ok")
