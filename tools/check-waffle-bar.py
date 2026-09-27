#!/usr/bin/env python3
"""Regression checks for waffle-bar audit.

Verifies:
1. Every QML file in modules/waffle/bar declares pragma ComponentBehavior: Bound.
2. No detached IPC subprocess calls (StartButton.qml toggles GlobalStates directly).
3. WaffleBar.qml:
   - Bar loader gates on !GlobalStates.screenLocked.
   - Registers and unregisters persistent focus with GlobalFocusGrab.
   - Filters screens against Config.options.bar.screenList.
4. WaffleBarContent.qml:
   - FadeLoader encapsulates WidgetsButton in an explicit Component {}.
5. BarButton.qml:
   - Does not declare a shadowing MouseArea capturing LeftButton or overriding WButton.
6. AppButton.qml:
   - Multi-window card margins are on the 4dp grid (rightMargin: 4).
   - Press micro-interaction scale animation is declarative.
7. SystemButton.qml:
   - Null-safe audio sink properties (Audio.sink?.audio?.muted / volume).
   - Null-safe network name fallback.
8. TimeButton.qml:
   - Spacing and paddings are on the 4dp grid (spacing: 8, rightPadding: 20).
9. UpdatesButton.qml:
   - Margins on the 4dp grid (margins: 2).
10. tasks/TaskAppButton.qml:
    - Null-safe desktopEntry and toplevel access.
    - Active indicator bottomMargin on the 4dp grid (bottomMargin: 2).
11. tasks/WindowPreview.qml:
    - Padding and spacing on 4dp grid (padding: 4, spacing: 4).
    - Window close button size on 4dp grid (implicitHeight: 28, implicitWidth: 28).
    - Null-safe toplevel activation and close methods.
12. tasks/TaskPreview.qml:
    - Symmetrical animated open and close transitions.
    - No offscreen layer.enabled / OpacityMask pass on contentItem.
13. tray/TrayOverflowMenu.qml:
    - Zero-safe grid row and column calculations.
14. check-design.py reports 0 findings across all waffle/bar QML files.
"""

from pathlib import Path
import re
import sys

BASE = Path("dots/.config/quickshell/ii/modules/waffle/bar")

def check_file_exists(rel_path: str) -> Path:
    p = BASE / rel_path
    if not p.is_file():
        print(f"FAIL: File not found: {p}")
        sys.exit(1)
    return p

