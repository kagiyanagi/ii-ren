# waffle-polkit — brief

**Purpose.** The privilege escalation dialog for the Waffle panel family (Windows 11 Fluent style). Presents a focused User Account Control (UAC) elevation prompt over a dimmed desktop scrim when an application or CLI command requests administrator authorization via Polkit-1.

**Primary action.** Authenticating privileged operations with a password (or confirmation), reviewing requesting application identity and action description, and dismissing/cancelling unrequested authorization attempts.

**Hierarchy.**
1. **Backdrop Scrim**:
   - Fullscreen overlay rectangle (`Appearance.colors.m3scrim`) dimming underlying workspace windows.
   - Click-to-dismiss `MouseArea` and scroll-absorbing `WheelHandler`.
2. **UAC Dialog Container (`WPane`)**:
   - Ambient shadow and fluent rounded borders (`Looks.radius.large`).
   - Titlebar Header (`PolkitDialogHeader`):
     - Dialog title ("Polkit" / UAC badge).
     - Action prompt ("Do you want to allow this app to make changes to your device?").
     - Top-right window `CloseButton` (32x32dp).
     - Titlebar `DragHandler` for window repositioning.
   - Body Section (`BodyRectangle`):
     - Requesting app icon (`WAppIcon`) and application name resolution (`DesktopEntries`).
     - Action message (`text: root.message`, copied from flow to survive flow teardown).
     - Credential input (`WTextField` with dynamic `TextInput.Password` or `TextInput.Normal` echo mode).
     - Indeterminate progress indicator (`WIndeterminateProgressBar`) active during PAM processing.
     - Contextual feedback status line displaying PAM lockout / faillock messages, "Incorrect password" alerts, or Caps Lock notifications with `FluentIcon`.
   - Action Footer (`BodyRectangle`):
     - Primary action button ("Yes", accent-styled `WButton`, gated on `PolkitService.interactionAvailable`).
     - Secondary action button ("No", neutral `colBackground: Looks.colors.bg1`, triggers `PolkitService.cancel()`).

**Reference.** Windows 11 User Account Control (UAC) elevation dialog adapted to Quickshell layer shell and ii-ren Fluent tokens (`.github/DESIGN.md`).

**What is wrong, measured.**
- **Immediate unlatched window unmap & skipped exit animation.** `WafflePolkit.qml` omitted `holdForExit: true` (defaulting to `false`) and had no `closed` signal connection to `root.release()`. The moment `PolkitService.active` transitioned to false, `FullscreenPolkitWindow` unmapped the Wayland layer surface on frame 0, snapping the dialog shut without playing any exit transition.
- **Invisible PAM lockout & authentication errors.** `WPolkitContent.qml` lacked any status row for authentication feedback. When authentication failed (`onAuthenticationFailed`), polkit restarted without notifying the user. If `faillock` locked the account, the PAM message (`flow.supplementaryMessage`) was never shown.
- **Untracked Caps Lock.** Caps Lock status was neither probed on creation nor tracked on keystrokes, providing zero feedback when Caps Lock was engaged.
- **Disappearing message & layout shift during exit.** The message text was bound directly to `PolkitService.cleanMessage`. Because the polkit flow is destroyed on the frame it finishes, `PolkitService.cleanMessage` emptied instantly, causing the dialog body to abruptly shrink by a line while animating out.
- **Window takeover with desktop wallpaper.** `WPolkitContent.qml` rendered a full-screen black rectangle (`#000000`) and a `StyledImage` decoding the wallpaper path. This obscured open user windows behind a fake desktop background instead of dimming the actual active workspace.
- **Off-grid metrics and hardcoded literals.**
  - `implicitWidth: 434` was off the 4dp grid (corrected to 440dp).
  - Spacings `15` and `18` were off the 4dp grid (corrected to 16dp).
  - Raw hex literal `"#000000"` used for root background and scrim.
- **Ungated submit button.** The "Yes" button remained active while PAM was verifying, allowing double-submissions.
- **Missing pragma declaration.** Missing `pragma ComponentBehavior: Bound`.

**Interaction.**
- Dialog scales down from 1.05 to 1.0 and fades in alongside the scrim using `Appearance.animation.elementMoveFast`.
- Clicking, pressing Escape, or clicking "No" / "Close" cancels authorization via `PolkitService.cancel()`.
- Typing password and pressing Enter or clicking "Yes" clears failure state and submits credentials via `root.submit()`.
- While PAM verifies credentials, input and submit controls are disabled, focus shifts to root so Escape remains responsive, and `WIndeterminateProgressBar` animates.
- On invalid credentials, the dialog executes `ErrorShakeAnimation` (`distance: 12`), sets `failed = true`, displays "Incorrect password", and refocuses the input field upon retry.
- On completion or cancel, the dialog and scrim scale and fade out smoothly; once invisible, `root.closed()` signals `FullscreenPolkitWindow` to release the Wayland surface.

**Edge states.**
- Account locked out: Displays PAM message with danger alert icon.
- Caps Lock active: Displays "Caps Lock is on" notification.
- Empty / non-password prompt: Displays clean prompt and standard input mode without password masking.
- Multi-screen: Hosted as an overlay layer surface on active screen.

**Cost.**
- Eliminates wallpaper decoding and offscreen image sampling during polkit dialog display.
- Uses standard elementMoveFast spatial and opacity animations without extra GPU passes.

**Delete.**
- `StyledImage` wallpaper background.
- Raw `#000000` color literals.
- Off-grid 434dp container width and 15dp/18dp spacings.

**Out of scope.**
- Modifying system PAM or polkit-1 daemon configurations.
