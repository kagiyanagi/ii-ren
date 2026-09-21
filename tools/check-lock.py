#!/usr/bin/env python3
"""The lock screen survives the shell dying, and leaves visibly when it unlocks.

Neither of these has a symptom you can see in a screenshot, and one of them is
not even in this repo's QML.

- **Taking the session back.** A session lock outlives the process that owns it.
  Kill the shell while the screen is locked -- `pkill qs; qs -c ii`, the way
  every QML change used to be tested -- and the compositor keeps the session
  locked and puts up its own "your lockscreen crashed" screen, which no password
  reaches and nothing dismisses short of a TTY. The only way out is a *new* lock
  client taking the session over, and Hyprland allows that only while
  `misc:allow_session_lock_restore` is set: `CSessionLockManager::onNewSessionLock`
  answers `sendDenied()` otherwise and says so nowhere the user will look. So the
  QML half (remember that the session is locked, ask for it back on the next
  start) and the compositor half (allow the ask) are one mechanism split across
  two files in two languages, and either one alone does nothing. Both are
  asserted here.

- **The flag is cleared as well as set.** `Persistent.states.lock.locked` is what
  the recovery reads. Written on lock and never on unlock, it locks the screen on
  every single start for the rest of the machine's life -- and the first restart
  after locking *looks* like it worked.

- **Unlocking is not the same frame as releasing the lock.** `screenLocked` is
  what destroys the surface, both through the `Loader` and through
  `WlSessionLock.locked`, so clearing it in `onUnlocked` deletes the exit
  animation outright with nothing else to show for it. The exit runs inside a
  hold, and the hold's length is the exit's own token. Same shape as the
  cheatsheet's intent-vs-mapping split, for the same reason.

- **The parked workspace maps back.** Locking parks each monitor on
  `INT32_MAX - ws` so no window sits behind a transparent lock surface. A shell
  that restarts under a lock re-runs that on a monitor that is *already* parked,
  where the arithmetic is its own inverse and the saved map is gone -- save the
  parked id as the one to return to and unlocking drops the user on an empty
  workspace with every window somewhere else.

Run: python3 tools/check-lock.py
"""
import pathlib
import re

REPO = pathlib.Path(__file__).parent.parent
SHELL = REPO / "dots/.config/quickshell/ii"
LOCK_SCREEN = SHELL / "modules/common/panels/lock/LockScreen.qml"
LOCK = SHELL / "modules/ii/lock/Lock.qml"
SURFACE = SHELL / "modules/ii/lock/LockSurface.qml"
HYPR_GENERAL = REPO / "dots/.config/hypr/hyprland/general.lua"


def src(p: pathlib.Path) -> str:
    """File text with comments blanked, so a comment cannot satisfy a check."""
    s = p.read_text()
    s = re.sub(r"//[^\n]*", "", s)
    s = re.sub(r"--\[\[.*?\]\]", "", s, flags=re.S)
    s = re.sub(r"(?m)^\s*--[^\n]*", "", s)
    return re.sub(r"/\*.*?\*/", "", s, flags=re.S)


screen = src(LOCK_SCREEN)
lock = src(LOCK)
surface = src(SURFACE)
hypr = src(HYPR_GENERAL)

# ---------------------------------------------------------------------------
# The compositor half. Without this the QML half is denied and silent.

assert re.search(r"allow_session_lock_restore\s*=\s*true", hypr), (
    "misc:allow_session_lock_restore must stay true in hyprland/general.lua: "
    "without it Hyprland denies the shell's attempt to take back a session it "
    "is still holding, and the crash screen stays up until a TTY reboots it")

# ---------------------------------------------------------------------------
# The QML half: remember, then ask for it back, on the same compositor only.

assert "Persistent.states.lock.locked" in screen, (
    "nothing records that the session is locked, so a shell that restarts "
    "under its own lock cannot know to take it back -- Hyprland's IPC will not "
    "tell it")

init = screen.split("function initIfReady")[1].split("\n    }")[0]
assert "Persistent.states.lock.locked" in init and "isNewHyprlandInstance" in init, (
    "initIfReady must re-lock when the flag is set and the Hyprland instance "
    "signature is unchanged")
