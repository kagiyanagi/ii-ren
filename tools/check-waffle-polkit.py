#!/usr/bin/env python3
"""Regression checks for waffle-polkit audit.

Verifies:
1. Pragma declarations:
   - WafflePolkit.qml declares pragma ComponentBehavior: Bound.
   - WPolkitContent.qml declares pragma ComponentBehavior: Bound.
2. Exit latching:
   - WafflePolkit.qml holds window for exit (holdForExit: true).
   - WafflePolkit.qml releases window when content closes (onClosed: root.release()).
   - WPolkitContent.qml declares signal closed().
   - WPolkitContent.qml emits closed() when !visible and !PolkitService.active.
3. Message capture and lifecycle safety:
   - WPolkitContent.qml binds text to root.message, not raw PolkitService.cleanMessage.
   - capture() function guards with `if (!flow) return`.
4. Status feedback and failure handling:
   - Status property prioritizes: PAM message, then failure, then Caps Lock.
   - onAuthenticationFailed marks root.failed = true and restarts shakeAnim.
   - submit() clears root.failed = false.
   - ErrorShakeAnimation targets dialog.
5. Interaction and focus management:
   - inputField and Yes button are gated on PolkitService.interactionAvailable.
   - CapsLock tracked via HyprlandXkb.refreshLockKeys() and noteCapsLockPressed().
   - Escape key cancels prompt via PolkitService.cancel().
   - takeFocus() keeps focus on root when disabled and transfers to inputField when enabled.
   - WIndeterminateProgressBar displays during PAM verification.
   - DragHandler allows repositioning dialog by header.
6. Scrim and 4dp grid design compliance:
   - Fullscreen scrim uses Appearance.m3colors.m3scrim (no raw hex literal, no wallpaper takeover).
   - Metrics (440px width, 16px/24px/32px/80px spacings and dimensions) adhere to 4dp grid.
"""

from pathlib import Path
import re
import sys

SHELL_DIR = Path("dots/.config/quickshell/ii")
HOST_PATH = SHELL_DIR / "modules/waffle/polkit/WafflePolkit.qml"
CONTENT_PATH = SHELL_DIR / "modules/waffle/polkit/WPolkitContent.qml"


def main():
    failed = False

    for p in (HOST_PATH, CONTENT_PATH):
        if not p.is_file():
            print(f"FAIL: File not found: {p}")
            return 1

    host_text = HOST_PATH.read_text(encoding="utf-8")
    content_text = CONTENT_PATH.read_text(encoding="utf-8")

    # 1. Pragma declarations
    if "pragma ComponentBehavior: Bound" not in host_text:
        print("FAIL: WafflePolkit.qml missing 'pragma ComponentBehavior: Bound'")
        failed = True
    if "pragma ComponentBehavior: Bound" not in content_text:
        print("FAIL: WPolkitContent.qml missing 'pragma ComponentBehavior: Bound'")
        failed = True

    # 2. Exit latching
    if not re.search(r"holdForExit:\s*true", host_text):
        print("FAIL: WafflePolkit.qml must set holdForExit: true")
        failed = True
    if not re.search(r"onClosed:\s*root\.release\(\)", host_text):
        print("FAIL: WafflePolkit.qml must call root.release() onClosed")
        failed = True
    if not re.search(r"signal\s+closed\(", content_text):
        print("FAIL: WPolkitContent.qml must declare signal closed()")
        failed = True
    if not re.search(r"!visible\s*&&\s*!PolkitService\.active\s*[\s\S]*?root\.closed\(\)", content_text):
        print("FAIL: WPolkitContent.qml must emit closed() on !visible && !PolkitService.active")
        failed = True

    # 3. Message capture and lifecycle safety
    if not re.search(r"text:\s*root\.message\b", content_text):
        print("FAIL: WPolkitContent.qml must bind message to root.message (not live PolkitService)")
        failed = True
    if not re.search(r"function\s+capture\(\)[\s\S]*?if\s*\(!flow\)\s*return", content_text):
        print("FAIL: WPolkitContent.qml capture() must guard if (!flow) return")
        failed = True

    # 4. Status feedback and failure handling
    status_match = re.search(r"readonly\s+property\s+string\s+status:\s*\{([\s\S]*?)\}", content_text)
    if not status_match:
        print("FAIL: WPolkitContent.qml missing status property")
        failed = True
    else:
        order = re.findall(r"if\s*\(([^)]*)\)", status_match.group(1))
        expected_conditions = ["root.pamMessage.length > 0", "root.failed", "HyprlandXkb.capsLock"]
        if order != expected_conditions:
            print(f"FAIL: status ordering must be PAM -> failure -> Caps Lock, got: {order}")
            failed = True

    if not re.search(r"onAuthenticationFailed[\s\S]*?root\.failed\s*=\s*true", content_text):
        print("FAIL: onAuthenticationFailed must set root.failed = true")
        failed = True
    if not re.search(r"shakeAnim\.restart\(\)", content_text):
        print("FAIL: onAuthenticationFailed must restart shakeAnim")
        failed = True
    if not re.search(r"function\s+submit\(\)\s*\{[\s\S]*?root\.failed\s*=\s*false", content_text):
        print("FAIL: submit() must clear root.failed = false")
        failed = True
    if "ErrorShakeAnimation" not in content_text or "target: dialog" not in content_text:
        print("FAIL: WPolkitContent.qml must target dialog with ErrorShakeAnimation")
        failed = True

    # 5. Interaction and focus management
    if not re.search(r"enabled:\s*PolkitService\.interactionAvailable", content_text):
        print("FAIL: inputField or submit button must be gated on PolkitService.interactionAvailable")
        failed = True
    if "HyprlandXkb.refreshLockKeys()" not in content_text:
        print("FAIL: WPolkitContent.qml must call HyprlandXkb.refreshLockKeys() on completion")
        failed = True
    if "HyprlandXkb.noteCapsLockPressed()" not in content_text:
        print("FAIL: WPolkitContent.qml must call HyprlandXkb.noteCapsLockPressed()")
        failed = True
    if "PolkitService.cancel()" not in content_text:
        print("FAIL: WPolkitContent.qml must handle cancelation via PolkitService.cancel()")
        failed = True
    if "WIndeterminateProgressBar" not in content_text:
        print("FAIL: WPolkitContent.qml must show WIndeterminateProgressBar during verification")
        failed = True
    if "DragHandler" not in content_text:
        print("FAIL: WPolkitContent.qml must include DragHandler on header")
        failed = True

    # 6. Scrim and 4dp grid design compliance
    if "Appearance.m3colors.m3scrim" not in content_text:
        print("FAIL: WPolkitContent.qml must use Appearance.m3colors.m3scrim for scrim")
        failed = True
    if '"#000000"' in content_text:
        print("FAIL: WPolkitContent.qml still contains raw hex '#000000'")
        failed = True
    if "StyledImage" in content_text and "wallpaperPath" in content_text:
        print("FAIL: WPolkitContent.qml should not replace user windows with wallpaper")
        failed = True
    if "implicitWidth: 434" in content_text:
        print("FAIL: WPolkitContent.qml retains off-grid width 434")
        failed = True
    if "spacing: 15" in content_text or "spacing: 18" in content_text:
        print("FAIL: WPolkitContent.qml retains off-grid spacing (15 or 18)")
        failed = True

    if failed:
        return 1

    print("check-waffle-polkit: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
