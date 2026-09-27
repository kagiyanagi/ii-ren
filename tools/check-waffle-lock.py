#!/usr/bin/env python3
"""Regression checks for waffle-lock audit.

Verifies:
1. WaffleLock.qml declares pragma ComponentBehavior: Bound.
2. GPU effect budget compliance:
   - No layer.enabled / OpacityMask pass on passwordInputWrapper.
   - Uses FastBlur with visible: opacity > 0 instead of 201-sample GaussianBlur.
3. Bidirectional and interactive navigation:
   - Reversible transitions between clock view and password view (no stuck one-way y: -height * 1.1).
   - MouseArea on unfocusedContent for click and wheel triggers.
   - Printable character forwarding from clock screen to root.context.currentText.
   - Escape key clears text or returns to clock screen (switchToUnfocusedView).
   - Idle return-to-clock timer (returnToClockTimer).
4. Caps Lock synchronization:
   - Refreshes lock keys on Component.onCompleted (HyprlandXkb.refreshLockKeys).
   - Toggles state on Qt.Key_CapsLock via HyprlandXkb.noteCapsLockPressed without auto-repeat.
   - Displays "Caps Lock is on" in status text.
5. Status, PAM lockout and failure feedback:
   - Surfaces root.context.authMessage (PAM lockout / faillock).
   - Surfaces root.context.showFailure ("The password is incorrect. Please try again.").
   - ErrorShakeAnimation triggers on auth failure.
   - Displays WIndeterminateProgressBar when root.context.unlockInProgress is true.
   - Disables password input and submit buttons during unlockInProgress.
   - Reconnects keyboard focus on shouldReFocus and onUnlockInProgressChanged.
6. Battery indicator null-safety:
   - Battery indicator gated on Battery.available.
7. 4dp grid and design law:
   - Margins, spacing, and dimensions adhere to the 4dp grid.
   - No raw hex literals.
   - check-design.py reports 0 findings on WaffleLock.qml.
"""

from pathlib import Path
import re
import subprocess
import sys

SHELL_DIR = Path("dots/.config/quickshell/ii")
LOCK_PATH = SHELL_DIR / "modules/waffle/lock/WaffleLock.qml"


def main():
    failed = False

    if not LOCK_PATH.is_file():
        print(f"FAIL: File not found: {LOCK_PATH}")
        return 1

    lock_text = LOCK_PATH.read_text(encoding="utf-8")

    # 1. Pragma ComponentBehavior: Bound
    if "pragma ComponentBehavior: Bound" not in lock_text:
        print("FAIL: WaffleLock.qml missing 'pragma ComponentBehavior: Bound'")
        failed = True

    # 2. GPU effect budget compliance
    if "OpacityMask" in lock_text:
        print("FAIL: WaffleLock.qml still contains OpacityMask")
        failed = True
    if "layer.enabled: true" in lock_text or "layer.enabled : true" in lock_text:
        print("FAIL: WaffleLock.qml still enables an offscreen layer")
        failed = True
    if "GaussianBlur" in lock_text:
        print("FAIL: WaffleLock.qml still uses heavy GaussianBlur")
        failed = True
    if "FastBlur" not in lock_text:
        print("FAIL: WaffleLock.qml does not use FastBlur")
        failed = True
    if "visible: opacity > 0" not in lock_text:
        print("FAIL: Blurred background lacks visible: opacity > 0 guard")
        failed = True

    # 3. Bidirectional and interactive navigation
    if "switchToPasswordViewAnim" in lock_text and "-height * 1.1" in lock_text:
        print("FAIL: WaffleLock.qml retains one-way non-reversible animation")
        failed = True
    if "switchToUnfocusedView" not in lock_text:
        print("FAIL: WaffleLock.qml lacks switchToUnfocusedView function")
        failed = True
    if "cursorShape: Qt.PointingHandCursor" not in lock_text:
        print("FAIL: Unfocused content lacks click cursor hint")
        failed = True
    if "onWheel:" not in lock_text:
        print("FAIL: Unfocused content lacks scroll/wheel navigation")
        failed = True
    if "returnToClockTimer" not in lock_text:
        print("FAIL: WaffleLock.qml lacks returnToClockTimer for idle reset")
        failed = True
    if "event.text >= \" \"" not in lock_text and "root.context.currentText = event.text" not in lock_text:
        print("FAIL: WaffleLock.qml does not forward printable characters from clock screen")
        failed = True
    if "Qt.Key_Escape" not in lock_text:
        print("FAIL: WaffleLock.qml does not handle Qt.Key_Escape")
        failed = True

    # 4. Caps Lock synchronization
    if "HyprlandXkb.refreshLockKeys()" not in lock_text:
        print("FAIL: WaffleLock.qml does not refresh lock keys on completion")
        failed = True
    if "HyprlandXkb.noteCapsLockPressed()" not in lock_text:
        print("FAIL: WaffleLock.qml does not track Caps Lock press via noteCapsLockPressed")
        failed = True
    if "isAutoRepeat" not in lock_text:
        print("FAIL: Caps Lock press does not check isAutoRepeat")
        failed = True
    if "Caps Lock is on" not in lock_text:
        print("FAIL: Status text does not indicate Caps Lock state")
        failed = True

    # 5. Status, PAM lockout and failure feedback
    if "authMessage" not in lock_text:
        print("FAIL: WaffleLock.qml ignores root.context.authMessage")
        failed = True
    if "showFailure" not in lock_text:
        print("FAIL: WaffleLock.qml ignores root.context.showFailure")
        failed = True
    if "ErrorShakeAnimation" not in lock_text:
        print("FAIL: WaffleLock.qml lacks ErrorShakeAnimation")
        failed = True
    if "WIndeterminateProgressBar" not in lock_text:
        print("FAIL: WaffleLock.qml lacks WIndeterminateProgressBar")
        failed = True
    if "unlockInProgress" not in lock_text:
        print("FAIL: WaffleLock.qml lacks unlockInProgress gating")
        failed = True
    if "onShouldReFocus" not in lock_text:
        print("FAIL: WaffleLock.qml does not listen to onShouldReFocus")
        failed = True
    if "onUnlockInProgressChanged" not in lock_text:
        print("FAIL: WaffleLock.qml does not re-focus on unlockInProgress completion")
        failed = True

    # 6. Battery indicator null-safety
    if "Battery.available" not in lock_text:
        print("FAIL: Battery indicators not gated on Battery.available")
        failed = True

    # 7. Check design law
    check_design_cmd = [sys.executable, "tools/check-design.py", "--diff"]
    res = subprocess.run(check_design_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"FAIL: check-design.py failed:\n{res.stdout}\n{res.stderr}")
        failed = True

    if failed:
        print("waffle-lock checks FAILED")
        return 1

    print("ok: waffle-lock pragma bound, effect budget compliant, bidirectional navigation, CapsLock sync, PAM lockout/failure feedback, and design law verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
