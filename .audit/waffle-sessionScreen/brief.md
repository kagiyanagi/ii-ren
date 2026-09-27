# waffle-sessionScreen — brief

**Purpose.** The fullscreen session security options overlay (Windows 11 Ctrl+Alt+Delete style) for the Waffle panel family. Presents quick actions to lock the session, sign out, change user password, launch the task manager, cancel, or execute system power state transitions (sleep, shut down, restart).

**Primary action.** Triggering a session management action (Lock, Sign out, Change password, Task Manager) or system power operation, or dismissing the screen to return to the active workspace.

**Hierarchy.**
1. **Backdrop Scrim**:
   - Fullscreen transparent window (`color: "transparent"`) with `Appearance.colors.m3scrim` dimming background windows.
   - Click-to-dismiss `MouseArea` and scroll-absorbing `WheelHandler`.
2. **Central Action Column (`centralContainer`)**:
   - Centered vertical action buttons with subtle enter/exit scale (`1.0` ↔ `0.96`) and opacity transitions:
     - **Lock** (`Session.lock()`)
     - **Sign out** (`Session.logout()`)
     - **Change password** (`Session.changePassword()`)
     - **Task Manager** (`Session.launchTaskManager()`)
     - **Cancel** (`cancelButton`, bordered pill button, closes session screen)
3. **Bottom-Right System Controls**:
   - `PowerButton` triggering Fluent `WMenu` positioned above the button with capability-gated options:
     - **Sleep** (`Session.suspend()`, gated on `SessionWarnings.can("CanSuspend")`)
     - **Shut down** (`Session.poweroff()`, gated on `SessionWarnings.can("CanPowerOff")`)
     - **Restart** (`Session.reboot()`, gated on `SessionWarnings.can("CanReboot")`)

**Reference.** Windows 11 Ctrl+Alt+Delete security options screen adapted to Quickshell layer shell and ii-ren Fluent tokens (`.github/DESIGN.md`).

**What is wrong, measured.**
- **Immediate unlatched surface unmap & skipped exit animation.** `WaffleSessionScreen.qml` bound `Loader.active: GlobalStates.sessionOpen`. When `sessionOpen` became false, the `PanelWindow` was destroyed immediately on frame 0. Because `rules.lua` specifies `no_anim = true` for `quickshell:session`, the surface snapped out abruptly with zero exit animation.
- **Broken keyboard navigation.** In `SessionScreenContent.qml`, `taskManagerButton` had `KeyNavigation.up: signOutButton`, completely skipping `changePasswordButton` when navigating up.
- **Double-activation vulnerability.** Buttons directly invoked actions and toggled `sessionOpen = false` without an execution guard, allowing repeated keypresses during exit transitions to fire multiple actions.
- **Ungated power actions & missing Sleep option.** `PowerButton.qml` only offered "Shut down" and "Restart", omitting "Sleep". Actions directly executed commands without checking logind capabilities (`SessionWarnings.can(...)`), failing to disable unavailable actions on machines lacking suspend/reboot capabilities.
- **Hardcoded hex colors & pitch-black screen.** `WaffleSessionScreen.qml` set `PanelWindow.color: "#000000"`, causing a jarring pitch-black frame without transparency or backdrop fading. Focus rings in `WSessionScreenTextButton.qml` and `SessionScreenContent.qml` used hardcoded `#ffffff` hex literals.
- **Off-grid metrics across all components.**
  - `CancelButton`: `Layout.leftMargin: 5`, `Layout.rightMargin: 5`, `Layout.topMargin: 38`, focus ring `margins: -3`.
  - Power button cluster: `bottomMargin: 21`, `rightMargin: 31`.
  - `WSessionScreenTextButton`: `implicitWidth: 135`, `horizontalPadding: 5`.
- **Missing pragma declarations.** Missing `pragma ComponentBehavior: Bound` in `WaffleSessionScreen.qml`, `SessionScreenContent.qml`, and `PowerButton.qml`.

**Interaction.**
- The overlay maps as an overlay layer surface on the focused monitor with exclusive keyboard focus.
- On enter, the backdrop scrim fades in while the central options scale up from `0.96` to `1.0` with `Appearance.animation.elementMoveFast`. Initial focus is explicitly directed to the "Lock" button.
- Pressing Escape, clicking the backdrop scrim, or activating "Cancel" smoothly begins the exit animation.
- Clicking or pressing Enter on an action runs `run(action)` which immediately locks out double-activation (`if (!GlobalStates.sessionOpen) return;`), flips `GlobalStates.sessionOpen = false`, and executes the action.
- The Wayland overlay surface remains mapped until the exit animation completes, at which point `SessionScreenContent` emits `closed()`, releasing the latched `root.rendered` state. If reopened mid-exit, the surface stays mapped and animates back in.

**Edge states.**
- Screen locked externally: Automatically closes the session screen when `GlobalStates.screenLocked` is detected.
- Power capability restrictions: Disables Sleep, Shut down, or Restart if `SessionWarnings.can(...)` reports `no` or `na`.
- Lock screen reuse: `PowerButton.qml` is shared with `WaffleLock.qml`, cleanly running power actions whether `sessionOpen` is true or false.

**Cost.**
- Replaces raw `#000000` window fill with transparent window and scrim rectangle, ensuring zero compositor tearing.
- Uses standard property animations for opacity and scale on `elementMoveFast` / `elementMoveExit` without additional render passes.

**Delete.**
- Raw `#000000` window color and raw `#ffffff` focus ring colors.
- Off-grid margins `5`, `21`, `31`, `38` and off-grid dimensions `135`.
- Unused `subtitle` property in `WaffleSessionScreen.qml`.

**Out of scope.**
- System logind or systemd-logind policy changes.
