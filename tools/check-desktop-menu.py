#!/usr/bin/env python3
"""The desktop menu grows out of the corner nearest the cursor, and its
wallpaper strip only exists when there is a wallpaper to switch to.

Three things in `modules/ii/desktopMenu/DesktopMenu.qml` are expressions, not
pictures, so no screenshot proves any of them:

- **The pivot.** AOSP's ArrowPopup.setPivotForOpenCloseAnimation() grows a popup
  out of the corner nearest the touch point. The card is placed at the cursor
  and then shifted back inside the screen near an edge, so "nearest corner" has
  to be asked of the *placed* card. The version this replaced asked it of the
  clamp instead -- `x >= cursorX` -- which is the same answer everywhere except
  the one pixel where the shift begins: there the card moves one pixel, the
  cursor ends up one pixel inside the left edge, and the pivot jumps to the far
  corner. It then stays wrong for the next half a card width -- a 160px band
  down the right edge of every screen, and another along the bottom -- which is
  a region nobody right-clicks in on purpose, so it is swept here.

- **The one-item strip.** `~/Pictures/Wallpapers` not existing is enough to
  leave the strip holding nothing but the wallpaper already applied: 132dp of
  card that can only re-select what is selected. It was the live state on the
  machine this was written on.

- **The shuffle.** The strip is reshuffled per open and must still lead with the
  current wallpaper, carry every other valid one exactly once, and never show
  the current one twice.

    python3 tools/check-desktop-menu.py
"""

import random
import re
from pathlib import Path

QML = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/desktopMenu/DesktopMenu.qml"

GUTTER = 8  # menuCard.gutter
CARD_W = 320  # menuCard.implicitWidth


# -- placement, lifted out of the x/y and leftAligned/topAligned bindings -----


def place(cursor, window, size):
    """menuCard.x / .y: open at the cursor, shifted back inside the screen."""
    return max(GUTTER, min(cursor, window - size - GUTTER))


def pivot(cursor_x, cursor_y, win_w, win_h, w, h):
    """Returns the card's placed rect and the corner it grows out of."""
    x = place(cursor_x, win_w, w)
    y = place(cursor_y, win_h, h)
    left = cursor_x <= x + w / 2
    top = cursor_y <= y + h / 2
    return x, y, left, top


def old_pivot(cursor_x, cursor_y, win_w, win_h, w, h):
    """What it used to be: the clamp's own side, not the nearest corner."""
    x = place(cursor_x, win_w, w)
    y = place(cursor_y, win_h, h)
    return x, y, x >= cursor_x, y >= cursor_y


def corner(x, y, w, h, left, top):
    return (x if left else x + w, y if top else y + h)


def dist2(ax, ay, bx, by):
    return (ax - bx) ** 2 + (ay - by) ** 2


SCREENS = [(1920, 1080), (2560, 1440), (3840, 2160), (1366, 768), (800, 600)]
CARDS = [(CARD_W, 200), (CARD_W, 420), (CARD_W, 560), (CARD_W, 132 + 5 * 52)]

# 1. The pivot is always a nearest corner of the card as placed.
for win_w, win_h in SCREENS:
    for w, h in CARDS:
        for cursor_x in range(0, win_w + 1, 7):
            for cursor_y in range(0, win_h + 1, 29):
                x, y, left, top = pivot(cursor_x, cursor_y, win_w, win_h, w, h)
                cx, cy = corner(x, y, w, h, left, top)
                best = min(
                    dist2(cursor_x, cursor_y, *corner(x, y, w, h, l, t))
                    for l in (True, False)
                    for t in (True, False)
                )
                assert dist2(cursor_x, cursor_y, cx, cy) == best, (
                    f"pivot is not the nearest corner at cursor "
                    f"({cursor_x},{cursor_y}) on {win_w}x{win_h}, card {w}x{h}"
                )

# 2. It flips exactly once across a horizontal sweep, and never at the shift
#    boundary. Two flips, or a flip where the clamp starts, is the old bug.
for win_w, win_h in SCREENS:
    for w, h in CARDS:
        if w + 2 * GUTTER > win_w:
            continue  # card wider than the screen has its own case below
        flips, boundary_flips = 0, 0
        clamp_start = win_w - w - GUTTER
        prev = None
        for cursor_x in range(0, win_w + 1):
            _, _, left, _ = pivot(cursor_x, 0, win_w, win_h, w, h)
            if prev is not None and left != prev:
                flips += 1
                if abs(cursor_x - clamp_start) <= 1:
                    boundary_flips += 1
            prev = left
        assert flips == 1, f"pivot flips {flips}x on {win_w}x{win_h}, card {w}"
        assert boundary_flips == 0, (
            f"pivot flips where the shift begins on {win_w}x{win_h}, card {w}"
        )

