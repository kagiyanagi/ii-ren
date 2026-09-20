#!/usr/bin/env python3
"""The bar popup's open/close pivot lands on the corner nearest the bar item.

DESIGN.md 2.6 / ArrowPopup.setPivotForOpenCloseAnimation(): a popup grows out of
whatever opened it. In `modules/ii/bar/StyledPopup.qml` that is arithmetic, not a
constant -- the surface is centred on the bar item until a screen edge pushes it
off, and the pivot has to travel the other way by exactly as much. No still frame
proves it, and no one can drive every bar orientation and every item position by
hand, so the expressions are lifted out of the QML and exercised here.

The one thing that must never happen is a pivot outside the surface: the popup
then grows out of thin air beside itself.

    python3 tools/check-popup-pivot.py
"""

ELEVATION = 10  # Appearance.sizes.elevationMargin
BAR = 40  # Appearance.sizes.barHeight / verticalBarWidth


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


class Popup:
    """One StyledPopup instance, as the QML computes it."""

    def __init__(self, vertical, bottom, screen_w, screen_h,
                 content_w, content_h, item_x, item_y, item_w, item_h,
                 bg_margin=0):
        self.vertical, self.bottom = vertical, bottom
        self.screen_w, self.screen_h = screen_w, screen_h
        self.item_x, self.item_y = item_x, item_y
        self.item_w, self.item_h = item_w, item_h

        # popupBackground: content plus its 10px inner margin, no layout scale.
        self.bg_w = content_w + 20
        self.bg_h = content_h + 20
        self.win_w = self.bg_w + ELEVATION * 2 + bg_margin
        self.win_h = self.bg_h + ELEVATION * 2 + bg_margin

    # -- window placement (margins block) -------------------------------------
    @property
    def ideal_left(self):
        return self.item_x + (self.item_w - self.win_w) / 2

    @property
    def ideal_top(self):
        return self.item_y + (self.item_h - self.win_h) / 2

    @property
    def left_margin(self):
        return clamp(self.ideal_left, 0, self.screen_w - self.win_w)

    @property
    def top_margin(self):
        return clamp(self.ideal_top, 0, self.screen_h - self.win_h)

    # -- popupBackground inside animContainer (which fills the window) --------
    @property
    def bg_x(self):
        if self.vertical:
            return self.win_w - ELEVATION - self.bg_w if self.bottom else ELEVATION
        return (self.win_w - self.bg_w) / 2  # horizontalCenter

    @property
    def bg_y(self):
        if self.vertical:
            return (self.win_h - self.bg_h) / 2  # verticalCenter
        return self.win_h - ELEVATION - self.bg_h if self.bottom else ELEVATION

    # -- the pivot ------------------------------------------------------------
    @property
    def pivot_x(self):
        if self.vertical:
            return self.bg_x + self.bg_w if self.bottom else self.bg_x
        wanted = self.ideal_left + self.win_w / 2 - self.left_margin
        return clamp(wanted, self.bg_x, self.bg_x + self.bg_w)

    @property
    def pivot_y(self):
        if not self.vertical:
            return self.bg_y + self.bg_h if self.bottom else self.bg_y
        wanted = self.ideal_top + self.win_h / 2 - self.top_margin
        return clamp(wanted, self.bg_y, self.bg_y + self.bg_h)


def top_bar(item_x, screen_w=1920, content_w=380):
    return Popup(vertical=False, bottom=False, screen_w=screen_w, screen_h=1080,
                 content_w=content_w, content_h=300,
                 item_x=item_x, item_y=0, item_w=32, item_h=BAR)


def bottom_bar(item_x, screen_w=1920):
    p = top_bar(item_x, screen_w)
    p.bottom = True
    return p


def left_bar(item_y, screen_h=1080):
    return Popup(vertical=True, bottom=False,
                 screen_w=1920, screen_h=screen_h, content_w=380, content_h=300,
                 item_x=0, item_y=item_y, item_w=BAR, item_h=32)


def right_bar(item_y, screen_h=1080):
    p = left_bar(item_y, screen_h)
    p.bottom = True
    return p


# --- the pivot is on the bar's edge of the surface ---------------------------

