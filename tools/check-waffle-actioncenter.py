#!/usr/bin/env python3
"""Regression checks for waffle-actionCenter audit.

Verifies:
1. NightLightControl.qml contains no rogue Bluetooth imports or discovery calls.
2. WifiControl.qml and BluetoothControl.qml do not reference non-existent contentLayout.
3. No actionCenter components spawn detached quickshell IPC subprocesses to close themselves.
4. VolumeControl.qml volume mixer header is not gated on EasyEffects availability.
5. MainPageBodySliders.qml uses null-safe Audio.sink access and no interactive dummy buttons.
6. ActionCenterContent.qml media pane collapses when inactive (visible: hasMedia).
7. MainPageBody.qml uses WPanelSeparator rather than raw 1px Rectangles.
8. Off-grid spacings and margins in MediaPaneContent.qml and MainPageBody.qml are resolved.
9. Every QML file in modules/waffle/actionCenter declares pragma ComponentBehavior: Bound.
"""

from pathlib import Path
import re
import sys

BASE = Path("dots/.config/quickshell/ii/modules/waffle/actionCenter")

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
    if not all_qml:
        print("FAIL: No QML files found under actionCenter")
        return 1

    for qml in all_qml:
        content = qml.read_text(encoding="utf-8")
        if "pragma ComponentBehavior: Bound" not in content:
            print(f"FAIL: {qml} missing 'pragma ComponentBehavior: Bound'")
            failed = True

    # 2. NightLightControl: No Bluetooth references or imports
    nl_path = check_file_exists("nightLight/NightLightControl.qml")
    nl_text = nl_path.read_text(encoding="utf-8")
    if "Bluetooth" in nl_text:
        print("FAIL: NightLightControl.qml still references Bluetooth")
        failed = True

    # 3. WifiControl & BluetoothControl: No contentLayout ReferenceError
    for ctrl_rel in ["wifi/WifiControl.qml", "bluetooth/BluetoothControl.qml"]:
        ctrl_path = check_file_exists(ctrl_rel)
        ctrl_text = ctrl_path.read_text(encoding="utf-8")
        if "contentLayout" in ctrl_text:
            print(f"FAIL: {ctrl_rel} references non-existent contentLayout")
            failed = True

    # 4. No detached IPC subprocess calls to sidebarLeft
    for qml in all_qml:
        text = qml.read_text(encoding="utf-8")
        if re.search(r'Quickshell\.execDetached\(\[.*"sidebarLeft"', text):
            print(f"FAIL: {qml} spawns detached qs IPC subprocess to close itself")
            failed = True

    # 5. VolumeControl: Volume mixer not gated on EasyEffects; uses WTextButton
    vc_path = check_file_exists("volumeControl/VolumeControl.qml")
    vc_text = vc_path.read_text(encoding="utf-8")
    if re.search(r"SectionText\s*\{[^}]*EasyEffects\.available[^}]*Volume mixer", vc_text, re.DOTALL):
        print("FAIL: VolumeControl.qml volume mixer header is gated on EasyEffects")
        failed = True
    if "WTextButton" not in vc_text:
        print("FAIL: VolumeControl.qml footer should use WTextButton")
        failed = True

    # 6. MainPageBodySliders: Null safety and dummy spacer
    sliders_path = check_file_exists("mainPage/MainPageBodySliders.qml")
    sliders_text = sliders_path.read_text(encoding="utf-8")
    if re.search(r"value:\s*Audio\.sink\.audio\.volume", sliders_text):
        print("FAIL: MainPageBodySliders.qml contains unguarded Audio.sink.audio.volume binding")
        failed = True
    if re.search(r"WPanelIconButton\s*\{\s*opacity:\s*0\s*\}", sliders_text):
        print("FAIL: MainPageBodySliders.qml uses clickable WPanelIconButton { opacity: 0 } as spacer")
        failed = True

    # 7. ActionCenterContent: Media pane collapses when inactive
    acc_path = check_file_exists("ActionCenterContent.qml")
    acc_text = acc_path.read_text(encoding="utf-8")
    if "visible: hasMedia" not in acc_text and "visible: opacity > 0" not in acc_text:
        print("FAIL: ActionCenterContent.qml media pane lacks visibility condition and will not collapse")
        failed = True
    if "ActionCenterContext.reset()" not in acc_text:
        print("FAIL: ActionCenterContent.qml does not reset ActionCenterContext on close")
        failed = True

    # 8. MainPageBody: No raw Rectangle separator; margins on grid
    mpb_path = check_file_exists("mainPage/MainPageBody.qml")
    mpb_text = mpb_path.read_text(encoding="utf-8")
    if re.search(r"Rectangle\s*\{\s*implicitHeight:\s*1", mpb_text):
        print("FAIL: MainPageBody.qml uses raw Rectangle separator line")
        failed = True
    if "topMargin: 18" in mpb_text or "bottomMargin: 14" in mpb_text:
        print("FAIL: MainPageBody.qml contains off-grid margins")
        failed = True

    # 9. MediaPaneContent: Spacings and margins on grid
    mpc_path = check_file_exists("MediaPaneContent.qml")
    mpc_text = mpc_path.read_text(encoding="utf-8")
    for bad in ["leftMargin: 23", "rightMargin: 23", "spacing: 25", "spacing: 26", "preferredWidth: 58"]:
        if bad in mpc_text:
            print(f"FAIL: MediaPaneContent.qml still contains '{bad}'")
            failed = True

    # 10. VolumeEntry: Null safety on audio
    ve_path = check_file_exists("volumeControl/VolumeEntry.qml")
    ve_text = ve_path.read_text(encoding="utf-8")
    if "root.node.audio.muted = !root.node?.audio.muted" in ve_text:
        print("FAIL: VolumeEntry.qml contains unsafe muted toggle")
        failed = True

    if failed:
        return 1

    print(f"ok: all checks passed ({len(all_qml)} files verified in waffle/actionCenter)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