# 3. The expression this replaced fails 2, and by the full width of the card.
win_w, win_h, w, h = 1920, 1080, CARD_W, 420
clamp_start = win_w - w - GUTTER
before = old_pivot(clamp_start, 0, win_w, win_h, w, h)
after = old_pivot(clamp_start + 1, 0, win_w, win_h, w, h)
assert before[2] and not after[2], "the old pivot no longer flips at the shift"
jump = abs(corner(*before[:2], w, h, before[2], before[3])[0] - corner(*after[:2], w, h, after[2], after[3])[0])
assert jump >= w - 1, f"expected the old pivot to jump a card width, got {jump}"

# 4. A card that cannot fit still lands inside the screen and keeps a real
#    corner. 800x600 with a tall menu is the shape that gets here.
for win_w, win_h in [(800, 600), (640, 480)]:
    x, y, left, top = pivot(win_w // 2, win_h // 2, win_w, win_h, CARD_W, 900)
    assert x == place(win_w // 2, win_w, CARD_W), "x left the clamp"
    assert y == GUTTER, f"a card taller than the screen must sit at the gutter, got {y}"
    assert isinstance(left, bool) and isinstance(top, bool)


# -- the strip's visibility and its model -------------------------------------


def strip_visible(count, widget_id):
    """stripViewport.visible"""
    return count > 1 and widget_id is None


def shuffled(wallpapers, current, valid):
    """menuColumn.shuffledWallpapers, with the shuffle left to random."""
    rest = [p for p in wallpapers if valid(p) and p != current]
    random.shuffle(rest)
    return ([current] + rest) if valid(current) else rest


IMAGES = {"a.png", "b.jpg", "c.jpeg", "d.mp4"}


def valid(p):
    return p in IMAGES


assert not strip_visible(0, None), "no wallpapers must hide the strip"
assert not strip_visible(1, None), "one wallpaper is the applied one: hide the strip"
assert strip_visible(2, None), "two wallpapers is a choice: show the strip"
assert not strip_visible(9, "widget-1"), "widget mode has no strip"

# The live state that made this a finding: the wallpaper folder does not exist,
# so the only entry is the one already applied.
assert len(shuffled([], "a.png", valid)) == 1
assert not strip_visible(len(shuffled([], "a.png", valid)), None)

# Nothing valid at all, not even the current one, is zero rather than a crash.
assert shuffled([], "nope.txt", valid) == []
assert not strip_visible(0, None)

for _ in range(200):
    model = shuffled(["a.png", "b.jpg", "c.jpeg", "d.mp4", "notes.txt", "sub"], "b.jpg", valid)
    assert model[0] == "b.jpg", "the applied wallpaper must lead, so its check mark shows"
    assert len(model) == len(set(model)), f"duplicate in the strip: {model}"
    assert set(model) == {"a.png", "b.jpg", "c.jpeg", "d.mp4"}, f"lost or kept the wrong entry: {model}"

# A current wallpaper that is not in the folder still leads, and is not counted
# against the folder's entries.
model = shuffled(["a.png", "b.jpg"], "c.jpeg", valid)
assert model[0] == "c.jpeg" and set(model) == {"a.png", "b.jpg", "c.jpeg"}


# -- the source itself --------------------------------------------------------

src = QML.read_text()
body = re.sub(r"//[^\n]*", "", src)

# One MenuRow holds the row metrics, the state layers and the keyboard. Ten
# copies of them is what this replaced, and a new row that reaches for
# DockMenuButton directly starts it over.
assert body.count("component MenuRow: DockMenuButton") == 1, "MenuRow is the row"
assert body.count("DockMenuButton {") == 1, "a row went back to raw DockMenuButton"
assert body.count("MenuRow {") >= 9, "rows went missing"

# The keyboard: RippleButton fires from its own MouseArea, so StrongFocus and
# the three activation keys have to be declared, once, on the shared row.
for prop in ("focusPolicy: Qt.StrongFocus", "Keys.onUpPressed", "Keys.onDownPressed",
             "Keys.onReturnPressed", "Keys.onEnterPressed", "Keys.onSpacePressed"):
    assert body.count(prop) == 1, f"{prop} must be declared exactly once, on MenuRow"

# Motion comes from the arrowPopup composite, like every other surface that
# grows out of what opened it. A number typed beside them is the drift.
assert not re.search(r"duration:\s*\d", body), "a literal duration came back"
for token in ("arrowPopupScale", "arrowPopupOvershoot", "arrowPopupScaleDuration",
              "arrowPopupSettle", "arrowPopupCloseDuration", "arrowPopupFadeDuration",
              "arrowPopupFadeHold"):
    assert token in body, f"{token} is no longer used"
# Enter and exit are asymmetric: decelerating in, accelerating out (DESIGN 4).
assert "emphasizedDecel" in body and "emphasizedAccel" in body

print("ok: desktop menu pivots on the nearest corner, hides a strip of one, "
      "and keeps its rows and motion in one place")