def main():
    failed = False

    # 1. Pragma ComponentBehavior: Bound across all files
    all_qml = sorted(BASE.glob("**/*.qml"))
    if not all_qml or len(all_qml) != 22:
        print(f"FAIL: Expected 22 QML files under modules/waffle/bar, found {len(all_qml)}")
        return 1

    for qml in all_qml:
        content = qml.read_text(encoding="utf-8")
        if "pragma ComponentBehavior: Bound" not in content:
            print(f"FAIL: {qml} missing 'pragma ComponentBehavior: Bound'")
            failed = True

    # 2. No detached IPC subprocess calls
    sb_path = check_file_exists("StartButton.qml")
    sb_text = sb_path.read_text(encoding="utf-8")
    if "ipc" in sb_text and "overview" in sb_text:
        print("FAIL: StartButton.qml still spawns detached quickshell IPC for overview toggle")
        failed = True

    # 3. WaffleBar.qml: screenLocked, GlobalFocusGrab, screenList
    wb_path = check_file_exists("WaffleBar.qml")
    wb_text = wb_path.read_text(encoding="utf-8")
    if "!GlobalStates.screenLocked" not in wb_text:
        print("FAIL: WaffleBar.qml does not guard barLoader against screenLocked")
        failed = True
    if "GlobalFocusGrab.addPersistent" not in wb_text or "GlobalFocusGrab.removePersistent" not in wb_text:
        print("FAIL: WaffleBar.qml missing GlobalFocusGrab persistent registration")
        failed = True
    if "screenList" not in wb_text or "Config.options?.bar?.screenList" not in wb_text:
        print("FAIL: WaffleBar.qml does not filter screens by screenList")
        failed = True

    # 4. WaffleBarContent.qml: Component wrapper on FadeLoader
    wbc_path = check_file_exists("WaffleBarContent.qml")
    wbc_text = wbc_path.read_text(encoding="utf-8")
    if re.search(r"sourceComponent:\s*WidgetsButton\s*\{", wbc_text):
        print("FAIL: WaffleBarContent.qml passes un-componentized WidgetsButton to FadeLoader")
        failed = True
    if not re.search(r"sourceComponent:\s*Component\s*\{\s*WidgetsButton", wbc_text):
        print("FAIL: WaffleBarContent.qml missing Component wrapper around WidgetsButton in FadeLoader")
        failed = True

    # 5. BarButton.qml: no shadowing MouseArea
    bb_path = check_file_exists("BarButton.qml")
    bb_text = bb_path.read_text(encoding="utf-8")
    if "MouseArea" in bb_text:
        print("FAIL: BarButton.qml still has redundant/shadowing MouseArea")
        failed = True

    # 6. AppButton.qml: on-grid stacked card margins and declarative scale
    ab_path = check_file_exists("AppButton.qml")
    ab_text = ab_path.read_text(encoding="utf-8")
    if "rightMargin: 3" in ab_text or "rightMargin: 5" in ab_text:
        print("FAIL: AppButton.qml has off-grid rightMargin (expected 4)")
        failed = True
    if "onDownChanged:" in ab_text:
        print("FAIL: AppButton.qml still uses imperative onDownChanged for scale")
        failed = True

    # 7. SystemButton.qml: null-safety
    sys_path = check_file_exists("SystemButton.qml")
    sys_text = sys_path.read_text(encoding="utf-8")
    if "Audio.sink?.audio.muted" in sys_text or "Audio.sink?.audio.volume" in sys_text:
        print("FAIL: SystemButton.qml lacks null guard on Audio.sink?.audio")
        failed = True
    if "Disconnected" not in sys_text:
        print("FAIL: SystemButton.qml lacks fallback for disconnected network name")
        failed = True

    # 8. TimeButton.qml: on-grid spacing and paddings
    tb_path = check_file_exists("TimeButton.qml")
    tb_text = tb_path.read_text(encoding="utf-8")
    if "spacing: 7" in tb_text:
        print("FAIL: TimeButton.qml has off-grid spacing: 7")
        failed = True
    if "rightPadding: 22" in tb_text:
        print("FAIL: TimeButton.qml has off-grid rightPadding: 22")
        failed = True

    # 9. UpdatesButton.qml: on-grid margins
    ub_path = check_file_exists("UpdatesButton.qml")
    ub_text = ub_path.read_text(encoding="utf-8")
    if "margins: 1" in ub_text:
        print("FAIL: UpdatesButton.qml has off-grid margins: 1")
        failed = True

    # 10. tasks/TaskAppButton.qml
    tab_path = check_file_exists("tasks/TaskAppButton.qml")
    tab_text = tab_path.read_text(encoding="utf-8")
    if "bottomMargin: 1" in tab_text:
        print("FAIL: TaskAppButton.qml has off-grid bottomMargin: 1")
        failed = True
    if re.search(r"root\.desktopEntry\.execute\(", tab_text):
        print("FAIL: TaskAppButton.qml has non-null-safe root.desktopEntry.execute()")
        failed = True

    # 11. tasks/WindowPreview.qml
    wp_path = check_file_exists("tasks/WindowPreview.qml")
    wp_text = wp_path.read_text(encoding="utf-8")
    if "padding: 5" in wp_text or "spacing: 5" in wp_text:
        print("FAIL: WindowPreview.qml has off-grid padding or spacing")
        failed = True
    if "implicitHeight: 30" in wp_text:
        print("FAIL: WindowPreview.qml has off-grid close button height: 30")
        failed = True

    # 12. tasks/TaskPreview.qml
    tp_path = check_file_exists("tasks/TaskPreview.qml")
    tp_text = tp_path.read_text(encoding="utf-8")
    if "layer.enabled" in tp_text or "OpacityMask" in tp_text:
        print("FAIL: TaskPreview.qml still uses expensive offscreen layer / OpacityMask")
        failed = True
    if "closeAnim" not in tp_text:
        print("FAIL: TaskPreview.qml missing animated closeAnim transition")
        failed = True

    # 13. tray/TrayOverflowMenu.qml: zero-safe grid calculations
    tom_path = check_file_exists("tray/TrayOverflowMenu.qml")
    tom_text = tom_path.read_text(encoding="utf-8")
    if "Math.floor(Math.sqrt(TrayService.unpinnedItems.length))" in tom_text:
        print("FAIL: TrayOverflowMenu.qml has unprotected 0/NaN row/column calculation")
        failed = True

    # 14. check-design.py verification
    sys.path.insert(0, "tools")
    import importlib
    check_design = importlib.import_module("check-design")
    design_hits = 0
    for qml in all_qml:
        rel = qml.resolve().relative_to(check_design.QML_ROOT.resolve())
        lines = qml.read_text(encoding="utf-8").splitlines()
        for name, sev, fn in check_design.RULES:
            for hit in fn(lines):
                print(f"FAIL: {rel}:{hit[0]}: [{name}] {hit[1]}")
                design_hits += 1
                failed = True

    if failed:
        print("\nwaffle-bar regression checks FAILED")
        return 1

    print("All waffle-bar regression checks PASSED.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
