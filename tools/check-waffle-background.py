#!/usr/bin/env python3
"""Regression checks for waffle-background audit.

Verifies:
1. WaffleBackground.qml declares pragma ComponentBehavior: Bound.
2. No unused or inappropriate ii-specific imports (e.g. qs.modules.ii.background.widgets).
3. Fullscreen window detection implemented and null-safe (monitor guard + Config.options.background.hideWhenFullscreen).
4. Video wallpaper support: detects video files, hides image surface so mpvpaper is visible.
5. Workplace / network safety guard (Config.options.workSafety).
6. Uses TransitionImage for smooth animated wallpaper transitions.
7. Desktop right-click context menu (desktopMenuArea -> GlobalStates.desktopMenuOpen).
8. Desktop drag-and-drop support for wallpaper switching and DropShelf staging.
9. Drop hint adheres to Fluent/Looks design system (Looks tokens, FluentIcon, WText).
10. WaffleFamily.qml gates WaffleBackground on Config.options.background.enable.
11. WaffleFamily.qml includes DesktopMenu and DropShelfPanel fallbacks.
"""

from pathlib import Path
import re
import sys

SHELL_DIR = Path("dots/.config/quickshell/ii")
BG_PATH = SHELL_DIR / "modules/waffle/background/WaffleBackground.qml"
FAMILY_PATH = SHELL_DIR / "panelFamilies/WaffleFamily.qml"

def main():
    failed = False

    if not BG_PATH.is_file():
        print(f"FAIL: File not found: {BG_PATH}")
        return 1

    bg_text = BG_PATH.read_text(encoding="utf-8")

    # 1. Pragma ComponentBehavior: Bound
    if "pragma ComponentBehavior: Bound" not in bg_text:
        print("FAIL: WaffleBackground.qml missing 'pragma ComponentBehavior: Bound'")
        failed = True

    # 2. No unused or inappropriate imports
    unwanted_imports = [
        "qs.modules.ii.background.widgets",
        "qs.modules.common.widgets.widgetCanvas",
        "Qt5Compat.GraphicalEffects",
        "Quickshell.Io",
    ]
    for imp in unwanted_imports:
        if imp in bg_text:
            print(f"FAIL: WaffleBackground.qml contains unwanted import: {imp}")
            failed = True

    # 3. Fullscreen window detection & null safety
    if "hideWhenFullscreen" not in bg_text:
        print("FAIL: WaffleBackground.qml missing hideWhenFullscreen logic")
        failed = True
    if "panelRoot.monitor" not in bg_text or "monitor &&" not in bg_text:
        print("FAIL: WaffleBackground.qml monitor filtering lacks null-guard")
        failed = True

    # 4. Video wallpaper support
    if "wallpaperIsVideo" not in bg_text or "isVideoFile" not in bg_text:
        print("FAIL: WaffleBackground.qml missing video wallpaper detection")
        failed = True
    if "!panelRoot.wallpaperIsVideo" not in bg_text:
        print("FAIL: WaffleBackground.qml does not hide image when wallpaper is video")
        failed = True

    # 5. Workplace / network safety guard
    if "workSafety" not in bg_text or "wallpaperSafetyTriggered" not in bg_text:
        print("FAIL: WaffleBackground.qml missing workSafety wallpaper guard")
        failed = True

    # 6. Uses TransitionImage
    if "TransitionImage" not in bg_text:
        print("FAIL: WaffleBackground.qml does not use TransitionImage")
        failed = True

    # 7. Desktop right-click context menu
    if "rightClickMenu" not in bg_text or "desktopMenuOpen" not in bg_text:
        print("FAIL: WaffleBackground.qml missing desktop right-click context menu")
        failed = True

    # 8. Drag and drop for wallpaper and drop shelf
    if "dropToSetWallpaper" not in bg_text or "DropShelf" not in bg_text:
        print("FAIL: WaffleBackground.qml missing wallpaper/shelf DropArea handling")
        failed = True

    # 9. Looks design tokens and components in dropHint
    if "Looks.colors" not in bg_text or "Looks.radius" not in bg_text:
        print("FAIL: WaffleBackground.qml dropHint not styled with Looks tokens")
        failed = True
    if "FluentIcon" not in bg_text or "WText" not in bg_text:
        print("FAIL: WaffleBackground.qml dropHint missing FluentIcon or WText")
        failed = True

    # 10 & 11. WaffleFamily.qml checks
    if not FAMILY_PATH.is_file():
        print(f"FAIL: File not found: {FAMILY_PATH}")
        return 1

    fam_text = FAMILY_PATH.read_text(encoding="utf-8")
    if not re.search(r"extraCondition:\s*Config\.options\.background\.enable;\s*component:\s*WaffleBackground", fam_text):
        print("FAIL: WaffleFamily.qml does not gate WaffleBackground on Config.options.background.enable")
        failed = True

    if "DesktopMenu" not in fam_text:
        print("FAIL: WaffleFamily.qml missing DesktopMenu fallback")
        failed = True
    if "DropShelfPanel" not in fam_text:
        print("FAIL: WaffleFamily.qml missing DropShelfPanel fallback")
        failed = True

    if failed:
        print("Some checks failed!")
        return 1

    print("ok: waffle-background regression suite passed cleanly")
    return 0

if __name__ == "__main__":
    sys.exit(main())
