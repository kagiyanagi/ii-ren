#!/usr/bin/env python3
"""Every clipboard delete is delivered, even when several arrive during one run.

Run the real Cliphist.qml with a slow fake cliphist in an offscreen Quickshell.
Process coalesces repeated starts into one re-run, and reads command properties
again then: clearing entry after start lost the next deletion. Distinct deletes
need their own FIFO, while refreshes may still coalesce. No real history is used.
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
entries = ["1\tfirst", "2\t100% \\path", "3\tquotes ' and $(false)", "4\tlast"]
with tempfile.TemporaryDirectory(prefix="ii-cliphist-delete-") as directory:
    path = Path(directory)
    source = (II / "services/Cliphist.qml").read_text()
    source = re.sub(r"^import qs[.\w]*\n", "", source, flags=re.M).replace("import QtQuick", 'import "."\nimport QtQuick')
    (path / "Cliphist.qml").write_text(source)
    shutil.copyfile(II / "modules/common/functions/StringUtils.qml", path / "StringUtils.qml")
    (path / "Config.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var options: ({hacks: {arbitraryRaceConditionDelay: 10}}) }')
    (path / "Fuzzy.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function prepare(s) { return s; } }')
    (path / "qmldir").write_text("\n".join(f"singleton {name} 1.0 {name}.qml" for name in ("Cliphist", "StringUtils", "Config", "Fuzzy")))
    binary = path / "cliphist"
    binary.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
if sys.argv[1] == "delete":
    entry = sys.stdin.read().removesuffix("\\n")
    with Path(os.environ["CLIPHIST_CHECK_LOG"]).open("a") as log:
        log.write(json.dumps(entry) + "\\n")
    time.sleep(.4)
''')
    binary.chmod(0o755)
    (path / "shell.qml").write_text('''import QtQuick
import Quickshell
import "."
ShellRoot {
    Component.onCompleted: {
        Cliphist.cliphistBinary = %s;
        Cliphist.deleteEntry(%s);
    }
    Timer { interval: 100; running: true; onTriggered: {
        %s
    } }
    Timer { interval: 2300; running: true; onTriggered: Qt.quit() }
}
''' % (json.dumps(str(binary)), json.dumps(entries[0]),
       "\n".join(f"Cliphist.deleteEntry({json.dumps(entry)});" for entry in entries[1:])))
    log = path / "deletes.jsonl"
    try:
        result = subprocess.run(["qs", "-p", str(path), "--no-color"], capture_output=True, text=True,
                                env=dict(os.environ, QT_QPA_PLATFORM="offscreen", CLIPHIST_CHECK_LOG=str(log)), timeout=8)
    except subprocess.TimeoutExpired as error:
        raise AssertionError(f"test shell did not finish: {error.stdout!r} {error.stderr!r}") from error
    assert result.returncode == 0, result.stdout + result.stderr
    actual = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    assert actual == entries, f"delete queue lost or changed entries: {actual}\n{result.stdout}{result.stderr}"
    assert not re.search(r"ReferenceError|TypeError|Unable to assign", result.stdout + result.stderr), result.stdout + result.stderr
print("ok: four rapid deletes reach cliphist once each, in order, with literal entry bytes")
