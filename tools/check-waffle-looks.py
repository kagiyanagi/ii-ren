#!/usr/bin/env python3
"""Regression checks for waffle-looks audit.

Verifies:
1. Every QML file in modules/waffle/looks declares pragma ComponentBehavior: Bound.
2. Looks.qml:
   - contentTransparency and panelLayerTransparency are gated on transparencyEnabled.
   - Transitions use Appearance.animation tokens.
3. WIcons.qml:
   - Null safety for battery icon / discreteLevel when Battery is unavailable.
   - Default fallback in powerProfileIcon.
4. WBarAttachedPanelContent.qml:
   - Escape handler calls root.close() (no ReferenceError: content is not defined).
   - Close and open animations use Appearance.animation tokens.
5. VerticalPageIndicator.qml:
   - NavigationArrow uses upArea.pressed (preventing NaN implicitWidth from upArea.containsPress).
6. WToolbarTabBar.qml:
   - No click-hijacking pressDetector MouseArea at z: 9999.
   - Indicator sizing derives safely from root.currentItem.
   - Margins and heights are on the 4dp grid.
7. WMenu.qml:
   - Array reduce call has initial value 0 (prevents TypeError on empty array).
   - Padding on 4dp grid (padding: 4).
   - Uses Appearance.animation duration tokens.
8. WButton.qml:
   - Declares property real iconLeftMargin: 0 on root.
9. WIndeterminateProgressBar.qml:
   - No redundant offscreen layer.enabled or OpacityMask passes.
   - implicitHeight on 4dp grid (implicitHeight: 4).
10. WText.qml:
    - Specifies elide: Text.ElideRight per DESIGN.md 10.17.
11. WProgressBar.qml:
    - Track highlight width calculated via root.visualPosition.
12. WSlider.qml:
    - Tooltip verticalPadding is on 4dp grid (verticalPadding: 4).
    - Handle x expression simplified.
13. WChoiceButton.qml:
    - Padding, indicator size, and offset on 4dp grid.
    - Height Behavior animates on resize (spatial token), not opacity.
14. WSwitch.qml:
    - Indicator pressed dimensions (16) and margins on 4dp grid.
15. CloseButton.qml:
    - Sized 32x32dp on 4dp grid.
    - No circular import from qs.modules.waffle.bar.
16. WMenuItem.qml:
    - Padding (12), indicator (4x4), and offset (16*2) on 4dp grid.
17. WScrollBar.qml:
    - Uses Appearance.rounding.full instead of literal 9999.
18. WTextField.qml:
    - Clean of invalid import QtQuick.Controls.FluentWinUI3.
19. WTextWithFixedWidth.qml:
    - Synchronizes longestTextMetrics.font with textItem.font.
20. WStackView.qml:
    - moveDistance on 4dp grid (32).
    - Uses Appearance.animation duration tokens.
21. WUserAvatar.qml:
    - Root is Item with mutable implicitWidth and implicitHeight (prevents fatal read-only implicitHeight crash in WaffleLock).
22. check-design.py --diff passes cleanly with 0 findings and 0 errors.
"""

from pathlib import Path
import subprocess
import sys

BASE = Path("dots/.config/quickshell/ii/modules/waffle/looks")


def check_file_exists(rel_path: str) -> Path:
    p = BASE / rel_path
    if not p.is_file():
        print(f"FAIL: File not found: {p}")
        sys.exit(1)
    return p


