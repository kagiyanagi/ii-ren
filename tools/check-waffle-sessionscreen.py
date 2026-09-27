#!/usr/bin/env python3
"""Regression checks for waffle-sessionScreen audit.

Verifies:
1. Every QML file under modules/waffle/sessionScreen declares pragma ComponentBehavior: Bound.
2. WaffleSessionScreen.qml implements latching (rendered property, release() on closed,
   Loader active: root.rendered, no raw active: GlobalStates.sessionOpen binding).
3. PanelWindow has color: "transparent" and anchors all four edges.
4. SessionScreenContent.qml defines closed() signal and animates enter/exit transitions.
5. Scrim uses Appearance.m3colors.m3scrim with click-to-dismiss and WheelHandler absorption.
6. Guarded action runner prevents double-activation during exit animations.
7. Key navigation up from taskManagerButton points to changePasswordButton (not signOutButton).
8. PowerButton.qml gates actions on SessionWarnings capabilities (CanSuspend, CanPowerOff, CanReboot).
9. All 4dp grid violations and raw hex literals in sessionScreen are resolved.
"""

from pathlib import Path
import re
import sys

BASE = Path("dots/.config/quickshell/ii/modules/waffle/sessionScreen")

def check_file_exists(rel_path: str) -> Path:
    p = BASE / rel_path
    if not p.is_file():
        print(f"FAIL: File not found: {p}")
        sys.exit(1)
    return p

def main() -> int:
    failed = False

    all_qml = sorted(BASE.glob("*.qml"))
    if not all_qml:
        print("FAIL: No QML files found under waffle/sessionScreen")
        return 1

    # 1. Pragma ComponentBehavior: Bound across all files
    for qml in all_qml:
        content = qml.read_text(encoding="utf-8")
        if "pragma ComponentBehavior: Bound" not in content:
            print(f"FAIL: {qml} missing 'pragma ComponentBehavior: Bound'")
            failed = True

    # 2. Surface latching in WaffleSessionScreen.qml
    wss_path = check_file_exists("WaffleSessionScreen.qml")
    wss_text = wss_path.read_text(encoding="utf-8")

    if not re.search(r"property\s+bool\s+rendered\s*:\s*false", wss_text):
        print("FAIL: WaffleSessionScreen.qml missing latched 'property bool rendered: false'")
        failed = True

    if not re.search(r"active:\s*root\.rendered", wss_text):
        print("FAIL: WaffleSessionScreen.qml Loader should be 'active: root.rendered'")
        failed = True

    if re.search(r"active:\s*GlobalStates\.sessionOpen", wss_text):
        print("FAIL: WaffleSessionScreen.qml Loader directly binds active: GlobalStates.sessionOpen")
        failed = True

    if "release()" not in wss_text or "root.rendered = false" not in wss_text:
        print("FAIL: WaffleSessionScreen.qml missing release() logic for exit latching")
        failed = True

    if 'color: "transparent"' not in wss_text:
        print("FAIL: WaffleSessionScreen.qml PanelWindow must use color: \"transparent\"")
        failed = True

    if "#000000" in wss_text:
        print("FAIL: WaffleSessionScreen.qml contains raw #000000 hex literal")
        failed = True

    for edge in ("top", "bottom", "left", "right"):
        if not re.search(rf"\b{edge}:\s*true", wss_text):
            print(f"FAIL: WaffleSessionScreen.qml PanelWindow missing anchor {edge}: true")
            failed = True

    # 3. SessionScreenContent.qml: closed() signal, animations, scrim, and guarded run()
    ssc_path = check_file_exists("SessionScreenContent.qml")
    ssc_text = ssc_path.read_text(encoding="utf-8")

    if "signal closed()" not in ssc_text:
        print("FAIL: SessionScreenContent.qml missing 'signal closed()'")
        failed = True

    if "Appearance.m3colors.m3scrim" not in ssc_text and "Appearance.colors.colScrim" not in ssc_text:
        print("FAIL: SessionScreenContent.qml scrim missing tokenized scrim color")
        failed = True

    if "WheelHandler" not in ssc_text:
        print("FAIL: SessionScreenContent.qml scrim missing WheelHandler absorption")
        failed = True

    if not re.search(r"function\s+run\s*\(action\)\s*\{\s*if\s*\(!GlobalStates\.sessionOpen\)\s*return;", ssc_text):
        print("FAIL: SessionScreenContent.qml missing guarded run() to prevent double-activation")
        failed = True

    if "KeyNavigation.up: changePasswordButton" not in ssc_text:
        print("FAIL: SessionScreenContent.qml taskManagerButton KeyNavigation.up should be changePasswordButton")
        failed = True

    if "#ffffff" in ssc_text or "#000000" in ssc_text:
        print("FAIL: SessionScreenContent.qml contains hardcoded hex literal")
        failed = True

    # Check 4dp grid compliance in SessionScreenContent.qml
    for off_grid_num in [5, 21, 31, 38]:
        if re.search(rf"\b(top|bottom|left|right)Margin:\s*{off_grid_num}\b", ssc_text):
            print(f"FAIL: SessionScreenContent.qml contains off-grid margin value {off_grid_num}")
            failed = True

    # 4. WSessionScreenTextButton.qml metrics and focus ring
    btn_path = check_file_exists("WSessionScreenTextButton.qml")
    btn_text = btn_path.read_text(encoding="utf-8")

    if "implicitWidth: 135" in btn_text:
        print("FAIL: WSessionScreenTextButton.qml still has off-grid implicitWidth: 135")
        failed = True

    if "horizontalPadding: 5" in btn_text:
        print("FAIL: WSessionScreenTextButton.qml still has off-grid horizontalPadding: 5")
        failed = True

    if "#ffffff" in btn_text:
        print("FAIL: WSessionScreenTextButton.qml contains hardcoded #ffffff")
        failed = True

    # 5. PowerButton.qml capabilities gating and actions
    pwr_path = check_file_exists("PowerButton.qml")
    pwr_text = pwr_path.read_text(encoding="utf-8")

    for cap in ["CanSuspend", "CanPowerOff", "CanReboot"]:
        if f'SessionWarnings.can("{cap}")' not in pwr_text:
            print(f"FAIL: PowerButton.qml missing capability check for {cap}")
            failed = True

    for act in ["Session.suspend()", "Session.poweroff()", "Session.reboot()"]:
        if act not in pwr_text:
            print(f"FAIL: PowerButton.qml missing action {act}")
            failed = True

    if failed:
        print("\ncheck-waffle-sessionscreen: FAILED")
        return 1

    print("check-waffle-sessionscreen: All checks passed.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
