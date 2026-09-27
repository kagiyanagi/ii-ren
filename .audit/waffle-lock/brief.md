# waffle-lock — brief

**Purpose.** The full-screen session lock surface for the Waffle family (Windows 11 Fluent style). Presents an initial ambient lock screen with a large display clock, current date, and system status indicators (network, battery), and transitions to a focused credential entry screen with avatar, username, password field, PAM feedback, Caps Lock notifications, and power controls.

**Primary action.** Entering user credentials to unlock the Wayland session; reviewing system status and power operations (shut down, restart) from the lock screen.

**Hierarchy.**
1. **Background Layer**:
   - `StyledImage`: Opaque wallpaper image covering the output screen.
   - `FastBlur`: Optimized acrylic backdrop blur with depth scaling entering on demand (`radius: 64`, `scale: 1.05`, `visible: opacity > 0`).
2. **Unfocused / Ambient Clock View**:
   - Display clock (`font.pixelSize: 132`, strong weight) and date header (`DateTime.collapsedCalendarFormat`).
   - Bottom-right status indicators: Wi-Fi/Ethernet (`WIcons.internetIcon`) and battery status (`WIcons.batteryLevelIcon`, gated on `Battery.available`).
   - Interactive dismiss surface: full-screen `MouseArea` responding to click, tap, scroll, and keypress gestures.
3. **Focused / Password View**:
   - User profile group: `WUserAvatar` (144x144dp) and username header (`SystemInfo.username`).
   - Password box: `passwordInputWrapper` with rounded borders, active indicator line, `WTextInput`, visibility toggle eye button, and submit arrow button.
   - Error & status row: horizontal shake micro-interaction on failure (`ErrorShakeAnimation`), indeterminate progress bar (`WIndeterminateProgressBar`), and context-aware feedback label displaying PAM lockout notifications (`root.context.authMessage`), incorrect credentials (`showFailure`), or Caps Lock status (`HyprlandXkb.capsLock`).
   - Bottom-right control cluster: network, battery, and session power actions (`SessionScreen.PowerButton`).

**Reference.** Windows 11 Lock and Sign-in experience adapted to Quickshell layer shell and ii-ren Fluent tokens (`.github/DESIGN.md`).

**What is wrong, measured.**
- **One-way non-reversible view transition & stuck blank screen.** `switchToPasswordViewAnim` drove `unfocusedContent.y` to `-height * 1.1` via a one-way script animation without any restoration path. Resetting `passwordView = false` (e.g. on idle timeout or escape) left the ambient clock permanently stranded offscreen.
- **Unresponsive clock screen.** Only `Keys.onPressed` triggered view switching. Clicking, tapping, dragging, or scrolling with the mouse had zero effect.
- **Swallowed first keystroke.** Pressing a character key on the clock screen triggered `switchToFocusedView()` but discarded the key event without appending it to `root.context.currentText`, causing the user's initial password character to be lost.
- **Invisible PAM lockout & error messages.** PAM faillock lockout messages (`root.context.authMessage`) and invalid credential failures (`root.context.showFailure`) were completely omitted from the UI. An account locked out by faillock displayed zero notice, leaving users baffled when correct passwords failed.
- **Untracked Caps Lock.** Caps Lock was neither probed on surface initialization nor tracked on keypress events. The user received no visual notification when Caps Lock was engaged.
- **Missing unlock-in-progress feedback.** During PAM verification, no progress indicator appeared and the field remained superficially interactive. On authentication failure or completion, the password field lost active keyboard focus.
- **Expensive GPU overhead and effect budget violations.**
  - `GaussianBlur` computed 201 samples (`samples: radius * 2 + 1`) over the entire screen on every frame, even when `opacity: 0` because `visible` was not gated.
  - `passwordInputWrapper` enabled `layer.enabled: true` and an offscreen `OpacityMask` pass solely to clip the bottom corners of a 2px active indicator line.
- **Off-grid design metrics and hardcoded literals.**
  - Durations `350`, `400`, `250` were hardcoded numbers without animation tokens.
  - Margins and spacings `21`, `31`, `15`, `3`, `6` were off the 4dp grid.
  - Raw hex literal `"#000000"` used in background scrim.
  - Battery indicator showed on desktop machines lacking batteries.

**Interaction.**
- Clicking, scrolling up, or typing on the ambient clock screen transitions to the password entry screen, automatically forwarding any typed printable character.
- Typing in the password field updates `root.context.currentText`. Pressing Enter or clicking the submit button verifies credentials via `root.context.tryUnlock()`.
- Pressing `Escape` clears text if non-empty, or returns to the ambient clock screen if empty.
- 15 seconds of inactivity in the password screen automatically transitions back to the ambient clock screen.
- On invalid credentials, the password box shakes horizontally and displays an error message.
- Clicking the power button presents options to shut down or restart the system.

**Edge states.**
- Account locked out: PAM lockout message ("The account is locked due to failed logins...") is presented prominently in danger red below the field.
- Caps Lock active: "Caps Lock is on" notification is displayed with an icon.
- Desktop without battery: Battery indicator is safely hidden via `Battery.available`.
- Multi-screen setup: `root.passwordView` and `root.context.currentText` synchronize across all monitor outputs.

**Cost.**
- Eliminates the 201-sample full-screen `GaussianBlur` shader pass, replacing it with `FastBlur` gated on `visible: opacity > 0`.
- Eliminates offscreen `layer.enabled` and `OpacityMask` framebuffer passes on the password box.
- Eliminates lost keystrokes and stuck off-screen states.

**Delete.**
- Redundant `SequentialAnimation id: switchToPasswordViewAnim`.
- Redundant `transform: Translate` and custom 6-leg shake animations (replaced by shared `ErrorShakeAnimation`).
- Offscreen `layer.enabled` and `OpacityMask` on `passwordInputWrapper`.

**Out of scope.**
- Modifying underlying Linux PAM daemon configurations or Hyprland session lock protocols.