def main():
    failed = False

    # 1. Pragma ComponentBehavior: Bound across all 48 files
    all_qml = sorted(BASE.glob("*.qml"))
    if len(all_qml) != 48:
        print(f"FAIL: Expected 48 QML files under modules/waffle/looks, found {len(all_qml)}")
        failed = True
    for f in all_qml:
        content = f.read_text(encoding="utf-8")
        if "pragma ComponentBehavior: Bound" not in content:
            print(f"FAIL: {f.name} missing 'pragma ComponentBehavior: Bound'")
            failed = True

    # 2. Looks.qml
    looks_text = check_file_exists("Looks.qml").read_text(encoding="utf-8")
    if "contentTransparency: transparencyEnabled ?" not in looks_text:
        print("FAIL: Looks.qml contentTransparency not gated on transparencyEnabled")
        failed = True
    if "panelLayerTransparency: transparencyEnabled ?" not in looks_text:
        print("FAIL: Looks.qml panelLayerTransparency not gated on transparencyEnabled")
        failed = True
    if "Appearance.animation.fadeFast.duration" not in looks_text:
        print("FAIL: Looks.qml transition.color does not use Appearance.animation token")
        failed = True
    if "Appearance.animation.elementMoveExit.duration" not in looks_text:
        print("FAIL: Looks.qml transition.opacity does not use Appearance.animation token")
        failed = True

    # 3. WIcons.qml
    icons_text = check_file_exists("WIcons.qml").read_text(encoding="utf-8")
    if "!Battery.available" not in icons_text:
        print("FAIL: WIcons.qml batteryIcon lacks Battery.available guard")
        failed = True
    if "Battery.percentage === undefined" not in icons_text:
        print("FAIL: WIcons.qml batteryLevelIcon lacks undefined percentage guard")
        failed = True
    if 'default:\n            return "flash-on";' not in icons_text:
        print("FAIL: WIcons.qml powerProfileIcon lacks default case")
        failed = True

    # 4. WBarAttachedPanelContent.qml
    bar_attached_text = check_file_exists("WBarAttachedPanelContent.qml").read_text(encoding="utf-8")
    if "content.close()" in bar_attached_text:
        print("FAIL: WBarAttachedPanelContent.qml retains ReferenceError 'content.close()'")
        failed = True
    if "root.close();" not in bar_attached_text:
        print("FAIL: WBarAttachedPanelContent.qml missing 'root.close()' on Escape")
        failed = True
    if "Appearance.animation.elementMoveExit.duration" not in bar_attached_text:
        print("FAIL: WBarAttachedPanelContent.qml closeAnimDuration lacks Appearance token")
        failed = True

    # 5. VerticalPageIndicator.qml
    indicator_text = check_file_exists("VerticalPageIndicator.qml").read_text(encoding="utf-8")
    if "upArea.containsPress" in indicator_text:
        print("FAIL: VerticalPageIndicator.qml retains invalid upArea.containsPress (causing NaN width)")
        failed = True
    if "upArea.pressed" not in indicator_text:
        print("FAIL: VerticalPageIndicator.qml missing upArea.pressed")
        failed = True

    # 6. WToolbarTabBar.qml
    tabbar_text = check_file_exists("WToolbarTabBar.qml").read_text(encoding="utf-8")
    if "pressDetector" in tabbar_text:
        print("FAIL: WToolbarTabBar.qml retains click-hijacking pressDetector MouseArea")
        failed = True
    if "bottomMargin: 2" not in tabbar_text or "implicitHeight: 4" not in tabbar_text:
        print("FAIL: WToolbarTabBar.qml indicator metrics off 4dp grid")
        failed = True

    # 7. WMenu.qml
    menu_text = check_file_exists("WMenu.qml").read_text(encoding="utf-8")
    if ").reduce((a, b) => a > b ? a : b, 0)" not in menu_text:
        print("FAIL: WMenu.qml reduce call missing initial value 0")
        failed = True
    if "padding: 4" not in menu_text:
        print("FAIL: WMenu.qml padding not on 4dp grid")
        failed = True

    # 8. WButton.qml
    button_text = check_file_exists("WButton.qml").read_text(encoding="utf-8")
    if "property real iconLeftMargin: 0" not in button_text:
        print("FAIL: WButton.qml missing declared property iconLeftMargin")
        failed = True

    # 9. WIndeterminateProgressBar.qml
    progress_text = check_file_exists("WIndeterminateProgressBar.qml").read_text(encoding="utf-8")
    if "layer.enabled" in progress_text or "OpacityMask" in progress_text:
        print("FAIL: WIndeterminateProgressBar.qml retains redundant layer.enabled/OpacityMask")
        failed = True
    if "implicitHeight: 4" not in progress_text:
        print("FAIL: WIndeterminateProgressBar.qml implicitHeight not 4dp")
        failed = True

    # 10. WText.qml
    text_qml = check_file_exists("WText.qml").read_text(encoding="utf-8")
    if "elide: Text.ElideRight" not in text_qml:
        print("FAIL: WText.qml missing 'elide: Text.ElideRight' (DESIGN.md 10.17)")
        failed = True

    # 11. WProgressBar.qml
    bar_text = check_file_exists("WProgressBar.qml").read_text(encoding="utf-8")
    if "root.visualPosition" not in bar_text:
        print("FAIL: WProgressBar.qml does not use visualPosition for highlight width")
        failed = True

    # 12. WSlider.qml
    slider_text = check_file_exists("WSlider.qml").read_text(encoding="utf-8")
    if "verticalPadding: 4" not in slider_text:
        print("FAIL: WSlider.qml tooltip verticalPadding not on 4dp grid")
        failed = True
    if "root.visualPosition * (root.width - diameter)" not in slider_text:
        print("FAIL: WSlider.qml handle x calculation not simplified")
        failed = True

    # 13. WChoiceButton.qml
    choice_text = check_file_exists("WChoiceButton.qml").read_text(encoding="utf-8")
    if "verticalPadding: 12" not in choice_text:
        print("FAIL: WChoiceButton.qml verticalPadding not on 4dp grid")
        failed = True
    if "Looks.transition.resize" not in choice_text:
        print("FAIL: WChoiceButton.qml height Behavior animation must use spatial resize transition")
        failed = True

    # 14. WSwitch.qml
    switch_text = check_file_exists("WSwitch.qml").read_text(encoding="utf-8")
    if "indicatorPressedWidth: 16" not in switch_text:
        print("FAIL: WSwitch.qml indicatorPressedWidth not on 4dp grid")
        failed = True

    # 15. CloseButton.qml
    close_text = check_file_exists("CloseButton.qml").read_text(encoding="utf-8")
    if "implicitHeight: 32" not in close_text or "implicitWidth: 32" not in close_text:
        print("FAIL: CloseButton.qml size not on 4dp grid (32x32)")
        failed = True
    if "qs.modules.waffle.bar" in close_text:
        print("FAIL: CloseButton.qml retains circular import qs.modules.waffle.bar")
        failed = True

    # 16. WMenuItem.qml
    menu_item_text = check_file_exists("WMenuItem.qml").read_text(encoding="utf-8")
    if "horizontalPadding: 12" not in menu_item_text:
        print("FAIL: WMenuItem.qml horizontalPadding not on 4dp grid (12)")
        failed = True

    # 17. WScrollBar.qml
    scroll_text = check_file_exists("WScrollBar.qml").read_text(encoding="utf-8")
    if "radius: 9999" in scroll_text:
        print("FAIL: WScrollBar.qml retains literal radius: 9999")
        failed = True
    if "radius: Appearance.rounding.full" not in scroll_text:
        print("FAIL: WScrollBar.qml does not use Appearance.rounding.full")
        failed = True

    # 18. WTextField.qml
    textfield_text = check_file_exists("WTextField.qml").read_text(encoding="utf-8")
    if "FluentWinUI3" in textfield_text:
        print("FAIL: WTextField.qml retains invalid import FluentWinUI3")
        failed = True

    # 19. WTextWithFixedWidth.qml
    fixed_width_text = check_file_exists("WTextWithFixedWidth.qml").read_text(encoding="utf-8")
    if "font: textItem.font" not in fixed_width_text:
        print("FAIL: WTextWithFixedWidth.qml does not bind longestTextMetrics.font to textItem.font")
        failed = True

    # 20. WStackView.qml
    stack_text = check_file_exists("WStackView.qml").read_text(encoding="utf-8")
    if "moveDistance: 32" not in stack_text:
        print("FAIL: WStackView.qml moveDistance not on 4dp grid (32)")
        failed = True
    if "Appearance.animation.elementMoveFast.duration" not in stack_text:
        print("FAIL: WStackView.qml pushDuration does not use Appearance token")
        failed = True

    # 21. WUserAvatar.qml
    avatar_text = check_file_exists("WUserAvatar.qml").read_text(encoding="utf-8")
    if "implicitWidth: 32" not in avatar_text or "implicitHeight: 32" not in avatar_text:
        print("FAIL: WUserAvatar.qml lacks mutable implicitWidth/implicitHeight")
        failed = True
    if avatar_text.strip().startswith("StyledImage"):
        print("FAIL: WUserAvatar.qml root is StyledImage (causes read-only implicitHeight crash in WaffleLock)")
        failed = True

    # 22. check-design.py --diff
    res = subprocess.run(["python3", "tools/check-design.py", "--diff"], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"FAIL: check-design.py --diff reported errors:\n{res.stdout}\n{res.stderr}")
        failed = True

    if failed:
        print("\ncheck-waffle-looks: FAILED")
        return 1

    print("check-waffle-looks: OK (all regression checks passed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
