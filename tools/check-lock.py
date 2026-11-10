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

- **The lockout warning is not filtered out.** After `deny` wrong passwords
  pam_faillock refuses the next ones before pam_unix ever sees them, and says so
  through the PAM conversation -- measured here on 2026-09-21, with an isolated
  tally dir: `"The account is locked due to 2 failed logins."` then
  `"(2 minutes left to unlock)"`, both with **`messageIsError == false`**. It is
  `pam_info`, not `pam_error`. So a capture that only keeps errors keeps nothing,
  and the screen goes back to shaking at a password PAM never checked. A plain
  wrong password sends no message at all, which is why the whole conversation can
  be surfaced without it becoming noise.

- **An empty password never reaches PAM.** pam_faillock counts an empty answer
  like a wrong one, three is a ten-minute lockout here, and Enter is the key
  people press to wake a dark screen -- a few of those used to be the lockout.
  `tryUnlock` is the only way into the password conversation for both families,
  so the refusal lives there and is run under node rather than read. The
  fingerprint conversation never waits on the field, or a print could not
  unlock the screen it was meant to.

- **Looking away does not turn the fingerprint reader off.** Ten seconds after
  the last key the typed password is cleared through `reset()`, which used to
  abort the fingerprint conversation as well. Quickshell's `PamContext.abort()`
  emits no `completed` -- the only thing the re-arm hangs off -- so one keypress
  and ten idle seconds left the reader off until the next lock. The reader
  belongs to the lock edges instead: armed by `resetFingerprint` on lock, stopped
  by `onScreenLockedChanged` on unlock. The round trip runs under node against a
  fake `PamContext` that aborts the way Quickshell's does.

- **The Caps Lock state is tracked, not polled at the worst moment.** Hyprland
  reports the lock keys in `hyprctl devices` and emits no socket2 event when they
  change -- verified by watching the socket across a toggle -- so the key event is
  all there is to go on. But the compositor hands the key to the client *before*
  it updates what it reports: measured on 2026-09-21, a query fired from the key
  event came back stale 11ms after one press and fresh 22ms after another. Stale
  then sticks, because nothing else asks, and the first shipped version of this
  did exactly that: the hint appeared when Caps Lock went on and would not go
  away when it went off. The press is the toggle, so the press flips the state,
  and the authoritative read is left to surface creation, which races nothing.
  Auto-repeat must be skipped -- xkb toggles a lock on the real press only.

- **The parked workspace maps back.** Locking parks each monitor on
  `INT32_MAX - ws` so no window sits behind a transparent lock surface. A shell
  that restarts under a lock re-runs that on a monitor that is *already* parked,
  where the arithmetic is its own inverse and the saved map is gone -- save the
  parked id as the one to return to and unlocking drops the user on an empty
  workspace with every window somewhere else.

- **Nothing can bring it back if it dies twice.** The takeback needs a new qs,
  and two things stop one appearing. A live reload under the lock tears the old
  generation's `WlSessionLock` down without unlocking (the new one never inherits
  it: `PanelLoader` waits on a fresh `Config`), and Quickshell leaves its
  process-wide lock pointer dangling, so the relock hits `qFatal("Tried to show
  lockscreen surfaces without active lock")` -- in the crash reports here on
  2026-08-31. So no reloads while locked. And Quickshell relaunches itself after
  a crash but not one within 10s of launch, so a crash loop under the lock is
  permanent unless `launch_quickshell.sh` starts it again. That loop is run here
  against a fake `qs`.

