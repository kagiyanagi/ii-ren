#!/usr/bin/env python3
"""Brightness stays in sync with hardware without feeding readings back as writes.

Run Brightness.qml in a windowless Quickshell with fake brightnessctl/ddcutil.
Only screens, shortcuts and other service inputs are stubbed; QML Behaviors,
Timers, Variants and Processes are real. No real display brightness is changed.

The service used to read only at startup, so external changes left sliders/OSDs
stale and the next keypress used the old value. Read/write races and anti-flashbang
feedback need real QML signal ordering, not a screenshot or a mock of the service.

    python3 tools/check-brightness.py [animation|writes|startup|refresh]
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
FAKE = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
root = Path(os.environ["BRIGHTNESS_FIXTURE"])
config = json.loads((root / "config.json").read_text())
args = sys.argv[1:]
ddc = Path(sys.argv[0]).name == "ddcutil"
bus = args[args.index("-b") + 1] if "-b" in args else "backlight"
def log(event, **extra):
    with (root / "calls.jsonl").open("a") as out:
        out.write(json.dumps(dict(event=event, bus=bus, args=args, **extra)) + "\n")
if ddc and "detect" in args:
    log("detect")
    time.sleep(config.get("detect_delay", 0))
    for i, name in enumerate(config["ddc"], 1):
        print(f"Display {i}\n I2C bus: /dev/i2c-{i}\n DRM connector: card0-{name}\n")
    if config.get("missing_query", False):
        Path(sys.argv[0]).write_text("#!/nonexistent-brightness-check-interpreter\n")
    sys.exit(config.get("detect_exit", 0))
path = root / ("raw-" + bus)
if "setvcp" in args or "s" in args or "set" in args:
    value = args[-1] if ddc else args[args.index("s") + 1]
    raw = int(value.rstrip("%"))
    log("write-start", raw=raw)
    time.sleep(config.get("write_delay", 0))
    if config.get("write_exit", 0):
        log("write-failure", raw=raw)
        sys.exit(config["write_exit"])
    path.write_text(str(raw))
    log("write-finish", raw=raw)
else:
    raw = path.read_text().strip()
    log("read", raw=raw)
    time.sleep(config.get("read_delay", 0))
    if config.get("read_fail", False):
        sys.exit(1)
    if config.get("read_invalid", False):
        print("not a brightness reading")
    elif ddc:
        print(f"VCP 10 C {raw} 100")
    elif "g" in args:
        print(raw)
    elif "m" in args:
        print(100)
    else:
        print(f"intel_backlight,backlight,{raw},{raw}%,100")
    sys.exit(config.get("read_exit", 0))
'''
PROBE = '''import QtQuick
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
    id: probe
    property int changes: 0
    Connections {
        target: Brightness
        function onBrightnessChanged() { probe.changes++; }
    }
    IpcHandler {
        target: "brightnessCheck"
        function state(): string {
            return JSON.stringify({changes: probe.changes, monitors: Brightness.monitors.map(m => ({
                ready: m.ready, brightness: m.brightness, multiplied: m.multipliedBrightness,
                ddc: m.isDdc, bus: m.busNum
            }))});
        }
        function branch(animate: bool): bool {
            const m = Brightness.monitors[0];
            m.setTimer.stop();
            m.animateChanges = animate;
            m.multipliedBrightnessChanged();
            return m.setTimer.running;
        }
        function set(index: int, value: real): void { Brightness.monitors[index].setBrightness(value); }
        function multiplier(index: int, value: real): void { Brightness.monitors[index].setBrightnessMultiplier(value); }
        function increase(): void { Brightness.increaseBrightness(); }
    }
}
'''


class Probe:
    def __init__(self, directory, screens=("eDP-1",), ddc=(), missing_ddc=False, **config):
        self.path = Path(directory)
        self.config = dict(ddc=list(ddc), **config)
        self.configure()
        for bus in ("backlight", "1", "2"):
            self.raw(bus, 50)
        source = (II / "services/Brightness.qml").read_text()
        # Substitute only the screen/shortcut inputs; keep the production logic.
        source = re.sub(r"^import qs[.\w]*\n", "", source, flags=re.M)
        source = source.replace("import Quickshell.Hyprland\n", 'import "."\n')
        source = source.replace("Quickshell.screens", "Fixture.screens").replace("ShellScreen", "var")
        (self.path / "Brightness.qml").write_text(source)
        stubs = {
            "Fixture": "property list<QtObject> screens: [" + ", ".join(
                "QtObject { property string name: " + json.dumps(n) + " }" for n in screens) + "]",
            "Config": 'property var options: ({light: {antiFlashbang: {enable: true}}})',
            "Appearance": '''property var m3colors: ({darkmode: false})
                property var animationCurves: ({expressiveEffects: [0.34, 0.8, 0.34, 1, 1, 1]})''',
            "Hyprland": "property var focusedMonitor: null; signal rawEvent(var event)",
            "Hyprsunset": "property real gamma: 100; function setGamma(v) { gamma = v; }",
            "StringUtils": "function shellSingleQuoteEscape(s) { return s; }",
        }
        for name, body in stubs.items():
            (self.path / (name + ".qml")).write_text(
                "pragma Singleton\nimport QtQuick\nQtObject {\n" + body + "\n}\n")
        (self.path / "GlobalShortcut.qml").write_text(
            "import QtQuick\nQtObject { property string name; property string description; signal pressed() }\n")
        # Shared process wrappers stay real when the service uses them.
        for name in ("RefreshProcess", "KeepAliveProcess"):
            shutil.copyfile(II / f"modules/common/utils/{name}.qml", self.path / (name + ".qml"))
        (self.path / "qmldir").write_text("\n".join(
            [f"singleton {name} 1.0 {name}.qml" for name in ["Brightness", *stubs]]
            + [f"{name} 1.0 {name}.qml" for name in ["GlobalShortcut", "RefreshProcess", "KeepAliveProcess"]]))
        (self.path / "shell.qml").write_text(PROBE)
        binary = self.path / "bin"
        binary.mkdir()
        for name in ("brightnessctl", "ddcutil"):
            command = binary / name
            command.write_text("#!/nonexistent-brightness-check-interpreter\n" if name == "ddcutil" and missing_ddc else FAKE)
            command.chmod(0o755)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", BRIGHTNESS_FIXTURE=str(self.path),
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

    def raw(self, bus, value):
        (self.path / ("raw-" + str(bus))).write_text(str(value))

    def call(self, method, *args):
        result = subprocess.run(["qs", "ipc", "--pid", str(self.process.pid), "call",
                                 "brightnessCheck", method, *map(str, args)],
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
        raise AssertionError(f"{why}: {state}\n{self.log.read_text()[-1800:]}")

    def ready(self):
        self.wait(lambda s: len(s["monitors"]) == len(self.config["ddc"] or [1])
                  and all(m["ready"] for m in s["monitors"]), "brightness never initializes")
        time.sleep(0.7)  # Let startup animation and DDC debounce settle.

    def calls(self, event):
        path = self.path / "calls.jsonl"
        return [c for line in path.read_text().splitlines() if (c := json.loads(line))["event"] == event] if path.exists() else []

    def close(self):
        self.process.terminate()
        self.process.wait(timeout=5)


@contextmanager
def probe(**config):
    with tempfile.TemporaryDirectory(prefix="ii-brightness-check-") as directory:
        p = Probe(directory, **config)
        try:
            yield p
        finally:
            p.close()


def check_animation():
    with probe() as p:
        p.ready()
        assert p.call("branch", "true") == "false", "animateChanges=true still restarts the debounce timer"
        assert p.call("branch", "false") == "true", "animateChanges=false must debounce brightness writes"


def check_writes():
    with probe(screens=("DP-1", "DP-2"), ddc=("DP-1", "DP-2")) as p:
        p.ready()
        p.configure(write_delay=0.7)
        p.call("set", 0, 0.7)
        p.call("set", 1, 0.8)
        p.wait(lambda s: (p.path / "raw-1").read_text() == "70"
               and (p.path / "raw-2").read_text() == "80",
               "one monitor's write cancels another's")

        # Both anti-flashbang adjustments must reach the hardware too.
        p.call("multiplier", 0, 0.5)
        p.call("multiplier", 1, 0.5)
        p.wait(lambda s: (p.path / "raw-1").read_text() == "35"
               and (p.path / "raw-2").read_text() == "40", "anti-flashbang drops a monitor")

        count = len(p.calls("write-start"))
        p.call("set", 0, 0.6)
        p.wait(lambda s: len(p.calls("write-start")) > count, "delayed write never starts")
        p.call("set", 0, 0.4)
        p.wait(lambda s: (p.path / "raw-1").read_text() == "20", "latest value is lost during a write")
        finished = [c["raw"] for c in p.calls("write-finish") if c["bus"] == "1"]
        assert finished[-2:] == [30, 20], f"a running DDC write was cancelled: {finished}"


def check_startup():
    for config in (dict(missing_ddc=True), dict(detect_exit=1)):
        with probe(**config) as p:
            p.ready()
            assert p.state()["monitors"][0]["brightness"] == 0.5
            p.call("increase")
            p.wait(lambda s: (p.path / "raw-backlight").read_text() == "55",
                   "first keypress starts from zero instead of the actual backlight")

    with probe(detect_delay=0.8) as p:
        p.wait(lambda s: bool(s["monitors"]), "monitor never appears")
        p.call("increase")
        p.call("set", 0, 0.05)
        assert p.state()["monitors"][0]["brightness"] == 0, "input writes an uninitialized brightness"
        p.ready()
        assert p.state()["monitors"][0]["brightness"] == 0.5


def check_refresh():
    with probe() as p:
        p.ready()
        writes = len(p.calls("write-start"))
        changes = p.state()["changes"]
        p.raw("backlight", 75)
        p.wait(lambda s: s["monitors"][0]["brightness"] == 0.75 and s["changes"] > changes,
               "an external backlight change never reaches the slider/OSD")
        time.sleep(0.3)
        assert len(p.calls("write-start")) == writes, "a hardware reading is written back"

        # A keypress before the next poll must also use the real hardware value.
        p.raw("backlight", 30)
        p.call("increase")
        p.wait(lambda s: (p.path / "raw-backlight").read_text() == "35",
               "the next keypress jumps from the cached brightness")

        p.configure(read_delay=0.6)
        count = len(p.calls("read"))
        p.wait(lambda s: len(p.calls("read")) > count, "periodic backlight read never starts")
        p.call("set", 0, 0.8)
        p.wait(lambda s: (p.path / "raw-backlight").read_text() == "80", "slider write never finishes")
        time.sleep(1)
        assert p.state()["monitors"][0]["brightness"] == 0.8, "an old read rolls back a slider gesture"

        p.configure(read_delay=0, read_invalid=True)
        time.sleep(1.3)
        assert p.state()["monitors"][0]["brightness"] == 0.8, "malformed output poisons brightness"
        p.configure(read_invalid=False, read_fail=True)
        time.sleep(1.3)
        assert p.state()["monitors"][0]["brightness"] == 0.8, "a failed read overwrites a good value"
        p.configure(read_fail=False, read_exit=1)
        p.raw("backlight", 20)
        time.sleep(1.3)
        assert p.state()["monitors"][0]["brightness"] == 0.8, "a failed command's partial output is applied"
        p.configure(read_exit=0)
        p.wait(lambda s: s["monitors"][0]["brightness"] == 0.2, "polling does not recover after failed reads")
        p.configure(write_exit=1)
        p.call("set", 0, 0.8)
        p.wait(lambda s: bool(p.calls("write-failure")) and s["monitors"][0]["brightness"] == 0.2,
               "a failed write leaves the requested value on the slider forever")
        assert writes == 0, "startup reading changes the actual brightness"

    with probe(screens=("DP-1",), ddc=("DP-1",)) as p:
        p.ready()
        p.raw("1", 65)
        p.wait(lambda s: s["monitors"][0]["brightness"] == 0.65,
               "external DDC changes never reach the service", seconds=7)
        assert not p.calls("write-start"), "DDC readback triggers a hardware write"
        p.call("set", 0, 0.8)
        p.call("multiplier", 0, 0.5)
        p.wait(lambda s: (p.path / "raw-1").read_text() == "40", "anti-flashbang never dims")
        writes = len(p.calls("write-start"))
        count = len(p.calls("read"))
        p.wait(lambda s: len(p.calls("read")) > count, "DDC polling stops after a local write", seconds=7)
        time.sleep(0.2)
        assert p.state()["monitors"][0]["brightness"] == 0.8, "readback compounds anti-flashbang dimming"
        assert len(p.calls("write-start")) == writes, "anti-flashbang readback loops into writes"

    with probe(read_invalid=True) as p:
        p.wait(lambda s: bool(p.calls("read")), "initial read never starts")
        time.sleep(0.1)
        assert not p.state()["monitors"][0]["ready"], "invalid startup output is marked ready"
        p.configure(read_invalid=False)
        p.ready()

    with probe(screens=("DP-1", "eDP-1"), ddc=("DP-1",), missing_query=True) as p:
        p.wait(lambda s: len(s["monitors"]) == 2 and s["monitors"][1]["ready"],
               "a DDC query that cannot start prevents the backlight from initializing")
        assert not p.state()["monitors"][0]["ready"]


CHECKS = {"animation": check_animation, "writes": check_writes,
          "startup": check_startup, "refresh": check_refresh}
if __name__ == "__main__":
    for name in sys.argv[1:] or CHECKS:
        CHECKS[name]()
        print("ok: brightness " + name)
