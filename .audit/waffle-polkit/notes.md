# waffle-polkit — notes

**Opening it.**
- Active under `Config.options.panelFamily: "waffle"`.
- Triggered whenever an application or CLI command requests elevated authorization via Polkit-1 (e.g. running `pkexec true`, or modifying system network settings).
- Testable with `pkexec true` or polkit test flows.

**Measured and fixed.**
- **Exit latching & smooth transitions:** Configured `holdForExit: true` on `WafflePolkit.qml` and connected `onClosed: root.release()`. Implemented `signal closed()` in `WPolkitContent.qml`, fired when the dialog and scrim have completed their accelerated exit transition (`!visible && !PolkitService.active`).
- **PAM lockout & failure feedback:** Added contextual feedback row below the password field. Captured `flow.supplementaryMessage` for PAM faillock lockout messages, surfaced "Incorrect password" on `onAuthenticationFailed`, and wired `ErrorShakeAnimation` targeting `dialog` on failure.
- **Caps Lock tracking & synchronization:** Added `HyprlandXkb.refreshLockKeys()` on creation and tracked toggles in `Keys.onPressed` via `HyprlandXkb.noteCapsLockPressed()`, skipping auto-repeats. Added visual Caps Lock status notification.
- **Flow message preservation:** Decoupled body message from transient `PolkitService.cleanMessage` via `root.capture()`, ensuring the dialog dimensions and message remain stable while exit animations run.
- **Desktop dimming scrim:** Replaced the full-screen wallpaper `StyledImage` and raw `#000000` rectangle with a transparent workspace scrim overlay using `Appearance.colors.m3scrim`, preserving the user's desktop context during authentication.
- **Focus & interaction management:** Handled focus transitions in `takeFocus()`, ensuring Escape key cancelation functions reliably even when `inputField` is disabled during PAM verification. Gated the "Yes" button on `PolkitService.interactionAvailable` to prevent duplicate submissions. Added `WIndeterminateProgressBar` during PAM processing.
- **4dp grid alignment & typography:**
  - Corrected dialog width: `implicitWidth: 434` -> 440dp.
  - Corrected spacings: `15` -> 16dp in header icon row, `18` -> 16dp in header title block.
  - Styled "Yes" button as Fluent accent button and "No" button with neutral background.
  - Added `pragma ComponentBehavior: Bound` across all files.

**Automated verification.**
- Created `tools/check-waffle-polkit.py` asserting pragma declarations, exit latching (`holdForExit`, `release()`), status line priority (PAM -> failure -> Caps Lock), message capture, interaction gating, CapsLock sync, scrim tokens, and 4dp grid alignment.
- Ran `python3 tools/check-waffle-polkit.py` (passes).
- Ran `python3 tools/check-polkit.py` (passes).
- Ran `python3 tools/check-design.py --diff` (0 findings, 0 errors).
