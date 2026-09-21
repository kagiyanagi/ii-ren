# ii-lock — notes

## The thing this row is actually about

A session lock outlives the process holding it. `pkill qs; qs -c ii` with the screen
locked leaves Hyprland holding a lock whose client is gone, so it puts up its own crash
screen — no password reaches it, no keybind dismisses it, and the documented way out is a
TTY. That is what the user reported, and it is the reason this row ran lane 1.

Three parts, and **all three are needed**; any one alone does nothing:

1. `misc:allow_session_lock_restore = true` in `hyprland/general.lua`. Already set here,
   which is luck rather than design — nothing in the repo asserted it. Hyprland's
   `CSessionLockManager::onNewSessionLock` answers `sendDenied()` without it, and says so
   only in its own debug log.
2. `Persistent.states.lock.locked`, written on **both** edges of `GlobalStates.screenLocked`.
   Nothing in Hyprland's IPC answers "is this session locked" — `hyprctl` has no such
   query in 0.56.2 — so the shell has to have written it down.
3. `LockScreen.initIfReady()` re-locking when that flag is set **and** the Hyprland
   instance signature is unchanged.

`tools/check-lock.py` asserts all three, plus the workspace arithmetic below.

### What is proven, and what is not

**Proven on this machine** (2026-09-21): a lock client killed with `kill -9` leaves the
session locked, and a *new* quickshell `WlSessionLock` takes it over and can then unlock
it. Two throwaway `qs -p` configs, no password needed, fallback to `hyprlock` if the
takeover were denied. That was the only genuinely unknown half — the protocol allows a
compositor to refuse, and Hyprland does refuse by default.

**Not proven end to end**: the shell's own half. Testing it means locking the real screen
and typing the real password, which the user declined for this session. The manual test,
for whoever has two minutes:

```sh
# lock, then kill the shell holding the lock
qs -c ii ipc call lock activate
pkill -x qs                     # from a TTY, or a keybind, or over ssh
qs -c ii                        # expect: the lock screen comes back, not the crash screen
```

If it fails: Hyprland's crash screen is up and the only way back is a lock client that is
allowed to take over — `hyprlock` from a TTY works and is installed here.

### Stale flag, deliberately

Kill the shell between the unlock and the 100 ms `writeAdapter` debounce, or unlock some
other way while the shell is dead, and the flag is stale — the next start locks a screen
that did not need locking. That is the direction the failure has to fall: the alternative
is a crash screen you cannot dismiss. Nothing else can tell us, so it was not narrowed.

### The side effect worth knowing

A QML live reload re-runs `initIfReady()`. If a reload ever drops `GlobalStates.screenLocked`
while the compositor still holds the lock, the recovery re-locks on the same frame. Whether
quickshell preserves that singleton across a reload was not tested (again: it needs a real
lock), but the recovery covers it either way.

## The parked workspace

Locking parks every monitor on `INT32_MAX - ws` so no window sits behind the transparent
lock surface, and keeps the map in `Lock.savedWorkspaces` — in memory. A shell that
restarts under a lock re-runs that handler on a monitor that is *already* parked, with the
map gone. Left alone it would have saved the parked id as the one to return to, and
unlocking would have dropped the user on an empty workspace with every window on another.
The mirror is its own inverse, so the fix is arithmetic and needs nothing persisted;
`check-lock.py` sweeps it, because a desktop that locks once exercises none of it.

## Looking at this surface at all

Nothing can screenshot a locked session, and only the password ends one, so
`tools/audit/preview-lock.sh out.png [timeout] [setup-js]` puts `LockSurface` in an
ordinary window over a dark backdrop and grabs it. The `setup-js` argument runs against
the preview's `LockContext`, which is how the states that need PAM to answer were looked
at without PAM:

```sh
tools/audit/preview-lock.sh busy.png 20 'previewContext.unlockInProgress = true'
tools/audit/preview-lock.sh armed.png 20 'previewContext.targetAction = 1'   # Poweroff
```

`shot-before.png` / `shot-after.png` come from it. It is also how the `SysTray` error
below was found — a defect of this surface that never appears in its own directory.

## Found by the preview, fixed outside this directory

- `modules/ii/bar/SysTray.qml` calls `rootItem.toggleVisible(...)`, where `rootItem` is
  `BarComponent`'s id. The lock screen uses the tray outside a `BarComponent` (the Fcitx
  indicator), so every tray change while locked threw `ReferenceError: rootItem is not
  defined` and took the `closeOverflowMenu()` below it down too. Guarded with the same
  `typeof` test `NetworkSpeed.qml` already uses.
- `Config.options.lock.centerClock` was read by no file in the repo (anti-pattern 16) and
  is deleted, from `Config.qml` and from the shipped `config.json`.

## Motion to watch in the cohesion pass

- The three islands enter staggered by `staggerStep` from the centre out, growing from
  `Item.Bottom`. Measure the stagger reads as choreography rather than lag at 60fps.
- Unlock now holds the compositor's lock for `elementMoveExit.duration` (130ms) before
  releasing it, so the islands can shrink and the surface fade. Watch that the dead time
  between a correct password and a usable desktop does not read as sluggish; the wallpaper
  un-zoom (`Background.qml`) starts after it, which is the intended order but adds to the
  total.

## Deliberately not done

- **No exit animation for a password char.** Backspace has to read as immediate, and
  deferring the `ListModel.remove` to animate it out means holding leaving rows, cancelling
  them when the user retypes, and a model that no longer matches the field. The enter (the
  M3E shape pop-in) is tokenised; the exit is instant by design, which is the one place
  this surface does not follow rule 4.
- **No caps-lock indicator.** There is no source for it: Hyprland emits no event, and
  `hyprctl devices` would have to be polled. Qt only sees the key press, which is not the
  state.
- The split-island layout was left alone. It is the shell's dialect of the Android 16
  bottom row and the redesign budget went on the failure modes instead.
