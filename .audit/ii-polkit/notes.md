# ii-polkit — notes

**How to drive it.** No IPC. `pkexec true &` raises a real prompt. `wtype` reaches
the field without a click (`OnDemand` focus lands on map), and Esc closes it.

**Every test prompt costs a faillock entry.** Cancelling (Esc, Cancel, a press on the
scrim, or killing `pkexec`) ends the PAM conversation with an error, and
`pam_faillock authfail` records it exactly as it records a wrong password. The tally is
per user and shared with the lock screen and `sudo`. On this machine `deny` is the
default 3 and `unlock_time` is 10 seconds, so the worst case is a 10s lockout. Still,
`faillock --user ren` before a run, and a wrong-password test costs **two** entries: the
failure, then the cancel after it.

**`wtype` pitfalls here.**
- `wtype -k Caps_Lock` inserts characters into the field through its virtual keymap. The
  Caps Lock *line* still shows, because the field's key handler sees `Key_CapsLock`, but
  the password text is garbage afterwards.
- Key events sent after the dialog has closed go to whatever window is focused. During
  this row one reached ghostwriter, which autosaves, and wrote a stray `q` into
  `.audit/FINDINGS.md`. It was restored from git. Do not send keys you cannot see land.

## What was wrong

1. **No exit, ever.** The `AuthFlow` is deleted on the frame it completes, which is when
   `PolkitAgent.isActive` goes false. `FullscreenPolkitWindow`'s `Loader` was bound to
   it, so success and cancel both unmapped on that frame. It is now latched
   (`rendered`, set on the edge, never bound; see `check-osk.py` for why not `||`) and
   released by the content once `WindowDialog` has collapsed. Measured: the layer is
   gone 133ms after Esc; `wtype` plus one `hyprctl` poll takes ~30ms here, so ~100ms is
   the dialog's own collapse (`elementMoveFast` / 2). **Success was not measured** because
   it needs the real password. It goes through the same edge.
2. **A wrong password said nothing.** polkit reports it only as `authenticationFailed`
   and restarts the session itself. The field just cleared. There is a status line now,
   in the lock screen's order: PAM, then the failure, then Caps Lock. Seen live:
   "Incorrect password" in `colError` after one wrong attempt, and "Caps Lock is on".
   Not seen live: faillock's lockout text. Reaching it takes three entries inside 10s.
3. **The field was live before PAM asked for anything.** `interactionAvailable` was
   written by hand on request start and on failure, and both come before the session's
   `request`. It is `flow.isResponseRequired` now. Seen live: the field and OK disable
   on submit and come back on the retry.
4. **Two scrims and a 0×0 dialog.** The content drew its own scrim `Rectangle` and
   centred a `WindowDialog` (itself a scrim) in a 0×0 box, so the dialog's Esc handler
   and outside-press dismiss covered nothing. There were also two hand-written Esc
   handlers. The dialog fills the window now and is the only scrim. `radius: 0`, because
   the rounded radius is meant for dialogs inside a sidebar.
5. **`WindowDialog` could not grow.** Its default `backgroundHeight` read the card's own
   `implicitHeight`, which `onShowChanged` overwrote with a snapshot. A row that appeared
   while the dialog was shown was laid out past the card's bottom, and a reused dialog
   reopened at zero. Now the default is the content's height and the shown height is bound
   to it. Probe (`qs -p`, default height): 149 shown, 205 after a row appears, 0 closed,
   205 reopened without a `Loader`. The five callers that set a fixed height behave exactly
   as before. `KeybindEditor` gains from this: its conflict row and its exec/global fields
   toggle while it is shown.

`tools/check-polkit.py` covers all five. All 15 asserts fire against the pre-row code.

## For the cohesion pass (60fps)

- **Default-height `WindowDialog` exits** (`KeybindEditor`, the Hermes vault
  remove-confirm, polkit). Their `targetY` used to follow the collapsing height, so the
  card shrank toward its centre. `backgroundHeight` is the content's height now, so it
  stays put during the exit and the card collapses upward while rising 60px. That is how
  the five fixed-height dialogs already left. Watch for whether it reads worse.
- **A row appearing in a shown dialog.** The card grows on `elementMoveFast`, and for that
  window the `ColumnLayout` is shorter than its content and squeezes the rows. Watch
  polkit's status line arriving after the ~2s failure delay.
- **The full-screen scrim's fade is cut** at the 100ms collapse by `WindowDialog`'s
  `visible: height > 0`. It is ~90% through its curve by then. This is the largest scrim
  that does this.

## Deliberately not done

- **Identity choice.** polkit offers every wheel member and preselects the first. Wheel is
  `ren` alone here, so nothing is shown. On a machine with several admins, the first may
  not be the person at the keyboard.
- **Multi-monitor.** `Variants` puts a dialog, with its own field, on every screen. This
  machine has one screen, so which field gets keyboard focus is unmeasured.
- **Stale PAM text.** Quickshell never clears `supplementaryMessage`, so with pam_fprintd
  in the stack a leftover "place your finger" would outrank "Incorrect password". No
  fprintd here.
- **Waffle.** `FullscreenPolkitWindow.holdForExit` defaults false, so `WPolkitContent` is
  unchanged. `waffle-polkit` can opt in with the same `closed` → `release()` pair.
- **The scrim press cancels.** This follows `WindowDialog` and BiometricPrompt, but like
  Esc it records a faillock entry. If stray clicks turn out to matter, stop wiring
  `onDismiss` for outside presses only. That needs `WindowDialog` to tell the two apart,
  and today it cannot.
