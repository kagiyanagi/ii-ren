#!/usr/bin/env python3
"""Keyboard backlight state must follow external changes without file events.

Run the real KeyboardBacklight.qml with a temporary LED device and a fake
brightnessctl. Disable FileView events to model sysfs hardware changes: the old
service then stayed at its first read. Verify external levels, cycle wraparound,
and the absence of a helper when the device disappears. No real LED is written.
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
with tempfile.TemporaryDirectory(prefix="ii-kbd-backlight-") as directory:
    path = Path(directory)
    device = path / "kbd_backlight"
    device.mkdir()
    (device / "brightness").write_text("0")
    (device / "max_brightness").write_text("2")
    source = (II / "services/KeyboardBacklight.qml").read_text()
    source = re.sub(r"^import qs[.\w]*\n", "", source, flags=re.M)
    source = source.replace("import QtQuick", 'import "."\nimport QtQuick').replace("watchChanges: true", "watchChanges: false")
    source = re.sub(r'command: \["bash", "-c", "ls -d .*?"\]',
                    'command: ["printf", "%s", ' + json.dumps(str(device)) + ']', source)
    (path / "KeyboardBacklight.qml").write_text(source)
    shutil.copyfile(II / "modules/common/utils/KeepAliveProcess.qml", path / "KeepAliveProcess.qml")
    helper = II / "scripts/keyboard-backlight/watch.py"
    if helper.exists():
        (path / "scripts/keyboard-backlight").mkdir(parents=True)
        shutil.copyfile(helper, path / "scripts/keyboard-backlight/watch.py")
    (path / "qmldir").write_text("singleton KeyboardBacklight 1.0 KeyboardBacklight.qml\nKeepAliveProcess 1.0 KeepAliveProcess.qml\n")
    (path / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
    IpcHandler {
        target: "keyboardCheck"
        function value(): int { return KeyboardBacklight.currentValue; }
        function maximum(): int { return KeyboardBacklight.maxValue; }
        function cycle(): void { KeyboardBacklight.cycle(); }
        function remove(): void { KeyboardBacklight.device = ""; }
    }
}
''')
    binary = path / "brightnessctl"
    binary.write_text('#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\nPath(os.environ["KBD_CHECK_DEVICE"], "brightness").write_text(sys.argv[-1])\n')
    binary.chmod(0o755)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", PATH=directory + os.pathsep + os.environ["PATH"], KBD_CHECK_DEVICE=str(device))
    with (path / "qs.log").open("w") as log:
        process = subprocess.Popen(["qs", "-p", directory, "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)

    def call(name):
        result = subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "keyboardCheck", name], capture_output=True, text=True, timeout=3)
        return result.stdout.strip()

    def wait(name, expected):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            if call(name) == str(expected): return
            time.sleep(.05)
        raise AssertionError(f"{name} never became {expected}: {(path / 'qs.log').read_text()}")

    try:
        wait("maximum", 2)
        wait("value", 0)
        (device / "brightness").write_text("2")
        wait("value", 2)
        call("cycle")
        wait("value", 0)
        deadline = time.monotonic() + 2
        while (device / "brightness").read_text() != "0" and time.monotonic() < deadline:
            time.sleep(.03)
        assert (device / "brightness").read_text() == "0", "cycle did not write its wrapped level"
        call("remove")
        wait("value", 0)
        if helper.exists():
            deadline = time.monotonic() + 2
            while subprocess.run(["pgrep", "-f", str(path / "scripts/keyboard-backlight/watch.py")], capture_output=True).returncode == 0:
                assert time.monotonic() < deadline, "backlight helper outlived its device"
                time.sleep(.03)
        assert not re.search(r"ReferenceError|TypeError|Unable to assign", (path / "qs.log").read_text())
    finally:
        process.terminate()
        process.wait(timeout=5)
print("ok: keyboard backlight follows external levels without events and cycles through kernel levels")
