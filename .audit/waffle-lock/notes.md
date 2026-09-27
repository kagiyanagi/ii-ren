# waffle-lock — notes

**Opening it.**
- Active under `Config.options.panelFamily: "waffle"`.
- Triggered by locking the session via `qs -c ii ipc call lock activate`, the global shortcut `Super+L` (`lock`), or `loginctl lock-session`.
- Previewable in a standalone window using `tools/audit/preview-lock.sh preview.png`.

**Measured and fixed.**
- **Bidirectional and reversible transitions:** Replaced the imperative `switchToPasswordViewAnim` (which animated `unfocusedContent.y` to `-height * 1.1` with no reset path) with declarative `Behavior on y` and `Behavior on opacity` across both `unfocusedContent` and `focusedContent`. Switching between ambient clock and password view is now fully reversible.
- **Interactive clock screen & character forwarding:** Added a full-screen `MouseArea` to `unfocusedContent` capturing clicks, taps, and mouse wheel scrolls. In `Keys.onPressed`, printable characters pressed on the clock screen are forwarded into `root.context.currentText`, eliminating swallowed initial keystrokes.
- **Escape navigation & idle timeout:** Added Escape key handling on `passwordInput` (clearing text if populated, or returning to clock view if empty) and introduced `returnToClockTimer` (15s inactivity reset to clock screen).
- **Caps Lock tracking & synchronization:** Added `HyprlandXkb.refreshLockKeys()` on creation and tracked toggles in `Keys.onPressed` via `HyprlandXkb.noteCapsLockPressed()`, skipping auto-repeats. Added visual Caps Lock status notification.
- **PAM lockout & error visibility:** Connected `root.context.authMessage` and `root.context.showFailure` to a dedicated status feedback row below the password field. Added the shared `ErrorShakeAnimation` targeting `passwordInputWrapper` on auth failure.
- **Unlock in progress feedback:** Integrated `WIndeterminateProgressBar` beneath the password box while `root.context.unlockInProgress` is true. Disabled input and submit buttons during verification, and automatically reclaimed active keyboard focus on completion or failure via `onUnlockInProgressChanged` and `onShouldReFocus`.
- **GPU effect budget compliance:**
  - Replaced the heavy full-screen `GaussianBlur` (`samples: 201`) with `FastBlur` (`radius: 64`, `visible: opacity > 0`).
  - Removed `layer.enabled: true` and `layer.effect: OpacityMask` on `passwordInputWrapper`, applying `bottomLeftRadius` and `bottomRightRadius` directly to `activeIndicatorLine`.
- **Battery indicator gating:** Gated battery icons on `Battery.available` in both ambient and focused views to prevent 0% ghost battery displays on desktops.
- **4dp spacing grid and design tokens:**
  - Corrected margins and spacings: `bottomMargin: 21` -> 24, `rightMargin: 31` -> 32, `spacing: 15` -> 16, `spacing: 3` -> 4, `margins: 6` -> 4, `implicitHeight: 22` -> 28.
  - Replaced raw `#000000` literal with `Appearance.colors.m3scrim`.
  - Annotated font sizes with design citations.

**Automated verification.**
- Created `tools/check-waffle-lock.py` asserting pragma bound declarations, GPU effect budget compliance, bidirectional navigation, CapsLock sync, PAM lockout/failure feedback, battery gating, and design law.
- Ran `python3 tools/check-waffle-lock.py` (passes).
- Ran `python3 tools/check-design.py --diff` (0 findings, 0 errors).
- Ran `python3 tools/check-effect-budget.py` (passes).
- Ran `python3 tools/check-lock.py` (passes).
