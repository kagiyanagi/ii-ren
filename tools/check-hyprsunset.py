#!/usr/bin/env python3
"""Night Light reaches the daemon even when its socket is late at login.

Run the actual Hyprsunset.qml, timers and processes in an offscreen Quickshell.
Only config/clock inputs and the hyprctl/daemon commands are faked: no display
settings change. A failed command must retry, and a newer manual choice or
temperature must win while the daemon is unavailable or a write is in flight.
Read the daemon's surviving gamma after a restart, then exercise the production
Brightness.increaseBrightness(): it must restore gamma before hardware brightness.

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
    print("not a reading" if config.get("read_invalid", False) else value)
    sys.exit(config.get("read_exit", 0))
'''
PROBE = '''import QtQuick
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
    id: root
    property int hardwareSteps: 0
    property int gammaAttempts: 0
    function getTargetMonitor() { return {ready: true, adjustBrightness: () => root.hardwareSteps++} }
    // INCREASE_BRIGHTNESS
    Component.onCompleted: Hyprsunset.load()
    Connections {
        target: Hyprsunset
        function onGammaChangeAttempt() { root.gammaAttempts++ }
    }
    IpcHandler {
        target: "sunsetCheck"
        function state(): string {
            return JSON.stringify({active: Hyprsunset.temperatureActive, gamma: Hyprsunset.gamma,
                hardwareSteps: root.hardwareSteps, gammaAttempts: root.gammaAttempts})
        }
        function toggle(active: bool): void { Hyprsunset.toggleTemperature(active) }
        function temperature(value: int): void { Config.options.light.night.colorTemperature = value }
        function gamma(value: int): void { Hyprsunset.setGamma(value) }
        function fetch(): void { Hyprsunset.fetchState() }
        function increase(): void { root.increaseBrightness() }
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
        brightness = (II / "services/Brightness.qml").read_text()
        increase = re.search(r"    function increaseBrightness\(\): void \{.*?\n    \}", brightness, re.S)[0]
        (self.path / "shell.qml").write_text(PROBE.replace("    // INCREASE_BRIGHTNESS", increase))
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


def check_gamma(p):
    p.wait(lambda s: s["gamma"] == 65, "shell lost the daemon's lowered gamma after restart")
    assert p.state()["gammaAttempts"] == 0, "reading startup gamma triggers the OSD"
    assert not [c for c in p.calls() if c[:2] == ["hyprsunset", "gamma"] and len(c) > 2], \
        "startup resets gamma instead of reading it"
    for gamma in range(70, 101, 5):
        p.call("increase")
        p.wait(lambda s: s["gamma"] == gamma and p.raw("gamma") == gamma,
               "brightness-up fails to restore gamma")
        assert p.state()["hardwareSteps"] == 0, "brightness-up skips to hardware while gamma is lowered"
    p.call("increase")
    assert p.state()["hardwareSteps"] == 1, "brightness-up never reaches hardware at full gamma"


def check_gamma_reads(p):
    p.wait(lambda s: s["gamma"] == 65, "startup gamma never initializes")
    p.configure(read_delay=0.6)
    p.call("fetch")
    time.sleep(0.1)
    p.call("gamma", 70)
    p.wait(lambda s: s["gamma"] == 70 and p.raw("gamma") == 70, "gamma adjustment never reaches daemon")
    time.sleep(0.8)
    assert p.state()["gamma"] == 70, "stale read rolls back a gamma adjustment"
    p.configure(read_delay=0, read_invalid=True)
    p.call("fetch")
    time.sleep(0.3)
    assert p.state()["gamma"] == 70, "malformed gamma output poisons the value"
    p.configure(read_invalid=False, read_exit=1)
    (p.path / "gamma").write_text("60")
    p.call("fetch")
    time.sleep(0.3)
    assert p.state()["gamma"] == 70, "a failed command's partial output replaces gamma"
    p.configure(read_exit=0)
    p.call("fetch")
    p.wait(lambda s: s["gamma"] == 60, "gamma reads do not recover after failures")
    p.configure(write_delay=0.3)
    p.call("gamma", 50)
    time.sleep(0.1)
    p.call("gamma", 55)
    p.wait(lambda s: s["gamma"] == 55 and p.raw("gamma") == 55, "latest gamma is lost during a write")


if __name__ == "__main__":
    for check in (check_gamma, check_startup, check_latest, check_updates, check_gamma_reads):
        with tempfile.TemporaryDirectory(prefix="ii-hyprsunset-check-") as directory:
            p = Probe(directory, gamma=65 if "gamma" in check.__name__ else 100, ready_at=time.time() + 0.9)
            try:
                check(p)
            finally:
                p.close()
        print("ok: hyprsunset " + check.__name__.removeprefix("check_"))
