#!/usr/bin/env python3
"""Night Light reaches the daemon even when its socket is late at login.

Run the actual Hyprsunset.qml, timers and processes in an offscreen Quickshell.
Only config/clock inputs and the hyprctl/daemon commands are faked: no display
settings change. A failed command must retry, and a newer manual choice or
temperature must win while the daemon is unavailable or a write is in flight.

    python3 tools/check-hyprsunset.py
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
FAKE = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
path = Path(os.environ["HYPRSUNSET_FIXTURE"])
config = json.loads((path / "config.json").read_text())
args = sys.argv[1:]
with (path / "calls.jsonl").open("a") as log:
    log.write(json.dumps(dict(args=args, time=time.time())) + "\n")
if time.time() < config["ready_at"]:
    print("Couldn't connect to hyprsunset")
    sys.exit(3)
setting = args[1]
target = path / setting
if len(args) > 2:
    time.sleep(config.get("write_delay", 0))
    target.write_text(args[2])
    print("ok")
else:
    value = target.read_text()
    time.sleep(config.get("read_delay", 0))
    print(value)
'''
PROBE = '''import QtQuick
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
    Component.onCompleted: Hyprsunset.load()
    IpcHandler {
        target: "sunsetCheck"
        function state(): string {
            return JSON.stringify({active: Hyprsunset.temperatureActive, gamma: Hyprsunset.gamma})
        }
        function toggle(active: bool): void { Hyprsunset.toggleTemperature(active) }
        function temperature(value: int): void { Config.options.light.night.colorTemperature = value }
        function gamma(value: int): void { Hyprsunset.setGamma(value) }
        function fetch(): void { Hyprsunset.fetchState() }
    }
}
'''


class Probe:
    def __init__(self, directory, automatic=True, gamma=100, **config):
        self.path = Path(directory)
        self.config = dict(ready_at=time.time()) | config
        self.configure()
        (self.path / "temperature").write_text("6000")
        (self.path / "gamma").write_text(str(gamma))
        source = (II / "services/Hyprsunset.qml").read_text()
        source = re.sub(r"^import qs[.\w]*\n", "", source, flags=re.M)
        source = source.replace("import Quickshell.Hyprland\n", 'import "."\n')
        (self.path / "Hyprsunset.qml").write_text(source)
        (self.path / "Config.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool ready: true
    property QtObject options: QtObject {
        property QtObject light: QtObject {
            property QtObject night: QtObject {
                property string from: "19:00"
                property string to: "06:30"
                property bool automatic: ''' + str(automatic).lower() + '''
                property int colorTemperature: 4200
            }
        }
    }
}
''')
        (self.path / "DateTime.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property var clock: ({hours: 22, minutes: 0}) }
''')
        shutil.copyfile(II / "modules/common/utils/RefreshProcess.qml", self.path / "RefreshProcess.qml")
        (self.path / "qmldir").write_text("\n".join([
            "singleton Hyprsunset 1.0 Hyprsunset.qml", "singleton Config 1.0 Config.qml",
            "singleton DateTime 1.0 DateTime.qml", "RefreshProcess 1.0 RefreshProcess.qml"]))
        (self.path / "shell.qml").write_text(PROBE)
        binary = self.path / "bin"
        binary.mkdir()
        for name, script in {"hyprctl": FAKE, "pidof": "#!/bin/sh\nexit 0\n",
                             "hyprsunset": "#!/bin/sh\nexit 0\n"}.items():
            command = binary / name
            command.write_text(script)
            command.chmod(0o755)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", HYPRSUNSET_FIXTURE=str(self.path),
                   PATH=str(binary) + os.pathsep + os.environ["PATH"])
        self.log = self.path / "qs.log"
        with self.log.open("w") as log:
            self.process = subprocess.Popen(["qs", "-p", str(self.path), "--no-color"], env=env,
                                            stdout=log, stderr=subprocess.STDOUT)

    def configure(self, **config):
        self.config.update(config)
        target = self.path / "config.json"
        pending = target.with_suffix(".new")
        pending.write_text(json.dumps(self.config))
        pending.replace(target)

    def call(self, method, *args):
        result = subprocess.run(["qs", "ipc", "--pid", str(self.process.pid), "call",
                                 "sunsetCheck", method, *map(str, args)],
                                capture_output=True, text=True, timeout=3)
        return result.stdout.strip() if result.returncode == 0 else ""

    def state(self):
        answer = self.call("state")
        return json.loads(answer) if answer else {}

    def wait(self, predicate, why, seconds=4):
        deadline = time.monotonic() + seconds
        state = {}
        while time.monotonic() < deadline:
            assert self.process.poll() is None, self.log.read_text()
            state = self.state()
            if state and predicate(state):
                return state
            time.sleep(0.03)
        raise AssertionError(f"{why}: {state}\n{self.log.read_text()[-1500:]}")

    def raw(self, setting):
        return int((self.path / setting).read_text())

    def calls(self):
        path = self.path / "calls.jsonl"
        return [json.loads(line)["args"] for line in path.read_text().splitlines()] if path.exists() else []

    def close(self):
        self.process.terminate()
        self.process.wait(timeout=5)
        assert not re.search(r"TypeError|ReferenceError|Unable to assign", self.log.read_text()), self.log.read_text()


def check_startup(p):
    p.wait(lambda s: bool(p.calls()), "no daemon command at startup")
    p.wait(lambda s: p.raw("temperature") == 4200 and s["active"],
           "automatic night light never reaches the late daemon")
    time.sleep(0.7)
    count = len(p.calls())
    time.sleep(0.8)
    assert len(p.calls()) == count, "retry timer keeps running after success"


def check_latest(p):
    p.wait(lambda s: bool(p.calls()), "no startup command")
    p.call("toggle", "false")
    p.wait(lambda s: not s["active"] and p.raw("temperature") == 6000
           and time.time() > p.config["ready_at"] + 0.6, "retry undoes a manual off")
    p.configure(write_delay=0.3)
    p.call("toggle", "true")
    time.sleep(0.1)
    p.call("temperature", 4500)
    p.call("toggle", "false")
    p.wait(lambda s: p.raw("temperature") == 6000 and not s["active"], "latest off is lost during a write")
    time.sleep(0.8)
    assert p.raw("temperature") == 6000, "stale temperature wins after commands settle"
    p.call("toggle", "true")
    p.wait(lambda s: s["active"] and p.raw("temperature") == 4500, "updated color temperature was lost")


def check_updates(p):
    p.wait(lambda s: bool(p.calls()), "no startup command")
    p.call("temperature", 4300)
    p.wait(lambda s: s["active"] and p.raw("temperature") == 4300,
           "color-temperature edit is lost while waiting for the daemon")
    p.configure(write_delay=0.3)
    p.call("temperature", 4600)
    time.sleep(0.1)
    p.call("temperature", 4700)
    p.wait(lambda s: s["active"] and p.raw("temperature") == 4700, "edit during a write is lost")
    p.configure(read_delay=0.8, write_delay=0)
    p.call("fetch")
    time.sleep(0.1)
    p.call("toggle", "false")
    p.wait(lambda s: not s["active"] and p.raw("temperature") == 6000, "off never reaches daemon")
    time.sleep(1)
    assert not p.state()["active"], "an old read rolls back a successful toggle"


if __name__ == "__main__":
    for check in (check_startup, check_latest, check_updates):
        with tempfile.TemporaryDirectory(prefix="ii-hyprsunset-check-") as directory:
            p = Probe(directory, ready_at=time.time() + 0.9)
            try:
                check(p)
            finally:
                p.close()
        print("ok: hyprsunset " + check.__name__.removeprefix("check_"))
