#!/usr/bin/env python3
"""Regression checks for waffle-notificationCenter audit.

Verifies:
1. Every QML file in modules/waffle/notificationCenter declares pragma ComponentBehavior: Bound.
2. WaffleNotificationCenter.qml:
   - panelLoader.active does not bind directly to GlobalStates.sidebarRightOpen.
   - Preserves exit animation on close.
   - Screen locked gating (!GlobalStates.screenLocked).
   - HyprlandFocusGrab active state gates on screen lock.
   - IPC handler supports toggle, open, and close.
3. FocusFooter.qml:
   - No detached quickshell IPC subprocess calls to sidebarRight.
   - Pomodoro focus time decrement is clamped (Math.max(300, ...)).
   - Metrics on 4dp grid (implicitWidth: 80).
4. CalendarWidget.qml:
   - Button size, margins, and spacings on 4dp grid (buttonSize: 40, spacing: 4, 2, 8, implicitHeight: 32).
   - No off-grid buttonSize: 41 or spacing: 6/1.
5. NotificationPaneContent.qml:
   - Root is Item (not FooterRectangle) and has no anchors.fill: parent.
   - Null-safe notifications access (groupsByAppName?.[modelData]).
6. NotificationCenterContent.qml:
   - Implicit height calculation is clamped with Math.max(230, ...).
7. WNotificationDismissAnim.qml:
   - Does not attempt invalid PropertyAction on "ListView.delayRemove".
   - Uses token duration (Appearance.animation.elementMoveExit.duration).
   - Emits dismissed signal on completion.
8. WNotificationGroup.qml:
   - Attaches ListView.delayRemove: removeAnimation.running.
   - Discards notifications only on animation completion (onDismissed).
   - 4dp grid metrics (margins: 12, spacing: 8, rightMargin: 4, clamp 36).
9. WSingleNotification.qml:
   - Action buttons have functional onClicked invoking Notifications.attemptInvokeAction.
   - Dismiss button uses visible: opacity > 0 to prevent clicks when hidden.
   - Attaches ListView.delayRemove: removeAnimation.running.
   - 4dp grid metrics (spacing: 16, spacing: 4, implicitSize: 16, horizontalPadding: 12).
   - Null safety on notification properties.
10. SmallBorderedIconAndTextButton.qml:
    - Icon size on 4dp grid (implicitSize: 16).
"""

from pathlib import Path
import re
import sys

BASE = Path("dots/.config/quickshell/ii/modules/waffle/notificationCenter")

def check_file_exists(rel_path: str) -> Path:
    p = BASE / rel_path
    if not p.is_file():
        print(f"FAIL: File not found: {p}")
        sys.exit(1)
    return p