Run: python3 tools/check-lock.py
"""
import json
import os
import pathlib
import re
import subprocess
import tempfile

REPO = pathlib.Path(__file__).parent.parent
SHELL = REPO / "dots/.config/quickshell/ii"
LOCK_SCREEN = SHELL / "modules/common/panels/lock/LockScreen.qml"
LOCK = SHELL / "modules/ii/lock/Lock.qml"
SURFACE = SHELL / "modules/ii/lock/LockSurface.qml"
HYPR_GENERAL = REPO / "dots/.config/hypr/hyprland/general.lua"
HYPR_EXECS = REPO / "dots/.config/hypr/hyprland/execs.lua"
LAUNCH = REPO / "dots/.config/hypr/hyprland/scripts/launch_quickshell.sh"


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
# The reason the password cannot work reaches the screen.

context = src(SHELL / "modules/common/panels/lock/LockContext.qml")
message = context.split("onPamMessage:")[1].split("\n        }")[0]
assert "authMessage" in message, (
    "PAM's messages have to be kept: faillock's lockout notice is the only "
    "warning the user gets that the next attempts are refused unread")
assert "messageIsError" not in message, (
    "do not filter the capture on messageIsError -- pam_faillock sends the "
    "lockout through pam_info, so an error-only filter keeps nothing at all")
assert "responseRequired" in message and "respond" in message, \
    "the password prompt itself is a message, and still has to be answered"

assert 'root.authMessage = "";' in context.split("function tryUnlock")[1].split("}")[0], \
    "the message must be cleared when the next attempt starts, or it outlives "\
    "the lockout it describes"
assert 'lockContext.authMessage = "";' in screen, (
    "a fresh lock must clear the last one's PAM message, or the screen opens "
    "showing a lockout that has already expired")
assert 'authMessage = ""' not in src(SHELL / "modules/common/panels/lock/LockContext.qml").split("function reset()")[1].split("}")[0], (
    "not in reset(): the ten-second idle timer calls that, and the reason the "
    "screen will not open should outlast looking away from it")

status = surface.split("Rectangle {\n        id: statusChip")[1].split("\n    // Main toolbar")[0]
assert "colErrorContainer" in status and "authMessage" in surface, \
    "the PAM message needs the error container; a lockout is not a hint"
assert "lineCount > 1" in status and "rounding.large" in status, (
    "a pill radius on a chip that has wrapped is an arc that eats the first "
    "and last lines (DESIGN.md 5.6) -- faillock's two sentences wrap")
assert "transformOrigin: Item.Bottom" in status, \
    "the chip is about the island under it, so it grows out of it (2.6)"
assert "elementMoveEnter" in status and "elementMoveExit" in status, \
    "enter and exit are different specs (2.5)"

# ---------------------------------------------------------------------------
# An empty password never starts PAM: faillock would count it.

pam_users = [p.relative_to(SHELL) for p in SHELL.rglob("*.qml") if "PamContext" in src(p)]
assert pam_users == [pathlib.Path("modules/common/panels/lock/LockContext.qml")], (
    f"PamContext outside LockContext ({pam_users}) is a second way into PAM that "
    "the empty-password gate in tryUnlock does not cover")
assert len(re.findall(r"\bpam\.start\(\)", context)) == 1, \
    "the password conversation is started from tryUnlock and nowhere else"

try_unlock = re.search(r"\n    function tryUnlock\(.*?\n    }\n", context, re.S)
assert try_unlock and "pam.start()" in try_unlock.group(0), "tryUnlock not found in LockContext.qml"
js = ("function make(root, pam) {" + try_unlock.group(0) + "return tryUnlock; }\n"
      "const run = (text, busy) => {\n"
      "    const root = { currentText: text, unlockInProgress: busy, authMessage: 'locked', alsoInhibitIdle: false };\n"
      "    let started = 0;\n"
      "    make(root, { start: () => started++ })(true);\n"
      "    return { started, busy: root.unlockInProgress, message: root.authMessage, inhibit: root.alsoInhibitIdle };\n"
      "};\n"
      "console.log(JSON.stringify([run('', false), run('hunter2', false), run('hunter2', true), run(' ', false)]));")
empty, typed, busy, space = json.loads(
    subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)
assert empty == {"started": 0, "busy": False, "message": "locked", "inhibit": False}, (
    f"Enter on an empty field started PAM or changed state ({empty}): faillock "
    "counts it, and the lockout message it would clear is the reason the next "
    "real attempt will be refused")
assert typed == {"started": 1, "busy": True, "message": "", "inhibit": True}, \
    f"a typed password must start exactly one attempt ({typed})"
assert busy["started"] == 0, "a second Enter while PAM is still answering must not start another"
assert space["started"] == 1, "a password of spaces is still a password -- the gate is empty, not blank"

finger = context.split("function tryFingerUnlock")[1].split("\n    }")[0]
assert "currentText" not in finger and "tryUnlock(" not in finger, (
    "the fingerprint conversation must not wait on the password field, or the "
    "gate above stops a print from unlocking")

# ---------------------------------------------------------------------------
# The idle clear leaves the fingerprint reader listening.


def lift(pattern, what):
    m = re.search(pattern, context, re.S)
    assert m, f"{what} not found in LockContext.qml"
    return m.group(0)


fns = "".join(lift(r"\n    function %s\(.*?\n    }\n" % name, name) for name in (
    "resetTargetAction", "clearText", "reset", "stopFingerPam", "tryFingerUnlock", "resetFingerprint"))
fns += lift(r"\n        function onScreenLockedChanged\(\).*?\n        }\n", "the screenLocked Connections")
idle = context.split("id: passwordClearTimer")[1].split("\n    }")[0]
assert "onTriggered:" in idle, "passwordClearTimer has no onTriggered"
js = (
    "const LockContext = { ActionEnum: { Unlock: 0, Poweroff: 1, Reboot: 2 } };\n"
    "const GlobalStates = { screenLocked: false };\n"
    "const Config = { options: { lock: { security: { fingerprint: { enable: true } } } } };\n"
    "const Fingerprint = { refresh() {} };\n"
    # Quickshell's PamContext::abort(): the conversation is dropped, completed is not emitted.
    "const fingerPam = { active: false, start() { this.active = true; }, abort() { this.active = false; } };\n"
    "const fingerprintRearmTimer = { running: false, interval: 0, restart() { this.running = true; },"
    " start() { this.running = true; }, stop() { this.running = false; } };\n"
    "const root = { currentText: '', unlockInProgress: false, targetAction: 0, fingerprintsConfigured: true,"
    " fingerprintExhausted: false, fingerprintAttempts: 0, fingerprintErrors: 0, fingerprintFailed: false,"
    " fingerprintRearmDelay: 400 };\n"
    + fns +
    "Object.assign(root, { resetTargetAction, clearText, reset, stopFingerPam, tryFingerUnlock, resetFingerprint });\n"
    "const idle = () => {" + idle.split("onTriggered:")[1] + "};\n"
    # A pending re-arm counts as listening: it is how the reader returns after a failed match.
    "const settle = () => { if (fingerprintRearmTimer.running) { fingerprintRearmTimer.running = false; root.tryFingerUnlock(); } };\n"
    "GlobalStates.screenLocked = true; root.reset(); root.resetFingerprint(); settle();\n"
    "const armed = fingerPam.active;\n"
    "root.currentText = 'hunter2'; root.targetAction = LockContext.ActionEnum.Poweroff;\n"
    "idle(); settle();\n"
    "const afterIdle = { listening: fingerPam.active, text: root.currentText, target: root.targetAction };\n"
    # unlockExitTimer: release the session, then reset; a failed match's re-arm may still be pending.
    "GlobalStates.screenLocked = false; onScreenLockedChanged(); root.reset();\n"
    "fingerprintRearmTimer.running = true; settle();\n"
    "console.log(JSON.stringify([armed, afterIdle, fingerPam.active]));")
armed, after_idle, after_unlock = json.loads(
    subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)
assert armed, "locking (reset, then resetFingerprint, as LockScreen does) must arm the reader"
assert after_idle["text"] == "" and after_idle["target"] == 0, \
    f"the idle clear must still clear the typed password and the power-off target ({after_idle})"
assert after_idle["listening"], (
    "the ten-second idle clear stopped the fingerprint reader: PamContext.abort() "
    "emits no completed, so nothing arms it again until the next lock")
assert not after_unlock, (
    "unlocking must stop the reader, and a re-arm still pending from a failed "
    "match must not start it again behind an unlocked screen")

# ---------------------------------------------------------------------------
# Caps Lock is asked for at the only moment it can have changed.

xkb = src(SHELL / "services/HyprlandXkb.qml")
assert "property bool capsLock" in xkb and "function refreshLockKeys" in xkb, \
    "HyprlandXkb owns the lock-key state; the lock screen only asks for it"
assert xkb.count('command: ["hyprctl", "-j", "devices"]') == 1, (
    "one devices fetch, not two: the layouts and the lock keys come out of the "
    "same call")
assert "function noteCapsLockPressed" in xkb, \
    "the press has to be trackable without asking the compositor"
assert "Qt.Key_CapsLock" in surface, (
    "nothing announces a Caps Lock change -- Hyprland has no event for it -- so "
    "the key press is all there is, and without it the hint never appears")

caps_branch = surface.split("Qt.Key_CapsLock")[1].split("}")[0]
assert "noteCapsLockPressed" in caps_branch, (
    "flip the tracked state on the key; a query here reads what the compositor "
    "reported *before* the press about half the time, and a stale answer sticks "
    "-- that is the bug where the hint would not go away when Caps Lock did")
assert "refreshLockKeys" not in caps_branch, \
    "same thing said the other way round: no compositor query from the key event"
assert "isAutoRepeat" in surface.split("Qt.Key_CapsLock")[0][-120:] + caps_branch, \
    "a held Caps Lock repeats and xkb toggles the lock once, so skip repeats"
assert surface.split("Component.onCompleted:")[1].split("}")[0].count("refreshLockKeys") == 1, (
    "Caps Lock can already be on when the screen locks, and a surface opening "
    "is the one moment a query has nothing to race")

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

# ---------------------------------------------------------------------------
# Something is always there to take it back.

assert re.search(r'Binding\s*\{\s*target:\s*Quickshell\s*property:\s*"watchFiles"\s*'
                 r'value:\s*!GlobalStates\.screenLocked', screen), (
    "live reload must be off while locked: a reload under the lock drops it "
    "without unlocking and the relock aborts on Quickshell's qFatal")
assert "launch_quickshell.sh" in src(HYPR_EXECS) and not re.search(
    r'exec_cmd\("qs -c', src(HYPR_EXECS)), \
    "the shell must start through launch_quickshell.sh, or a crash loop under the lock is final"
assert os.access(LAUNCH, os.X_OK), "launch_quickshell.sh must be executable"


def launches(codes, locked):
    """How many times the script starts qs, given each run's exit code."""
    with tempfile.TemporaryDirectory() as tmp:
        t = pathlib.Path(tmp)
        (t / "quickshell").mkdir()
        (t / "quickshell/states.json").write_text(
            '{\n    "lock": {\n        "locked": %s\n    }\n}\n' % str(locked).lower())
        (t / "codes").write_text("\n".join(map(str, codes)) + "\n")
        (t / "qs").write_text(
            '#!/usr/bin/env bash\necho run >> "$T/runs"\n'
            'c=$(head -n1 "$T/codes"); sed -i 1d "$T/codes"; exit "${c:-0}"\n')
        (t / "qs").chmod(0o755)
        env = dict(os.environ, T=tmp, XDG_STATE_HOME=tmp, PATH=f"{tmp}:{os.environ['PATH']}")
        subprocess.run(["bash", str(LAUNCH)], env=env, timeout=30, check=True)
        return (t / "runs").read_text().count("run")


assert launches([255, 139, 0], locked=True) == 3, \
    "a crash under the lock must be followed by another qs, until one exits cleanly"
assert launches([143], locked=True) == 1, \
    "SIGTERM is pkill / iiren run, which start their own qs -- a second one would duplicate the shell"
assert launches([255], locked=False) == 1, \
    "unlocked, a crash loop is Quickshell's to stop; the supervisor only covers the locked case"

print("ok: session takeback wired on both sides, flag written on both edges, "
      "no reloads under the lock, relaunched when it dies locked, "
      "unlock holds the lock for its exit, PAM's lockout reaches the screen "
      "unfiltered, an empty password never starts PAM, the idle clear leaves "
      "the fingerprint reader listening, Caps Lock is asked for "
      "on the key, parked workspaces map back")
