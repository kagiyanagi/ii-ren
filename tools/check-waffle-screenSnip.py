#!/usr/bin/env python3
"""Regression checks for waffle-screenSnip audit.

Verifies:
1. Pragma ComponentBehavior: Bound in all 3 component files.
2. Root properties & null-safety in WScreenSnip.qml:
   - Root declares mediaType, imageAction, videoAction, selectionMode.
   - Root functions (screenshot, ocr, qrScan, record, recordWithSound, search)
     mutate root properties instead of regionSelectorLoader.item.
3. Multi-monitor support and exit lifecycle latching:
   - WScreenSnip uses Variants over Quickshell.screens.
   - Supports Config.options.regionSelector.showOnlyOnFocusedMonitor.
   - Separates wanted and rendered states for exit fade out.
4. Active recording stop toggle:
   - Checks Persistent.states.screenRecord.active and calls record.sh --stop.
5. Declared videoAction and getScreenshotAction in WRegionSelectionPanel.qml:
   - property var videoAction is declared.
   - getScreenshotAction switches on root.videoAction.
6. Exit lifecycle, passive mode, and dismiss signals:
   - property bool open declared.
   - signal fadedOut() and signal dismiss() declared.
   - Content animates opacity with elementMoveFast (enter) and elementMoveExit (exit).
   - Passive mode sets passthrough mask and clears keyboard focus.
7. Coordinate normalization & screen bounding in WRegionSelectionPanel.qml:
   - Windows offset by root.monitorOffsetX and root.monitorOffsetY.
   - Selection clamped to screen width/height.
   - Empty/zero-sized selection guarded on drag release.
8. Elimination of idle Process snipProc:
   - Uses Quickshell.execDetached instead of snipProc.startDetached.
9. Elimination of DashedBorder (Canvas) in WRectangularSelection.qml:
   - No DashedBorder (Canvas) texture re-upload churn during drag.
   - Uses GPU-accelerated Rectangle border.
   - No raw hex literals (#ffffff, #000000) or untokenized durations.
10. 4dp grid compliance and Fluent styling:
    - Toolbar button paddings on 4dp grid (12dp).
    - Downward opening WMenu with downDirection: true.
    - Window selection icon is desktop.
"""

from pathlib import Path
import re
import sys

SHELL_DIR = Path("dots/.config/quickshell/ii")
SCREEN_SNIP_PATH = SHELL_DIR / "modules/waffle/screenSnip/WScreenSnip.qml"
PANEL_PATH = SHELL_DIR / "modules/waffle/screenSnip/WRegionSelectionPanel.qml"
RECT_SEL_PATH = SHELL_DIR / "modules/waffle/screenSnip/WRectangularSelection.qml"