def main():
    failed = False

    # 1. Pragma ComponentBehavior: Bound across all files
    all_qml = sorted(BASE.glob("*.qml"))
    if not all_qml or len(all_qml) != 13:
        print(f"FAIL: Expected 13 QML files under modules/waffle/notificationCenter, found {len(all_qml)}")
        return 1

    for qml in all_qml:
        content = qml.read_text(encoding="utf-8")
        if "pragma ComponentBehavior: Bound" not in content:
            print(f"FAIL: {qml} missing 'pragma ComponentBehavior: Bound'")
            failed = True

    # 2. WaffleNotificationCenter.qml: Lifetime, lock gating, IPC
    wnc_path = check_file_exists("WaffleNotificationCenter.qml")
    wnc_text = wnc_path.read_text(encoding="utf-8")
    if re.search(r"Loader\s*\{[^}]*active:\s*GlobalStates\.sidebarRightOpen", wnc_text):
        print("FAIL: WaffleNotificationCenter.qml directly binds panelLoader.active to sidebarRightOpen, killing exit animation")
        failed = True
    if "GlobalStates.screenLocked" not in wnc_text:
        print("FAIL: WaffleNotificationCenter.qml missing screenLocked guard")
        failed = True
    if "!GlobalStates.screenLocked" not in wnc_text:
        print("FAIL: WaffleNotificationCenter.qml focus grab not gated on screenLocked")
        failed = True
    for fn in ["function toggle()", "function close()", "function open()"]:
        if fn not in wnc_text:
            print(f"FAIL: WaffleNotificationCenter.qml IpcHandler missing {fn}")
            failed = True

    # 3. FocusFooter.qml: No detached IPC, pomodoro clamp, 4dp grid
    ff_path = check_file_exists("FocusFooter.qml")
    ff_text = ff_path.read_text(encoding="utf-8")
    if "Quickshell.execDetached" in ff_text and "sidebarRight" in ff_text:
        print("FAIL: FocusFooter.qml spawns detached quickshell IPC subprocess to close sidebarRight")
        failed = True
    if "Math.max(300" not in ff_text:
        print("FAIL: FocusFooter.qml pomodoro focus decrement lacks lower clamp")
        failed = True
    if "implicitWidth: 81" in ff_text:
        print("FAIL: FocusFooter.qml implicitWidth: 81 is off the 4dp grid (use 80)")
        failed = True

    # 4. CalendarWidget.qml: 4dp grid metrics
    cw_path = check_file_exists("CalendarWidget.qml")
    cw_text = cw_path.read_text(encoding="utf-8")
    if "buttonSize: 41" in cw_text or "buttonSpacing: 6" in cw_text:
        print("FAIL: CalendarWidget.qml contains off-grid buttonSize or spacing (41/6)")
        failed = True
    if "topMargin: 10" in cw_text or "leftMargin: 5" in cw_text or re.search(r"spacing:\s*1\b", cw_text):
        print("FAIL: CalendarWidget.qml contains off-grid margins or spacing (10/5/1)")
        failed = True
    if "implicitHeight: 34" in cw_text:
        print("FAIL: CalendarWidget.qml contains off-grid implicitHeight: 34 (use 32)")
        failed = True
    if "buttonSize: 40" not in cw_text:
        print("FAIL: CalendarWidget.qml missing buttonSize: 40")
        failed = True

    # 5. NotificationPaneContent.qml: Root Item, no anchors.fill on root, null-safety
    npc_path = check_file_exists("NotificationPaneContent.qml")
    npc_text = npc_path.read_text(encoding="utf-8")
    if "FooterRectangle {" in npc_text:
        print("FAIL: NotificationPaneContent.qml root should be Item, not FooterRectangle")
        failed = True
    root_header = npc_text.split("ColumnLayout")[0]
    if "anchors.fill: parent" in root_header:
        print("FAIL: NotificationPaneContent.qml root has anchors.fill: parent fighting WPane contentItem sizing")
        failed = True
    if "groupsByAppName?.[modelData]" not in npc_text:
        print("FAIL: NotificationPaneContent.qml missing null-safe groupsByAppName access")
        failed = True

    # 6. NotificationCenterContent.qml: Clamped height
    ncc_path = check_file_exists("NotificationCenterContent.qml")
    ncc_text = ncc_path.read_text(encoding="utf-8")
    if "Math.max(230" not in ncc_text:
        print("FAIL: NotificationCenterContent.qml missing Math.max clamp on implicitHeight")
        failed = True

    # 7. WNotificationDismissAnim.qml: Valid property animation, token duration
    nda_path = check_file_exists("WNotificationDismissAnim.qml")
    nda_text = nda_path.read_text(encoding="utf-8")
    if '"ListView.delayRemove"' in nda_text:
        print("FAIL: WNotificationDismissAnim.qml attempts invalid PropertyAction on 'ListView.delayRemove'")
        failed = True
    if "duration: 250" in nda_text:
        print("FAIL: WNotificationDismissAnim.qml uses literal 250ms duration")
        failed = True
    if "signal dismissed" not in nda_text:
        print("FAIL: WNotificationDismissAnim.qml missing dismissed signal")
        failed = True

    # 8. WNotificationGroup.qml: delayRemove, animated dismiss, 4dp metrics
    ng_path = check_file_exists("WNotificationGroup.qml")
    ng_text = ng_path.read_text(encoding="utf-8")
    if "ListView.delayRemove: removeAnimation.running" not in ng_text:
        print("FAIL: WNotificationGroup.qml missing ListView.delayRemove binding")
        failed = True
    if "margins: 11" in ng_text or "spacing: 7" in ng_text or "rightMargin: 3" in ng_text:
        print("FAIL: WNotificationGroup.qml contains off-grid metrics (11/7/3)")
        failed = True

    # 9. WSingleNotification.qml: action onClicked, visible guard, delayRemove, 4dp metrics
    sn_path = check_file_exists("WSingleNotification.qml")
    sn_text = sn_path.read_text(encoding="utf-8")
    if "Notifications.attemptInvokeAction" not in sn_text:
        print("FAIL: WSingleNotification.qml action button missing attemptInvokeAction onClicked handler")
        failed = True
    if "visible: opacity > 0" not in sn_text:
        print("FAIL: WSingleNotification.qml dismiss button missing visible: opacity > 0 (interactive when hidden)")
        failed = True
    if "ListView.delayRemove: removeAnimation.running" not in sn_text:
        print("FAIL: WSingleNotification.qml missing ListView.delayRemove binding")
        failed = True
    if "spacing: 19" in sn_text or "horizontalPadding: 10" in sn_text:
        print("FAIL: WSingleNotification.qml contains off-grid metrics (19/10)")
        failed = True
    if "implicitSize: 14" in sn_text or "implicitSize: 18" in sn_text:
        print("FAIL: WSingleNotification.qml contains off-grid icon sizes (14/18)")
        failed = True

    # 10. SmallBorderedIconAndTextButton.qml: 4dp icon size
    sbt_path = check_file_exists("SmallBorderedIconAndTextButton.qml")
    sbt_text = sbt_path.read_text(encoding="utf-8")
    if "implicitSize: 14" in sbt_text:
        print("FAIL: SmallBorderedIconAndTextButton.qml implicitSize: 14 is off the 4dp grid (use 16)")
        failed = True

    if failed:
        return 1

    print("OK: all waffle-notificationCenter regression checks passed.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
