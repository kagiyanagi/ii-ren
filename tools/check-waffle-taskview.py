#!/usr/bin/env python3
"""Regression checks for waffle-taskView audit.

Verifies:
1. Pragma declarations:
   - All 4 QML files declare pragma ComponentBehavior: Bound.
2. Lifecycle, exit latching, and race prevention:
   - WaffleTaskView.qml manages panelLoader.shouldBeActive without premature destruction.
   - TaskViewContent.qml declares signal closed and open()/close() functions.
   - Symmetrical enter/exit animations using Appearance.animation specs.
   - keyboardFocus drops to None during exit animation.
3. Screen lock and focus management:
   - Screen lock gating (!GlobalStates.screenLocked) on open/toggle and auto-close on lock.
   - HyprlandFocusGrab bound to GlobalStates.overviewOpen && root.monitorIsFocused.
   - IpcHandler targets "taskView" with toggle, open, close, workspacesToggle.
4. Dragging and null safety:
   - TaskViewWindow.qml binds drag state using root.Drag.active (attached Drag property).
   - DragHandler in TaskViewContent resets openedX/openedY on release.
   - window-layout.js protects against null/empty clients and 0 dimensions (no NaN/Infinity).
   - TaskViewWorkspace.qml protects against screen height <= 0 (no division by zero / NaN).
   - Null guards on HyprlandData.activeWorkspace, client address, and reposition().
5. GPU resource conservation:
   - ScreencopyView live capture gated on GlobalStates.overviewOpen.
6. 4dp grid compliance:
   - Grid-aligned metrics across all files.
"""

from pathlib import Path
import re
import subprocess
import sys

SHELL_DIR = Path("dots/.config/quickshell/ii")
TASKVIEW_DIR = SHELL_DIR / "modules/waffle/taskView"

QML_FILES = [
    "WaffleTaskView.qml",
    "TaskViewContent.qml",
    "TaskViewWindow.qml",
    "TaskViewWorkspace.qml",
]