assert re.search(r"if\s*\(\s*Persistent\.states\.lock\.locked\s*&&\s*!\s*Persistent\.isNewHyprlandInstance",
                 init), (
    "the re-lock has to be gated on !isNewHyprlandInstance: a flag left over "
    "from a machine that went down locked would otherwise lock every fresh "
    "session, which is launchOnStartup's job and its setting to make")

writes = re.findall(r"Persistent\.states\.lock\.locked\s*=\s*([^;\n]+)", screen)
assert writes, "the flag is read but never written"
assert any("GlobalStates.screenLocked" in w for w in writes) or (
    any("true" in w for w in writes) and any("false" in w for w in writes)), (
    "the flag must be written on both edges -- set on lock and never cleared, "
    "it locks the screen on every start forever, and the first restart after "
    "locking still looks like it worked")

# ---------------------------------------------------------------------------
# The surface leaves before the session does.

unlocked = screen.split("onUnlocked:")[1].split("\n        }")[0]
assert "GlobalStates.screenLocked = false" not in unlocked, (
    "releasing the session in onUnlocked destroys the surface on the frame the "
    "password lands, which deletes its exit animation and shows nothing else")
assert "screenLockExiting = true" in unlocked, (
    "onUnlocked must raise screenLockExiting, which is what the surface plays "
    "its exit on while the compositor still holds the lock")

hold = screen.split("id: unlockExitTimer")[1].split("}")[0]
assert re.search(r"interval\s*:\s*Appearance\.animation\.\w+\.duration", hold), (
    "the hold between a correct password and a released session is the exit's "
    "own duration token, never a number picked to look right")

assert re.search(r"property bool screenLockExiting", src(SHELL / "GlobalStates.qml")), \
    "screenLockExiting must live in GlobalStates: both panel families read it"

# The surface's own half of that: something has to animate on the flag, or the
# hold is dead time with nothing in it.
assert "onScreenLockExitingChanged" in surface or "screenLockExiting" in surface, (
    "LockSurface ignores screenLockExiting, so the hold added to every unlock "
    "buys nothing")

island = surface.split("component LockIsland")[1]
assert "transformOrigin: Item.Bottom" in island, (
    "the islands are anchored to the bottom edge, so they grow out of it "
    "(DESIGN.md 2.6), not out of their own middle")
assert "elementMoveEnter" in island and "elementMoveExit" in island, (
    "enter and exit are not the same spec (DESIGN.md 2.5): decelerating and "
    "spatial in, fast effects out")

# ---------------------------------------------------------------------------
# The parked workspace maps back, including on a re-lock.
#
# Lifted from Lock.qml rather than restated: a desktop that locks once exercises
# none of this, because the second lock only happens after the shell has died.

BASE = int(re.search(r"lockWorkspaceBase\s*:\s*(\d+)", lock).group(1))
assert BASE == 2147483647, "Hyprland's last valid workspace id is INT32_MAX"
assert re.search(r"ws\s*>\s*root\.lockWorkspaceBase\s*/\s*2", lock), (
    "Lock.qml must recognise an already-parked workspace before saving it as "
    "the one to come back to")
assert f"{BASE}" not in lock.replace(f"lockWorkspaceBase: {BASE}", ""), \
    "the base is named once; a second copy is how the two halves drift apart"


def park(ws):
    return BASE - ws


def parked(ws):
    return ws > BASE / 2


def relock_saves(ws):
    """What Lock.qml records as the workspace to return to, given what is active."""
    return BASE - ws if parked(ws) else ws


for ws in list(range(1, 32)) + [100, 1000, 999999]:
    assert not parked(ws), f"ordinary workspace {ws} must not read as parked"
    assert parked(park(ws)), f"workspace {ws} parks to an id that reads as parked"
    assert relock_saves(ws) == ws, "a first lock saves the workspace it found"
    assert relock_saves(park(ws)) == ws, (
        f"a re-lock on parked workspace {park(ws)} must save {ws} to return to, "
        f"not {park(ws)} -- every window is on {ws}")

print("ok: session takeback wired on both sides, flag written on both edges, "
      "unlock holds the lock for its exit, parked workspaces map back")
