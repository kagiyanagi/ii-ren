#!/usr/bin/env python3
"""Shell starts must not turn Electron applications into Node processes.

The desktop launcher inherits qs's environment. Restarting qs from an Electron
agent exported ELECTRON_RUN_AS_NODE=1 into the desktop: Beeper rejected
--no-sandbox and Obsidian failed to require electron instead of opening windows.
Terminal launches worked because their environment did not contain the flag.

Run the session supervisor and CLI restart, and the actual launch commands from
setup, smoke and the restart keybind, against a fake qs. Assert the flag is absent
in the child, while Wayland, D-Bus, PATH and the requested config stay intact.
No real shell or application is started or killed.
"""
import json
import os
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUPERVISOR = ROOT / "dots/.config/hypr/hyprland/scripts/launch_quickshell.sh"
CLI = ROOT / "sdata/cli/lib/run.sh"


def background_launch(path):
    matches = re.findall(r"^\s*nohup (.*?) >", path.read_text(), re.M)
    assert len(matches) == 1, (path, matches)
    return matches[0]


keybinds = (ROOT / "dots/.config/hypr/hyprland/keybinds.lua").read_text()
restart = re.search(r'hl\.bind\("CTRL \+ SUPER \+ R", hl\.dsp\.exec_cmd\("([^"]+)"\)', keybinds)
assert restart, "restart keybind missing"
launches = {
    "session": ["bash", str(SUPERVISOR)],
    "CLI": ["bash", "-c", 'source "$1"; wait', "sh", str(CLI)],
    "setup": ["bash", "-c", background_launch(ROOT / "setup-ii-ren.sh")],
    "smoke": ["bash", "-c", background_launch(ROOT / "tools/smoke.sh")],
    "keybind": ["bash", "-c", restart[1] + " wait"],
}

with tempfile.TemporaryDirectory() as tmp:
    directory = pathlib.Path(tmp)
    capture = directory / "launch.json"
    (directory / "qs").write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, sys\n"
        "if sys.argv[1:2] == ['kill']: sys.exit(0)\n"
        "with open(os.environ['LAUNCH_CAPTURE'], 'w') as out:\n"
        " json.dump({'args': sys.argv[1:], 'env': dict(os.environ)}, out)\n"
    )
    (directory / "qs").chmod(0o755)
    for tool in ["hyprctl", "sleep", "killall"]:
        (directory / tool).write_text("#!/bin/sh\nexit 0\n")
        (directory / tool).chmod(0o755)

    for flag in [None, "1"]:
        env = dict(os.environ, PATH=f"{tmp}:{os.environ['PATH']}",
                   LAUNCH_CAPTURE=str(capture), XDG_STATE_HOME=tmp, qsConfig="ii",
                   WAYLAND_DISPLAY="wayland-launch-test",
                   DBUS_SESSION_BUS_ADDRESS="unix:path=/test/session-bus")
        env.pop("ELECTRON_RUN_AS_NODE", None)
        if flag is not None:
            env["ELECTRON_RUN_AS_NODE"] = flag
        for name, command in launches.items():
            capture.unlink(missing_ok=True)
            subprocess.run(command, env=env, check=True, timeout=5, capture_output=True)
            assert capture.exists(), f"{name}: no shell started"
            child = json.loads(capture.read_text())
            assert "ELECTRON_RUN_AS_NODE" not in child["env"], f"{name}: leaked Node mode"
            for key in ["WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "PATH"]:
                assert child["env"][key] == env[key], (name, key)
            assert "-c" in child["args"] and child["args"][child["args"].index("-c") + 1] == "ii", name

print("ok: session, CLI, setup, smoke and restart keybind clear Electron Node mode and preserve the desktop environment")
