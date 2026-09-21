# ii-lock — brief

**Purpose.** Get the owner back into a session that is already theirs, and prove to
everyone else that they cannot. It is the one surface in the shell that is *also* a
security boundary, so "does it survive the shell dying" ranks above how it looks.

**Primary action.** Type the password (or put a finger on the reader) and get back in.
Everything else on the surface — who is logged in, layout, battery, sleep, power, reboot
— is secondary and must look it.

**Hierarchy.** The desktop's own clock widget, seen through the transparent lock surface,
is what the eye hits first; the lock surface does not draw one and must not start. Second
is the centre island: fingerprint state, password field, and the single `colPrimary`
circle that is the only saturated thing on screen. Third, the two flanking islands —
identity on the left, power on the right — in `colOnSurfaceVariant`, same height, never
tinted.

**Reference.** The Android 16 lock screen's bottom row: the entry sits on the bottom
edge under a clock that owns the top two thirds, with the utility affordances pushed into
the corners. The split-island arrangement is this shell's own dialect of that and stays.

**Interaction.**
- Surface enter: the three islands scale `0.9 → 1` on `elementMoveEnter` and fade in on
  `elementMoveFast`, staggered by `staggerStep` from the centre outwards.
  `transformOrigin: Item.Bottom` on all three — they are anchored to the screen edge, so
  they grow out of it (2.6).
- Surface exit: the mirror, on `elementMoveExit`, and it must actually run. Today the
  session lock is released on the same frame the password lands, which deletes the exit
  outright; the compositor holds the lock for the exit's length instead, and only then
  does `screenLocked` flip and the wallpaper start its own un-zoom. Intent and mechanism
  stay apart for the same reason the cheatsheet keeps them apart.
- Unlock in progress: PAM takes a visible beat, and on a wrong password it takes two
  seconds. The confirm circle carries `MaterialLoadingIndicator` while it thinks.
- Failure: the existing `ErrorShakeAnimation` on the field and on the fingerprint icon.
- Every button is a `ToolbarButton`/`IconToolbarButton`, so all four states come from
  `RippleButton`. The field gets hover and focus from `ToolbarTextField`'s `StateOverlay`.
- Keyboard: every keypress anywhere goes to the field; Escape clears it. Nothing here
  closes, so Escape has no other job.

**Told, not guessed.** Two things stop a correct password from working, and the surface
said nothing about either — it shook and printed "Incorrect password" in both cases.

- *Caps Lock.* Hyprland reports it in `hyprctl devices` and announces it nowhere, so the
  surface asks: once on the way up, and on the Caps Lock key itself, which is the only
  other moment the answer can change while anyone is looking.
- *The account being locked out.* After `deny` wrong passwords `pam_faillock` refuses the
  next ones before `pam_unix` ever sees them, and says so through the PAM conversation as
  **info, not error**. Nothing was reading it.

Both land in one status chip above the centre island, PAM first, because a lockout
outranks a hint: error container for PAM, neutral for Caps Lock, a pill while it is one
line and a card once it wraps. It grows out of the island it is about and leaves on the
exit spec, like everything else here.

**Edge states.**
- *Fingerprint absent or not enrolled* — the indicator's `Loader` is inactive and the
  island shrinks to field + confirm. Unchanged.
- *Fingerprint spent* — `fingerprint_off`, dots red, reader left alone. Unchanged.
- *A power action armed* — the confirm icon already swaps to `power_settings_new` /
  `restart_alt`, but the field still says "Enter password", which is the one place the
  surface lies about what Enter will do. The placeholder names the action instead.
- *Wrong password* — placeholder becomes "Incorrect password", field shakes, text clears.
- *Locked out* — the chip carries PAM's own two sentences, including its countdown. It
  survives the ten-second idle reset, because the reason the screen will not open should
  outlast looking away from it, and goes when the next attempt starts.
- *The shell died while the screen was locked* — the compositor keeps the session locked
  and shows its own crash screen, forever, with no way back short of a TTY. This is the
  state the row exists for. The shell records that the session is locked, and a shell
  that starts up under the same Hyprland instance with that flag set takes the session
  back on the spot. `misc:allow_session_lock_restore` is what the compositor needs for
  that to be allowed, and nothing in this repo asserted it was still on.
- *Re-locked after a restart* — the lock's workspace shuffle finds the temp workspace
  already active and its saved map gone. It must not save the temp id as the one to
  return to, or unlocking drops the user on an empty workspace with every window
  somewhere else.

**Cost.** One effect on the surface: the `OpacityMask` that clips the field's contents to
its pill, kept because the shape chars have to be clipped to a curve a rectangular `clip`
cannot follow. `MaterialLoadingIndicator` is chosen over `CircularProgress` because the
latter is the shared tranche's only `layer.enabled`, and it lives behind a `Loader` that
is inactive except while PAM is working. Nothing repeats except the fingerprint attempt
dots (3) and the password chars, and neither carries an effect.

**Delete.** `active` and `showInputField` (nothing has ever set or read either), the
`Behavior` on a `bottomMargin` that is a constant, the two `Loader`s around the keyboard
layout row that are unconditionally active, and `lock.centerClock` — a config key no file
in the repo reads.

**Out of scope.** The lock *screen* content that belongs to the desktop plane (clock,
media, notification widgets and their drag proxies — vendored, see the re-port hazard),
`LockContext`'s PAM and fingerprint logic beyond what the surface shows, `waffle-lock`,
and `settings-LockConfig`. The two shared-file changes this row does make — the exit
hold and the crash recovery — are in `modules/common/panels/lock/LockScreen.qml`
deliberately: both failures belong to every panel family, not to ii.
