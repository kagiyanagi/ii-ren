#!/usr/bin/env python3
"""Regression checks for waffle-notificationPopup audit.

Verifies:
1. Pragma ComponentBehavior: Bound declaration.
2. Exit animation & layer surface latch:
   - visible does not bind directly to Notifications.popupList or hasPopups.
   - visible gates on !GlobalStates.screenLocked.
   - mapped property latch exists and is set true/false.
   - exitGrace Timer covers the dismissal transition (Appearance.animation.elementMoveExit.duration).
   - exitGrace is a one-shot Timer without repeats or competing running bindings.
3. Screen configuration:
   - Respects Config.options.notifications.monitor.
   - Falls back to focused monitor.
4. Keyboard focus:
   - Explicit WlrKeyboardFocus.None prevents stealing keyboard focus.
5. Bar position & anchoring:
   - Config.options.waffles.bar.bottom switches bottom vs top anchoring.
   - No conflicting width property when both left and right anchors are set.
6. Mask region:
   - popupBounds clamps to content height and reports 0 when empty.
   - popupBounds carries no transform.
7. Published height (GlobalStates.notificationPopupHeight):
   - Published via Binding.
   - Returns 0 when popups are bottom-anchored or empty.
   - Returns clamped stack height when top-anchored.
8. 4dp grid metrics:
   - gutter, spacing, and implicitWidth are all multiples of 4dp.
   - Card width aligns to 360dp Waffle standard.
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
POPUP_PATH = ROOT / "modules/waffle/notificationPopup/WaffleNotificationPopup.qml"
DISMISS_PATH = ROOT / "modules/waffle/notificationCenter/WNotificationDismissAnim.qml"
APPEARANCE_PATH = ROOT / "modules/common/Appearance.qml"


def one(src: str, pattern: str, what: str) -> str:
    m = re.search(pattern, src, re.M)
    assert m, f"{what} no longer matches {pattern!r} -- check is stale"
    return m.group(1).strip()


def check_popup_exists() -> str:
    assert POPUP_PATH.is_file(), f"File not found: {POPUP_PATH}"
    return POPUP_PATH.read_text(encoding="utf-8")


def check_bound_pragma(src: str):
    assert "pragma ComponentBehavior: Bound" in src, (
        "WaffleNotificationPopup.qml missing 'pragma ComponentBehavior: Bound'"
    )


def check_exit_and_latch(src: str):
    visible = one(src, r"^\s*visible:\s*(.+)$", "the window's visible binding")
    assert "popupList" not in visible and "hasPopups" not in visible, (
        f"visible directly reads popup list -- surface unmaps mid-exit: {visible}"
    )
    assert "screenLocked" in visible, (
        f"visible missing screenLocked guard: {visible}"
    )

    latch = one(visible, r"root\.(\w+)\s*&&", "the latch visible reads")
    assert re.search(rf"^\s*property\s+bool\s+{latch}:\s*false$", src, re.M), (
        f"'{latch}' is not a plain boolean latch property"
    )
    assert re.search(rf"{latch}\s*=\s*true", src) and re.search(rf"{latch}\s*=\s*false", src), (
        f"'{latch}' must be explicitly set true and false"
    )

    grace_token = one(src, r"interval:\s*Appearance\.animation\.(\w+)\.duration", "exitGrace interval")
    dismiss_src = DISMISS_PATH.read_text(encoding="utf-8")
    dismiss_token = one(dismiss_src, r"duration:\s*Appearance\.animation\.(\w+)\.duration", "dismiss animation duration")
    assert grace_token == dismiss_token, (
        f"exitGrace uses {grace_token} but dismiss animation uses {dismiss_token} -- duration mismatch"
    )

    timer_block = one(src, r"(Timer\s*\{[\s\S]+?id:\s*exitGrace[\s\S]+?\})", "exitGrace Timer block")
    assert "repeat:" not in timer_block, "exitGrace Timer must be a one-shot (no repeat)"
    assert "running:" not in timer_block, "exitGrace Timer must not have a running binding (causes ordering race)"


def check_screen_and_focus(src: str):
    assert "Config.options.notifications.monitor" in src, (
        "WaffleNotificationPopup.qml does not check Config.options.notifications.monitor"
    )
    assert "Hyprland.focusedMonitor?.name" in src, (
        "WaffleNotificationPopup.qml does not fallback to focused monitor"
    )
    assert re.search(r"WlrLayershell\.keyboardFocus:\s*WlrKeyboardFocus\.None", src), (
        "WaffleNotificationPopup.qml does not explicitly set keyboardFocus to None"
    )


def check_anchors_and_bar_position(src: str):
    assert "Config.options.waffles.bar.bottom" in src, (
        "WaffleNotificationPopup.qml does not inspect Config.options.waffles.bar.bottom"
    )
    listview_block = one(src, r"(WListView\s*\{[\s\S]+?id:\s*listview[\s\S]+?model:\s*ScriptModel)", "listview block")
    assert re.search(r"anchors\s*\{[\s\S]+?right:\s*parent\.right[\s\S]+?left:\s*parent\.left", listview_block), (
        "listview must anchor to both right and left edges of parent"
    )
    assert not re.search(r"^\s*width:\s*", listview_block, re.M), (
        "listview specifies width while anchoring both left and right -- triggers QML warning"
    )
    assert "root.barAtBottom ? parent.bottom : undefined" in listview_block, (
        "listview does not anchor bottom when bar is at bottom"
    )
    assert "!root.barAtBottom ? parent.top : undefined" in listview_block, (
        "listview does not anchor top when bar is at top"
    )


def check_mask_bounds(src: str):
    masked = one(src, r"mask:\s*Region\s*\{\s*item:\s*(\w+)", "the window mask item")
    box = one(src, rf"(Item\s*\{{\s*id:\s*{masked}[\s\S]+?\}})", f"the {masked} item")
    assert "scale" not in box and "transform" not in box, (
        f"{masked} carries a transform, which breaks Region mask recalculation"
    )
    assert "root.hasPopups" in box and "listview.count > 0" in box, (
        f"{masked} height does not gate on hasPopups and count > 0 (swallows clicks when empty)"
    )


def check_published_height(src: str):
    binding_block = one(src, r'(Binding\s*\{[\s\S]+?property:\s*"notificationPopupHeight"[\s\S]+?\})', "height binding")
    val_expr = one(binding_block, r"value:\s*([\s\S]+?)\n\s*\}", "published height value")

    def calc(visible: bool, bar_at_bottom: bool, count: int, content_height: float, y: float, height: float) -> float:
        clean_expr = " ".join(val_expr.split())
        js = (
            clean_expr.replace("root.visible", str(visible))
                      .replace("!root.barAtBottom", str(not bar_at_bottom))
                      .replace("root.barAtBottom", str(bar_at_bottom))
                      .replace("listview.count", str(count))
                      .replace("listview.contentHeight", str(content_height))
                      .replace("listview.topMargin", "12")
                      .replace("listview.bottomMargin", "12")
                      .replace("listview.height", str(height))
                      .replace("listview.y", str(y))
                      .replace("Math.min", "min")
                      .replace("&&", " and ")
                      .replace("||", " or ")
                      .replace("true", "True")
                      .replace("false", "False")
        )
        cond, rest = js.split("?", 1)
        then, alt = rest.split(":", 1)
        return eval(f"({then}) if ({cond}) else ({alt})", {"min": min})  # noqa: S307

    # When bottom-anchored (standard waffle bar at bottom), must publish 0 so top-right readers do not inset
    assert calc(True, True, 2, 200, 800, 1000) == 0, (
        "bottom-anchored popups must publish 0 for top-right notificationPopupHeight"
    )
    # When hidden or empty, must publish 0
    assert calc(False, False, 2, 200, 12, 1000) == 0, "hidden popups must publish 0"
    assert calc(True, False, 0, 0, 12, 1000) == 0, "empty popup list must publish 0"
    # When top-anchored and visible, must publish y + clamped content height
    top_published = calc(True, False, 1, 150, 12, 1000)
    assert top_published == 12 + 150 + 12 + 12, f"unexpected top published height: {top_published}"


def check_grid_metrics(src: str):
    gutter = float(one(src, r"readonly property real gutter:\s*([\d.]+)", "gutter token"))
    assert gutter % 4 == 0, f"gutter {gutter} is not on 4dp grid"

    width_match = one(src, r"implicitWidth:\s*(\d+)", "listview implicitWidth")
    implicit_width = int(width_match)
    assert implicit_width % 4 == 0, f"implicitWidth {implicit_width} is not on 4dp grid"

    spacing = int(one(src, r"spacing:\s*(\d+)", "listview spacing"))
    assert spacing % 4 == 0, f"spacing {spacing} is not on 4dp grid"

    # 384dp width - 12dp leftMargin - 12dp rightMargin = 360dp card width
    card_width = implicit_width - int(gutter) * 2
    assert card_width == 360, f"effective card width {card_width} does not match 360dp waffle standard"


def main():
    src = check_popup_exists()
    check_bound_pragma(src)
    check_exit_and_latch(src)
    check_screen_and_focus(src)
    check_anchors_and_bar_position(src)
    check_mask_bounds(src)
    check_published_height(src)
    check_grid_metrics(src)
    print("ok  waffle-notificationPopup regression checks passed")


if __name__ == "__main__":
    main()