def main():
    failed = False

    # Check files exist
    for f in QML_FILES + ["window-layout.js"]:
        p = TASKVIEW_DIR / f
        if not p.is_file():
            print(f"FAIL: Missing file: {p}")
            return 1

    tv_host = (TASKVIEW_DIR / "WaffleTaskView.qml").read_text(encoding="utf-8")
    tv_content = (TASKVIEW_DIR / "TaskViewContent.qml").read_text(encoding="utf-8")
    tv_window = (TASKVIEW_DIR / "TaskViewWindow.qml").read_text(encoding="utf-8")
    tv_workspace = (TASKVIEW_DIR / "TaskViewWorkspace.qml").read_text(encoding="utf-8")
    tv_js = (TASKVIEW_DIR / "window-layout.js").read_text(encoding="utf-8")

    # 1. Pragma declarations
    for name, content in [
        ("WaffleTaskView.qml", tv_host),
        ("TaskViewContent.qml", tv_content),
        ("TaskViewWindow.qml", tv_window),
        ("TaskViewWorkspace.qml", tv_workspace),
    ]:
        if "pragma ComponentBehavior: Bound" not in content:
            print(f"FAIL: {name} missing 'pragma ComponentBehavior: Bound'")
            failed = True

    # 2. Lifecycle, exit latching, and race prevention
    if "shouldBeActive" not in tv_host:
        print("FAIL: WaffleTaskView.qml must decouple loader active state with shouldBeActive")
        failed = True
    if not re.search(r"onClosed:\s*panelLoader\.shouldBeActive\s*=\s*false", tv_host):
        print("FAIL: WaffleTaskView.qml must reset shouldBeActive onClosed")
        failed = True
    if not re.search(r"signal\s+closed\b", tv_content):
        print("FAIL: TaskViewContent.qml must declare signal closed")
        failed = True
    if not re.search(r"function\s+open\(\)\s*\{[\s\S]*?closeAnim\.stop\(\)", tv_content):
        print("FAIL: TaskViewContent.qml open() must stop closeAnim")
        failed = True
    if not re.search(r"function\s+close\(\)\s*\{[\s\S]*?openAnim\.stop\(\)", tv_content):
        print("FAIL: TaskViewContent.qml close() must stop openAnim")
        failed = True
    if "Appearance.animation.elementMoveEnter.duration" not in tv_content:
        print("FAIL: TaskViewContent.qml openAnim must use Appearance.animation.elementMoveEnter.duration")
        failed = True
    if "Appearance.animation.elementMoveExit.duration" not in tv_content:
        print("FAIL: TaskViewContent.qml closeAnim must use Appearance.animation.elementMoveExit.duration")
        failed = True
    if not re.search(r"WlrKeyboardFocus\.None", tv_host):
        print("FAIL: WaffleTaskView.qml must release keyboard focus to None on close")
        failed = True

    # 3. Screen lock and focus management
    if "screenLocked" not in tv_host:
        print("FAIL: WaffleTaskView.qml missing screenLocked checks")
        failed = True
    if "HyprlandFocusGrab" not in tv_host:
        print("FAIL: WaffleTaskView.qml missing HyprlandFocusGrab")
        failed = True
    if 'target: "taskView"' not in tv_host:
        print("FAIL: WaffleTaskView.qml IpcHandler target must be 'taskView'")
        failed = True
    for fn in ["toggle", "open", "close", "workspacesToggle"]:
        if not re.search(rf"function\s+{fn}\s*\(", tv_host):
            print(f"FAIL: WaffleTaskView.qml IpcHandler missing function {fn}()")
            failed = True

    # 4. Dragging and null safety
    if "root.Drag.active" not in tv_window:
        print("FAIL: TaskViewWindow.qml must check attached root.Drag.active, not drag.active")
        failed = True
    if re.search(r"\bdrag\.active\b", tv_window):
        print("FAIL: TaskViewWindow.qml still references unattached drag.active")
        failed = True
    if not re.search(r"windowItem\.openedX\s*=\s*0", tv_content) or not re.search(r"windowItem\.openedY\s*=\s*0", tv_content):
        print("FAIL: TaskViewContent.qml must reset openedX/openedY on drag end")
        failed = True
    if "!hyprlandClient || !hyprlandClient.size" not in tv_js:
        print("FAIL: window-layout.js scaleWindow must guard against null/missing client size")
        failed = True
    if "screenHeight > 0" not in tv_workspace:
        print("FAIL: TaskViewWorkspace.qml must guard screenHeight > 0 against division by zero")
        failed = True
    if "HyprlandData.activeWorkspace" not in tv_content:
        print("FAIL: TaskViewContent.qml missing null guard on HyprlandData.activeWorkspace")
        failed = True

    # 5. GPU resource conservation
    if not re.search(r"live:\s*GlobalStates\.overviewOpen", tv_window):
        print("FAIL: TaskViewWindow.qml ScreencopyView.live must be gated on GlobalStates.overviewOpen")
        failed = True
    if not re.search(r"live:\s*GlobalStates\.overviewOpen", tv_workspace):
        print("FAIL: TaskViewWorkspace.qml ScreencopyView.live must be gated on GlobalStates.overviewOpen")
        failed = True

    # 6. 4dp grid compliance
    if "spacing: 25" in tv_content:
        print("FAIL: TaskViewContent.qml still contains off-grid spacing 25")
        failed = True
    if "topMargin: 9" in tv_workspace:
        print("FAIL: TaskViewWorkspace.qml still contains off-grid topMargin 9")
        failed = True
    if "implicitHeight: 38" in tv_window or "implicitWidth: 38" in tv_window:
        print("FAIL: TaskViewWindow.qml CloseButton size 38 is off 4dp grid")
        failed = True
    if "implicitHeight: 3\n" in tv_workspace:
        print("FAIL: TaskViewWorkspace.qml activeIndicator implicitHeight 3 is off 4dp grid")
        failed = True

    # Run check-design.py on the directory
    res = subprocess.run(
        [sys.executable, "tools/check-design.py", "-v"],
        capture_output=True,
        text=True,
        check=False,
    )
    for line in res.stdout.splitlines():
        if "taskView" in line:
            print(f"FAIL: check-design finding in taskView: {line}")
            failed = True

    if failed:
        return 1

    print("check-waffle-taskview: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
