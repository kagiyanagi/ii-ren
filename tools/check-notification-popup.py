#!/usr/bin/env python3
"""Assert the notification stack finishes leaving, and stays out of its neighbours' way.

`NotificationPopup` is 120 lines of placement and lifetime -- every control on it
belongs to the card kit. Both things it owns fail silently.

**The exit.** `visible: Notifications.popupList.length > 0` unmaps the layer surface
in the same frame the model empties, so `NotificationListView`'s `remove` transition
-- a slide out to `width + removeOvershoot` plus a fade, on `elementMoveExit` -- plays
to a surface nobody can see. The card still disappears, which is exactly what it is
meant to do, so there is no symptom to notice and no still frame that shows it. And
because one notification at a time is the ordinary case, the cut-off exit was not an
edge state: it was every notification in the shell. The window now outlives the list
by a grace timer, and this asserts the grace is at least as long as the transition it
is there to cover, with both durations read out of the source rather than transcribed.

The latch is asserted too, not just the timer. `visible: hasPopups ||
exitGrace.running` reads like the same thing and is not: that binding and the handler
that starts the timer are two connections to one change signal, and nothing fixes
which runs first, so the surface may unmap for a frame before the grace begins (2.9).
It is the obvious "simplification" for a later session to make.

**The published height.** `GlobalStates.notificationPopupHeight` is read by three
surfaces that share this corner -- the clipboard toast, the pairing card and the
screenshot preview -- and every one of them treats `<= 0` as "nothing there". The
value is `listview.y + contentHeight`, so an empty stack in a still-mapped window
published the top margin on its own and pushed all three down by a gutter for
nothing. Swept here against an empty stack, one card, and a stack taller than the
screen, which is the case the clamp exists for.

Run: python3 tools/check-notification-popup.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
POPUP = (ROOT / "modules/ii/notificationPopup/NotificationPopup.qml").read_text()
LISTVIEW = (ROOT / "modules/common/widgets/StyledListView.qml").read_text()
APPEARANCE = (ROOT / "modules/common/Appearance.qml").read_text()

READERS = [
    "modules/ii/clipboardToast/ClipboardToast.qml",
    "modules/ii/fastPair/FastPairPopup.qml",
    "modules/ii/regionSelector/ScreenshotPreviewPopup.qml",
]


def one(src: str, pattern: str, what: str) -> str:
    m = re.search(pattern, src, re.M)
    assert m, f"{what} no longer matches {pattern!r} -- this check is stale"
    return m.group(1).strip()


def spec(name: str) -> dict:
    """An AnimSpec out of Appearance.qml, with its duration resolved."""
    body = one(APPEARANCE, rf"property AnimSpec {name}: AnimSpec \{{\n((?:.+\n)+?)\s*\}}", f"the {name} spec")
    token = one(body, r"duration: root\.animationCurves\.(\w+)", f"{name}'s duration")
    return {
        "duration": float(one(APPEARANCE, rf"property real {token}: ([\d.]+)", token)),
        "alwaysRunToEnd": "alwaysRunToEnd: false" not in body,
    }


# --- the exit: the surface outlives the list ---------------------------------

def check_exit_survives_the_empty_list():
    visible = one(POPUP, r"^\s*visible: (.+)$", "the window's visible binding")

    assert "popupList" not in visible and "hasPopups" not in visible, (
        "visible follows the notification list directly -- the surface unmaps on the frame "
        f"the last popup times out and its remove transition never draws: {visible}"
    )
    assert "screenLocked" in visible, (
        f"visible no longer hides the stack on a locked screen: {visible}"
    )

    latch = one(visible, r"(\w+) &&", "the latch visible reads")
    assert re.search(rf"^\s*property bool {latch}: false$", POPUP, re.M), (
        f"`{latch}` is not a plain latch -- a binding here is the ordering race the latch avoids"
    )
    assert re.search(rf"{latch} = true", POPUP) and re.search(rf"{latch} = false", POPUP), (
        f"`{latch}` is only ever written one way, so the surface maps or unmaps but not both"
    )


def check_the_grace_covers_the_transition():
    """The window must stay mapped for at least as long as the card takes to leave."""
    grace_token = one(POPUP, r"interval: Appearance\.animation\.(\w+)\.duration", "the exit grace interval")
    remove_token = one(
        LISTVIEW,
        r"remove: Transition \{\n(?:.+\n)*?\s*Appearance\?\.animation\.(\w+)\.numberAnimation",
        "StyledListView's remove transition",
    )
    grace, remove = spec(grace_token)["duration"], spec(remove_token)["duration"]
    assert grace >= remove, (
        f"the exit grace is {grace}ms but the remove transition runs {remove}ms "
        f"({grace_token} vs {remove_token}) -- the card is cut off partway out"
    )

    # A grace that never ends is a surface that never unmaps: it must be a one-shot.
    timer = one(POPUP, r"(Timer \{\n(?:.+\n)+?\s*\})", "the exit grace timer")
    assert "repeat" not in timer, "the exit grace repeats -- it is a one-shot, not a heartbeat"
    assert "running:" not in timer, (
        "the exit grace has a `running` binding, which overrides restart()/stop() and "
        "puts the ordering race back"
    )


# --- the dodge: a toggle-driven slide has to reverse -------------------------

def check_the_sidebar_dodge_is_interruptible():
    token = one(
        POPUP,
        r"Behavior on x \{\n\s*animation: Appearance\.animation\.(\w+)\.numberAnimation",
        "the sidebar dodge",
    )
    assert not spec(token)["alwaysRunToEnd"], (
        f"the dodge runs on {token}, which runs to the end (2.7) -- a sidebar closed "
        "mid-slide queues the whole trip out and back instead of turning around"
    )


# --- the mask: the content box, never the full-height list --------------------

def check_the_mask_is_the_content_box():
    masked = one(POPUP, r"mask: Region \{\n\s*item: (\w+)", "the window's mask")
    assert masked != "listview", (
        "the mask is the full-height list -- it is anchored top to bottom, so the whole "
        "right edge of the screen stops being clickable"
    )
    box = one(POPUP, rf"(Item \{{\n\s*id: {masked}\n(?:.+\n)+?\s*\}})", f"the {masked} box")
    assert re.search(r"height: Math\.min\(listview\.contentHeight, listview\.height\)", box), (
        f"{masked} no longer clamps to the content -- an empty or short stack masks the "
        "whole column again"
    )
    # check-mask-regions.py owns the other half: a masked item must carry no transform.
    assert "scale" not in box and "transform" not in box, (
        f"{masked} grew a transform -- the region is computed from the item's rect with its "
        "transform applied and refreshed only on geometry change, so it freezes"
    )


# --- the published height: 0 means nothing is there --------------------------

def check_published_height():
    expr = one(POPUP, r'property: "notificationPopupHeight"\n\s*value: (.+)$', "the published height")

    def published(visible: bool, content: float, view_height: float, y: float) -> float:
        js = (
            expr.replace("root.visible", str(visible))
                .replace("listview.contentHeight", str(content))
                .replace("listview.height", str(view_height))
                .replace("listview.y", str(y))
                .replace("Math.min", "min")
                .replace("&&", "and").replace("||", "or")
                .replace("true", "True").replace("false", "False")
        )
        # `cond ? a : b` reordered into Python's `a if cond else b`.
        cond, rest = js.split("?", 1)
        then, alt = rest.split(":", 1)
        return eval(f"({then}) if ({cond}) else ({alt})", {"min": min})  # noqa: S307

    gutter = float(one(APPEARANCE, r"property real hyprlandGapsOut: ([\d.]+)", "hyprlandGapsOut"))
    assert published(True, 0, 1000, gutter) == 0, (
        "an empty stack in a still-mapped window publishes its top margin -- all three "
        "readers take any positive number as a stack to drop below"
    )
    assert published(False, 300, 1000, gutter) == 0, "a hidden stack still reserves the corner"
    assert published(True, 300, 1000, gutter) == gutter + 300, "one card's stack is mismeasured"
    assert published(True, 4000, 1000, gutter) == gutter + 1000, (
        "a stack taller than the screen is not clamped -- it pushes its neighbours off the display"
    )

    # The readers this contract exists for. If one stops gating on `<= 0`, the zero above
    # buys nothing and this file is measuring something nobody reads.
    for rel in READERS:
        src = (ROOT / rel).read_text()
        assert "GlobalStates.notificationPopupHeight <= 0" in src, (
            f"{rel} no longer treats a non-positive published height as an empty corner"
        )
        assert re.search(r"Math\.max\(0, Math\.min\(GlobalStates\.notificationPopupHeight", src), (
            f"{rel} no longer clamps the inset it takes from the stack"
        )


# --- placement: no invented margins ------------------------------------------

def check_the_gutter_is_a_token():
    assert re.search(r"readonly property real gutter: Appearance\.sizes\.hyprlandGapsOut", POPUP), (
        "the stack's outer spacing is not the shared gutter token -- it sat 4px from the "
        "edge while every other surface in this corner sat at hyprlandGapsOut"
    )
    block = one(POPUP, r"(NotificationListView \{\n(?:.*\n)+?\s*popup: true\n)", "the list")
    for line, what in ((r"^\s*x: (.+)$", "the list's x"), (r"^\s*topMargin: (.+)$", "the list's top margin")):
        placed = one(block, line, what)
        assert "root.gutter" in placed, f"{what} does not use the gutter token: {placed}"
        assert not re.search(r"\b\d+\b", placed), f"{what} still carries a literal number: {placed}"


for check in (
    check_exit_survives_the_empty_list,
    check_the_grace_covers_the_transition,
    check_the_sidebar_dodge_is_interruptible,
    check_the_mask_is_the_content_box,
    check_published_height,
    check_the_gutter_is_a_token,
):
    try:
        check()
    except AssertionError as e:
        print(f"FAIL  {check.__name__}: {e}")
        sys.exit(1)

print("ok  the stack finishes leaving, and publishes 0 when there is nothing in the corner")
