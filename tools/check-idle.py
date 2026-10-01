#!/usr/bin/env python3
"""Keep awake ends on time, and says truthfully how long it has left.

None of this shows in a screenshot. The countdown rounds minutes up, so "5m" still
reads 5m for the first minute instead of flashing 4m the instant it starts. A timed
keep-awake is ended by a 1s tick on the wall clock, not by a single-shot Timer: Qt
timers are monotonic, and one set for 30m would run 30m past a suspend. A shell that
restarts after the end time must come back off, so restore runs the same tick. Unlock
and keep awake means until turned off, as it did before durations, and must not
overwrite the duration the tile remembers.

Keep awake can also be tied to processes picked in the dialog, by PID. A process
exiting sends nothing, so a poll drops the PIDs ps no longer lists and the last one
gone ends it. A PID picked while that ps ran was not asked about and must survive
its answer. Any other way of turning it on (a duration, the tile, unlock) replaces
the picked apps, and they persist with the rest.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
service = (II / "services/Idle.qml").read_text()
persistent = (II / "modules/common/Persistent.qml").read_text()
lock = (II / "modules/common/panels/lock/LockScreen.qml").read_text()

# The formatter, lifted out of the QML and run under node.
body = re.search(r"readonly property string remainingText: \{\n(.*?)\n    \}\n", service, re.S).group(1)
cases = [0, 1_000, 59_000, 59_001, 60_000, 60_001, 300_000, 299_000, 3_600_000, 5_400_000, 86_400_000]
js = f"const f = remaining => {{\n{body}\n}};\nconsole.log(JSON.stringify({cases}.map(f)));"
out = json.loads(subprocess.run(["node", "-"], input=js, capture_output=True, text=True, check=True).stdout)
assert out == ["0s", "1s", "59s", "1m", "1m", "2m", "5m", "5m", "1h", "1h 30m", "24h"], out

tick = re.search(r"Timer \{\n\s*id: tick\n(.*?)\n    \}", service, re.S).group(1)
assert "Date.now()" in tick and "root.set(false, 0)" in tick, "the tick must end it on the wall clock"
assert "running: root.inhibit && root.until > 0" in tick, "no tick unless a timed one runs"
assert re.search(r"root\.until = Persistent\.states\.idle\.until.*?tick\.triggered\(\)", service, re.S), \
    "restore must end a keep-awake whose time passed while the shell was down"
assert "property real until: 0" in persistent, "until is epoch ms: a QML int wraps"
assert "Idle.set(true, 0)" in lock and "Idle.toggleInhibit(true)" not in lock, \
    "unlock and keep awake is until turned off, without touching the remembered duration"
assert "function set(on, until, anchors = [])" in service and "root.anchors = anchors" in service, \
    "every other start must clear the picked apps"
assert "property list<var> anchors: []" in persistent and "Persistent.states.idle.anchors = anchors" in service, \
    "picked apps must outlive a shell restart"
reap = re.search(r"onStreamFinished: \{\n(.*?)\n\s*\}\n\s*\}\n\s*\}", service, re.S).group(1)
assert "running: root.inhibit && root.anchors.length > 0" in service, "no poll unless apps are picked"
js = ("const root = { anchors: [{pid: 1}, {pid: 2}, {pid: 3}], set: (...a) => out.push(a) }, alive = { pids: [1, 2] }, out = [];\n"
      "for (const text of ['  1\\n', '']) { (function () {\n" + reap + "\n}).call({ text }); }\n"
      "console.log(JSON.stringify(out));")
js = js.replace("text.split", "this.text.split")
out = json.loads(subprocess.run(["node", "-"], input=js, capture_output=True, text=True, check=True).stdout)
assert out == [[True, 0, [{"pid": 1}, {"pid": 3}]], [True, 0, [{"pid": 3}]]], \
    f"exited PIDs drop, one picked mid-poll stays: {out}"
print("ok: countdown rounds up, ends on the wall clock, comes back off after a restart, lock keeps it on, picked apps end it when they exit")