p = top_bar(item_x=960)
assert p.pivot_y == p.bg_y, "top bar: the surface must grow down from its top edge"

p = bottom_bar(item_x=960)
assert p.pivot_y == p.bg_y + p.bg_h, "bottom bar: the surface must grow up from its bottom edge"

p = left_bar(item_y=540)
assert p.pivot_x == p.bg_x, "left bar: the surface must grow right from its left edge"

p = right_bar(item_y=540)
assert p.pivot_x == p.bg_x + p.bg_w, "right bar: the surface must grow left from its right edge"


# --- the other axis follows the bar item -------------------------------------

# Centre of the screen: nothing is clamped, so the pivot is the surface centre.
p = top_bar(item_x=960)
assert abs(p.pivot_x - (p.bg_x + p.bg_w / 2)) < 1e-9, \
    "an unclamped popup grows from the centre of its own top edge"

# Hard against the right edge (a tray icon): the window cannot centre on it any
# more, so the pivot has to walk right by the amount the window was pushed left.
p = top_bar(item_x=1920 - 32)
assert p.left_margin == p.screen_w - p.win_w, "the window should be clamped at the right edge"
assert p.pivot_x > p.bg_x + p.bg_w * 0.9, \
    "a tray popup grows from its top-RIGHT corner, not its centre"

# Hard against the left edge (the workspaces end of the bar).
p = top_bar(item_x=0)
assert p.left_margin == 0, "the window should be clamped at the left edge"
assert p.pivot_x < p.bg_x + p.bg_w * 0.1, \
    "a popup at the left end grows from its top-LEFT corner"

# Same story on a vertical bar, along y.
p = right_bar(item_y=1080 - 32)
assert p.pivot_y > p.bg_y + p.bg_h * 0.9, "a bottom tray icon on a right bar grows from its bottom-right"
p = left_bar(item_y=0)
assert p.pivot_y < p.bg_y + p.bg_h * 0.1, "a top icon on a left bar grows from its top-left"


# --- the pivot never leaves the surface --------------------------------------
# The clamp is the whole point: without it, an item near an edge puts the origin
# outside the card and the popup appears to erupt from a point beside itself.

for make in (top_bar, bottom_bar):
    for screen_w in (1024, 1366, 1920, 3840):
        for item_x in range(-64, screen_w + 64, 17):
            p = make(item_x, screen_w)
            assert p.bg_x <= p.pivot_x <= p.bg_x + p.bg_w, (make.__name__, screen_w, item_x)
            assert p.pivot_y in (p.bg_y, p.bg_y + p.bg_h)

for make in (left_bar, right_bar):
    for screen_h in (720, 1080, 1440):
        for item_y in range(-64, screen_h + 64, 13):
            p = make(item_y, screen_h)
            assert p.bg_y <= p.pivot_y <= p.bg_y + p.bg_h, (make.__name__, screen_h, item_y)
            assert p.pivot_x in (p.bg_x, p.bg_x + p.bg_w)


# --- a popup wider than the screen still lands a finite number ---------------
# layoutScale caps a popup at 90% of the screen, but a small screen plus a user
# popupScaleMultiplier can still overflow; clamp(lo > hi) must not produce NaN.

p = top_bar(item_x=500, screen_w=800, content_w=1200)
assert p.win_w > p.screen_w, "this case is only interesting when the popup overflows"
assert p.pivot_x == p.pivot_x, "pivot must not be NaN when the popup is wider than the screen"
assert p.bg_x <= p.pivot_x <= p.bg_x + p.bg_w, "an overflowing popup still pivots inside itself"


# --- customPosition popups pick their corner from the anchor flags -----------
# (SysTrayMenu and the record indicator set anchors by hand rather than tracking
# a bar item; the QML reads anchorLeft/Right/Top/Bottom and centres on an axis
# that names neither.)

def custom_pivot(bg_x, bg_w, anchor_left, anchor_right):
    if anchor_left:
        return bg_x
    if anchor_right:
        return bg_x + bg_w
    return bg_x + bg_w / 2


assert custom_pivot(10, 400, True, False) == 10
assert custom_pivot(10, 400, False, True) == 410
assert custom_pivot(10, 400, False, False) == 210, "neither flag set: centre of that axis"

print("check-popup-pivot: ok")
