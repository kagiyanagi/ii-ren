#!/usr/bin/env python3
"""Document the installed Quickshell's one queued Process re-run accurately.

Repeated running=true assignments during a run coalesce into one re-run, using
the command at restart time. Verify that in a real offscreen Quickshell rather
than relying on a fake Process that silently assumes starts are ignored.
"""
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="ii-process-rerun-") as directory:
    path = Path(directory)
    (path / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    id: root
    property string argument: "first"
    property int completions: 0
    Component.onCompleted: worker.running = true
    Process {
        id: worker
        command: ["sh", "-c", 'sleep 0.3; printf "%s" "$1"', "sh", root.argument]
        stdout: StdioCollector { onStreamFinished: console.log("OUTPUT", text) }
        onExited: root.completions++
    }
    Timer { interval: 100; running: true; onTriggered: {
        root.argument = "second";
        worker.running = true;
        worker.running = true;
        worker.running = true;
    } }
    Timer { interval: 150; running: true; onTriggered: {
        root.argument = "latest";
        worker.running = true;
    } }
    Timer { interval: 1000; running: true; onTriggered: {
        console.log("COMPLETIONS", root.completions);
        Qt.quit();
    } }
}
''')
    result = subprocess.run(["qs", "-p", directory, "--no-color"], capture_output=True, text=True,
                            env=dict(os.environ, QT_QPA_PLATFORM="offscreen"), timeout=6)
    log = result.stdout + result.stderr
    assert re.findall(r"OUTPUT (\w+)", log) == ["first", "latest"], log
    assert "COMPLETIONS 2" in log, log
for relative in ("AGENTS.md", "dots/.config/quickshell/ii/modules/common/utils/RefreshProcess.qml"):
    source = (ROOT / relative).read_text()
    assert not re.search(r"running.{0,80}no-op", source, re.S), f"{relative}: falsely says a running Process ignores another start"
print("ok: repeated starts queue one re-run with the latest command; process documentation agrees")
