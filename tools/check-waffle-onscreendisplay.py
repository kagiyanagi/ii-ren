#!/usr/bin/env python3
"""Regression checks for waffle-onScreenDisplay audit.

Verifies:
1. All 4 QML files declare `pragma ComponentBehavior: Bound`.
2. No undefined references (e.g. `osdRoot`) in WaffleOSD.qml; declarative screen binding used.
3. `root.trigger()` is implemented and callable on WaffleOSD.
4. IpcHandler targets "osd" and "osdVolume" with trigger, open, close, hide, toggle methods.
5. Fullscreen gating (hideWhenFullscreen with active workspace window detection) and screenLocked checks.
6. Config.osdIndicatorEnabled gating before opening indicators.
7. OSDValue metrics conform to 4dp grid (height 48, widths 192/168, icon 16, margins on grid).
8. WTextWithFixedWidth uses longestText: "100" without hardcoded clipping implicitWidth.
9. Null-safe property accesses on Audio and Brightness monitors.
10. No broken Behavior on Loader.source.
"""

from pathlib import Path
import re
import sys

SHELL_DIR = Path("dots/.config/quickshell/ii")
OSD_DIR = SHELL_DIR / "modules/waffle/onScreenDisplay"

FILES = [
    "WaffleOSD.qml",
    "OSDValue.qml",
    "VolumeOSD.qml",
    "BrightnessOSD.qml",
]


def main():
    failed = False

    # Check files exist
    for f in FILES:
        p = OSD_DIR / f
        if not p.is_file():
            print(f"FAIL: Missing file: {p}")
            return 1

    waffle_osd = (OSD_DIR / "WaffleOSD.qml").read_text(encoding="utf-8")
    osd_value = (OSD_DIR / "OSDValue.qml").read_text(encoding="utf-8")
    volume_osd = (OSD_DIR / "VolumeOSD.qml").read_text(encoding="utf-8")
    brightness_osd = (OSD_DIR / "BrightnessOSD.qml").read_text(encoding="utf-8")

    # 1. pragma ComponentBehavior: Bound
    for name, content in [
        ("WaffleOSD.qml", waffle_osd),
        ("OSDValue.qml", osd_value),
        ("VolumeOSD.qml", volume_osd),
        ("BrightnessOSD.qml", brightness_osd),
    ]:
        if "pragma ComponentBehavior: Bound" not in content:
            print(f"FAIL: {name} is missing 'pragma ComponentBehavior: Bound'")
            failed = True

    # 2. No undefined osdRoot reference, declarative screen binding
    if "osdRoot" in waffle_osd:
        print("FAIL: WaffleOSD.qml contains undefined 'osdRoot' reference")
        failed = True
    if "screen: root.focusedScreen" not in waffle_osd:
        print("FAIL: WaffleOSD.qml missing declarative 'screen: root.focusedScreen'")
        failed = True

    # 3. root.trigger() function exists
    if not re.search(r"function\s+trigger\s*\(", waffle_osd):
        print("FAIL: WaffleOSD.qml missing 'function trigger(' definition on root")
        failed = True

    # 4. IPC handlers
    if 'target: "osd"' not in waffle_osd:
        print("FAIL: WaffleOSD.qml missing IpcHandler with target 'osd'")
        failed = True
    if 'target: "osdVolume"' not in waffle_osd:
        print("FAIL: WaffleOSD.qml missing IpcHandler with target 'osdVolume'")
        failed = True

    for fn in ["trigger", "open", "close", "hide", "toggle"]:
        if not re.search(rf"function\s+{fn}\s*\(", waffle_osd):
            print(f"FAIL: WaffleOSD.qml missing IPC function '{fn}'")
            failed = True

    # 5. Fullscreen gating and screen locked
    if "hideWhenFullscreen" not in waffle_osd or "hasFullscreenWindow" not in waffle_osd:
        print("FAIL: WaffleOSD.qml missing hideWhenFullscreen / hasFullscreenWindow detection")
        failed = True
    if "screenLocked" not in waffle_osd:
        print("FAIL: WaffleOSD.qml missing screenLocked check/closing")
        failed = True

    # 6. Config.osdIndicatorEnabled check
    if "osdIndicatorEnabled" not in waffle_osd:
        print("FAIL: WaffleOSD.qml does not check Config.osdIndicatorEnabled")
        failed = True

    # 7. OSDValue 4dp grid metrics
    if "implicitHeight: 48" not in osd_value:
        print("FAIL: OSDValue.qml implicitHeight is not 48dp")
        failed = True
    if "implicitHeight: 46" in osd_value:
        print("FAIL: OSDValue.qml still contains off-grid implicitHeight 46")
        failed = True
    if "170" in osd_value:
        print("FAIL: OSDValue.qml contains off-grid width 170")
        failed = True
    if "implicitSize: 16" not in osd_value:
        print("FAIL: OSDValue.qml FluentIcon implicitSize is not 16dp")
        failed = True
    if "implicitSize: 18" in osd_value:
        print("FAIL: OSDValue.qml still contains off-grid implicitSize 18")
        failed = True
    if "Layout.rightMargin: root.showNumber ? 0 : 3" in osd_value:
        print("FAIL: OSDValue.qml contains off-grid margin 3")
        failed = True

    # 8. WTextWithFixedWidth uses longestText without hardcoded clipping width
    if 'longestText: "100"' not in osd_value:
        print('FAIL: OSDValue.qml missing longestText: "100" on WTextWithFixedWidth')
        failed = True
    if re.search(r"WTextWithFixedWidth[\s\S]*?implicitWidth:\s*16", osd_value):
        print("FAIL: OSDValue.qml forces clipping implicitWidth: 16 on WTextWithFixedWidth")
        failed = True

    # 9. Null-safe property accesses
    if "Audio.sink?.audio?.volume" not in volume_osd:
        print("FAIL: VolumeOSD.qml lacks null guard on Audio.sink?.audio?.volume")
        failed = True
    if "brightnessMonitor?.brightness" not in brightness_osd:
        print("FAIL: BrightnessOSD.qml lacks null guard on brightnessMonitor?.brightness")
        failed = True

    # 10. No broken Behavior on Loader.source
    if "Behavior on source" in waffle_osd:
        print("FAIL: WaffleOSD.qml still has broken Behavior on Loader.source")
        failed = True

    if failed:
        return 1

    print("PASS: waffle-onScreenDisplay regression checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
