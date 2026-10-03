#!/usr/bin/env python3
"""Long-running helpers restart after a crash and die with the shell.

A `Process { running: <binding> }` whose helper exits stays stopped - the binding
has nothing new to say - so a crashed privacystate.py or `nmcli monitor` left its
feature dead until the next shell restart. And a killed or crashed shell runs no
destructors: every `pkill qs` left another nmcli/gdbus monitor running for the rest
of the session (five of each after an afternoon of restarts).

modules/common/utils/KeepAliveProcess.qml does both: restarts with backoff, and
starts the helper under setpriv --pdeathsig. This asserts every monitor-style helper
goes through it, then runs it in a throwaway `qs -p` shell: a helper that exits at
once is restarted on the 1s, 2s schedule, and a `kill -9` of the shell takes the
other helper with it. That part needs a Wayland session and skips without one.
"""
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
KEEP = II / "modules/common/utils/KeepAliveProcess.qml"

keep = KEEP.read_text()
assert re.search(r'command: \["setpriv", "--pdeathsig", "TERM", "--", \.\.\.root\.args\]', keep), \
    "KeepAliveProcess no longer starts its helper under setpriv --pdeathsig"

LONG = re.compile(r'"(nmcli|gdbus|udevadm)", "monitor"|"cava", "-p"|privacyStateScript|"python3", root\.helperPath\]')
for f in (II / "services").glob("*.qml"):
    t = f.read_text()
    for m in re.finditer(r'\n(\s*)(\w+) \{\n', t):
        body = t[m.end():t.find(f"\n{m.group(1)}}}", m.end())]
        head = "\n".join(body.splitlines()[:4])
        if m.group(2) == "Process" and LONG.search(head):
            raise AssertionError(f"services/{f.name}: a long-running helper in a plain Process; use KeepAliveProcess")

if not os.environ.get("WAYLAND_DISPLAY"):
    print("ok (static only, no Wayland session for the qs run)")
    raise SystemExit

with tempfile.TemporaryDirectory() as d:
    (Path(d) / "KeepAliveProcess.qml").write_text(keep)
    marker = f"keepalive-check-{os.getpid()}"
    (Path(d) / "shell.qml").write_text(f'''import QtQuick
import Quickshell
ShellRoot {{
    id: r
    property int starts: 0
    KeepAliveProcess {{ args: ["sh", "-c", "exit 1"]; onRunningChanged: if (running) r.starts++ }}
    KeepAliveProcess {{ args: ["sh", "-c", "exec -a {marker} sleep 300"] }}
    Timer {{ interval: 3500; running: true; onTriggered: console.log("STARTS", r.starts) }}
}}
''')
    log = Path(d) / "log"
    qs = subprocess.Popen(["qs", "-p", f"{d}/shell.qml"], stdout=log.open("w"), stderr=subprocess.STDOUT)
    try:
        time.sleep(4.5)
        starts = re.search(r"STARTS (\d+)", log.read_text())
        assert starts, f"the test shell never reported; its log:\n{log.read_text()[-800:]}"
        assert int(starts.group(1)) == 3, f"a helper exiting at once started {starts.group(1)} times in 3.5s, not 3 (0s, 1s, 3s)"
        assert subprocess.run(["pgrep", "-f", f"^{marker}"], capture_output=True).returncode == 0, "the long-lived helper never started"
    finally:
        qs.kill()
        qs.wait()
    time.sleep(0.5)
    left = subprocess.run(["pgrep", "-f", f"^{marker}"], capture_output=True).returncode == 0
    subprocess.run(["pkill", "-f", f"^{marker}"])
    assert not left, "a helper outlived a kill -9 of the shell"

print("ok: helpers restart on 1s, 2s backoff and die with the shell")