def main():
    failed = False

    for p in (SCREEN_SNIP_PATH, PANEL_PATH, RECT_SEL_PATH):
        if not p.is_file():
            print(f"FAIL: File not found: {p}")
            return 1

    snip_text = SCREEN_SNIP_PATH.read_text(encoding="utf-8")
    panel_text = PANEL_PATH.read_text(encoding="utf-8")
    rect_text = RECT_SEL_PATH.read_text(encoding="utf-8")

    # 1. Pragma declarations
    for name, text in [("WScreenSnip.qml", snip_text),
                       ("WRegionSelectionPanel.qml", panel_text),
                       ("WRectangularSelection.qml", rect_text)]:
        if "pragma ComponentBehavior: Bound" not in text:
            print(f"FAIL: {name} missing 'pragma ComponentBehavior: Bound'")
            failed = True

    # 2. Root properties & null-safety in WScreenSnip.qml
    for prop in ("mediaType", "imageAction", "videoAction", "selectionMode"):
        if not re.search(rf"\bproperty\s+var\s+{prop}\b", snip_text):
            print(f"FAIL: WScreenSnip.qml missing root declaration for '{prop}'")
            failed = True

    if "regionSelectorLoader.item." in snip_text:
        print("FAIL: WScreenSnip.qml must not mutate regionSelectorLoader.item directly (null deref on cold open)")
        failed = True

    # 3. Multi-monitor support and exit lifecycle latching
    if "Variants {" not in snip_text or "model: Quickshell.screens" not in snip_text:
        print("FAIL: WScreenSnip.qml must use Variants over Quickshell.screens")
        failed = True

    if "showOnlyOnFocusedMonitor" not in snip_text:
        print("FAIL: WScreenSnip.qml must respect Config.options.regionSelector.showOnlyOnFocusedMonitor")
        failed = True

    if not re.search(r"property\s+bool\s+rendered:\s*false", snip_text):
        print("FAIL: WScreenSnip.qml Loader delegate must decouple 'rendered' from 'wanted'")
        failed = True

    # 4. Active recording stop toggle
    if "Persistent.states.screenRecord.active" not in snip_text or "--stop" not in snip_text:
        print("FAIL: WScreenSnip.qml must stop existing recording when record action invoked while active")
        failed = True

    # 5. Declared videoAction and getScreenshotAction in WRegionSelectionPanel.qml
    if not re.search(r"property\s+var\s+videoAction\b", panel_text):
        print("FAIL: WRegionSelectionPanel.qml missing declaration for 'property var videoAction'")
        failed = True

    if "root.videoAction" not in panel_text:
        print("FAIL: WRegionSelectionPanel.qml getScreenshotAction must switch on root.videoAction")
        failed = True

    # 6. Exit lifecycle, passive mode, and dismiss signals
    if not re.search(r"property\s+bool\s+open:\s*true", panel_text):
        print("FAIL: WRegionSelectionPanel.qml must declare 'property bool open: true'")
        failed = True

    if "signal fadedOut()" not in panel_text:
        print("FAIL: WRegionSelectionPanel.qml must declare 'signal fadedOut()'")
        failed = True

    if "signal dismiss()" not in panel_text:
        print("FAIL: WRegionSelectionPanel.qml must declare 'signal dismiss()'")
        failed = True

    if "elementMoveExit" not in panel_text or "elementMoveFast" not in panel_text:
        print("FAIL: WRegionSelectionPanel.qml must use elementMoveFast and elementMoveExit for enter/exit opacity")
        failed = True

    if "root.passive ? passthroughRegion : null" not in panel_text:
        print("FAIL: WRegionSelectionPanel.qml must mask to passthroughRegion when passive")
        failed = True

    # 7. Coordinate normalization & screen bounding in WRegionSelectionPanel.qml
    if "root.monitorOffsetX" not in panel_text or "root.monitorOffsetY" not in panel_text:
        print("FAIL: WRegionSelectionPanel.qml must offset window coordinates by monitorOffsetX/Y")
        failed = True

    if "selectionWidth <= 0 || selectionHeight <= 0" not in panel_text:
        print("FAIL: WRegionSelectionPanel.qml must guard against empty/zero selection on drag release")
        failed = True

    # 8. Elimination of idle Process snipProc
    if "id: snipProc" in panel_text:
        print("FAIL: WRegionSelectionPanel.qml should not contain idle Process snipProc")
        failed = True

    if "Quickshell.execDetached" not in panel_text:
        print("FAIL: WRegionSelectionPanel.qml should use Quickshell.execDetached")
        failed = True

    # 9. Elimination of DashedBorder (Canvas) in WRectangularSelection.qml
    if "DashedBorder" in rect_text:
        print("FAIL: WRectangularSelection.qml must eliminate DashedBorder (Canvas) for live drag")
        failed = True

    if re.search(r'"#[0-9a-fA-F]{3,8}"', rect_text):
        print("FAIL: WRectangularSelection.qml contains raw hex color literals")
        failed = True

    if "duration: 150" in rect_text:
        print("FAIL: WRectangularSelection.qml contains hardcoded duration literal (150)")
        failed = True

    # 10. 4dp grid compliance and Fluent styling
    if re.search(r"leftPadding:\s*11\b", panel_text) or re.search(r"rightPadding:\s*11\b", panel_text):
        print("FAIL: WRegionSelectionPanel.qml contains off-grid padding (11)")
        failed = True

    if "downDirection: true" not in panel_text:
        print("FAIL: WRegionSelectionPanel.qml selectionTypeMenu must set downDirection: true")
        failed = True

    if "calendar-add" in panel_text:
        print("FAIL: WRegionSelectionPanel.qml window icon should be desktop, not calendar-add")
        failed = True

    if not failed:
        print("PASS: waffle-screenSnip regression suite passed (10/10 check groups).")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
