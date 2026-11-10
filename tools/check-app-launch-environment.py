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

CLI/setup/smoke must delegate to a user service: nohup only ignores SIGHUP;
it cannot survive the agent's systemd scope being stopped. Model the manager's
separate environment and require launch failures to reach the caller.
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
START = ROOT / "sdata/cli/lib/start-shell.sh"


for path in [CLI, ROOT / "setup-ii-ren.sh", ROOT / "tools/smoke.sh"]:
    assert "start-shell.sh" in path.read_text(), f"{path}: bypasses independent shell service"
    assert not re.search(r"nohup .*qs -c", path.read_text()), f"{path}: shell still belongs to caller"


keybinds = (ROOT / "dots/.config/hypr/hyprland/keybinds.lua").read_text()
restart = re.search(r'hl\.bind\("CTRL \+ SUPER \+ R", hl\.dsp\.exec_cmd\("([^"]+)"\)', keybinds)
assert restart, "restart keybind missing"
launches = {
    "session": ["bash", str(SUPERVISOR)],
    "CLI": ["bash", "-c", 'source "$1"; wait', "sh", str(CLI)],
    "setup/smoke launcher": ["bash", str(START)],
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
    # Model the user manager's separate environment: only --setenv crosses over.
    # Also require a service (no --scope/--wait/--pipe tying it to the caller).
    (directory / "systemd-run").write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, sys\n"
        "args = sys.argv[1:]\n"
        "if os.environ.get('LAUNCH_SYSTEMD_FAIL'): sys.exit(73)\n"
        "with open(os.environ['LAUNCH_CAPTURE'] + '.manager', 'w') as out: json.dump(args, out)\n"
        "assert all(x in args for x in ['--user', '--collect', '--service-type=exec'])\n"
        "env = {'LAUNCH_CAPTURE': os.environ['LAUNCH_CAPTURE'], 'ELECTRON_RUN_AS_NODE': '1'}\n"
        "while args and args[0].startswith('--'):\n"
        " arg = args.pop(0)\n"
        " assert arg not in ['--scope', '--wait', '--pipe']\n"
        " if arg.startswith('--setenv='):\n"
        "  key, value = arg[len('--setenv='):].split('=', 1); env[key] = value\n"
        "os.execvpe(args[0], args, env)\n"
    )
    (directory / "systemd-run").chmod(0o755)
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

    log = directory / "shell log; $literal.log"
    subprocess.run(["bash", str(START), str(log)], env=env, check=True, timeout=5)
    manager = json.loads(pathlib.Path(str(capture) + '.manager').read_text())
    assert f"--property=StandardOutput=append:{log}" in manager, "smoke log path must be one literal argument"
    assert "--property=StandardError=inherit" in manager
    # Invoke the sourced CLI without `wait` to check its actual return status.
    failure = subprocess.run(["bash", "-c", 'source "$1"', "sh", str(CLI)],
                             env=dict(env, LAUNCH_SYSTEMD_FAIL='1'), timeout=5, capture_output=True)
    assert failure.returncode == 73, failure
    assert b"Quickshell started" not in failure.stdout, "must not report a failed launch as success"

print("ok: shell launches preserve desktop environment, clear Node mode, and use an independent service with failure reporting")
