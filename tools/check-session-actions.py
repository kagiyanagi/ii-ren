#!/usr/bin/env python3
"""Session actions must reach their owner without destroying work first.

`loginctl lock-session` only emits a signal: hypridle used to be the only thing
listening for it, so stopping the idle daemon broke both Lock and Super+L. Run
Session.qml's action under node and check the keybind reaches the shell's own
lock shortcut, which also honours the external-locker setting.

Power requests are allowed to fail (polkit, inhibitors); none may pre-emptively
kill a client. Logout uses protocol close requests and waits for clients to
leave, abandoning logout if one refuses instead of killing the compositor.
"""
import json
import importlib.util
import re
import subprocess
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parent.parent
II = ROOT / "dots/.config/quickshell/ii"
src = (II / "modules/common/functions/Session.qml").read_text()
keybinds = (ROOT / "dots/.config/hypr/hyprland/keybinds.lua").read_text()


def body(name):
    match = re.search(rf"^    function {name}\(\) \{{\n(.*?)^    \}}", src, re.M | re.S)
    assert match, f"Session.qml: missing {name}()"
    return match.group(1)


subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const calls = [];
const Quickshell = {{ execDetached: command => calls.push(command), shellPath: path => '/shell/' + path }};
(function () {{ {body('lock')} }})();
assert.deepEqual(calls, [['hyprctl', 'dispatch', 'hl.dsp.global("quickshell:lock")']],
    'Lock depends on a loginctl signal consumer instead of calling the shell');
console.log('ok: the session Lock action directly calls the shell locker');
"""], check=True)

spec = importlib.util.spec_from_file_location("logout_helper", II / "scripts/session/logout.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def simulate(snapshots, *, failed_query=False, failed_close=False):
    calls, clock = [], [0]
    replies = iter(snapshots)
    current = snapshots[0]

    def run(command, **kwargs):
        nonlocal current
        calls.append(command)
        if command == ["hyprctl", "-j", "clients"]:
            if failed_query:
                raise subprocess.CalledProcessError(1, command)
            current = next(replies, current)
            return SimpleNamespace(stdout=json.dumps(current))
        if "window.close" in command[-1] and failed_close:
            raise subprocess.CalledProcessError(1, command)
        if command[-1] == "hl.dsp.exit()":
            assert not [w for w in current if w.get("mapped", True)], "logout exited with windows still open"
        return SimpleNamespace(returncode=0)

    helper.subprocess = SimpleNamespace(run=run, CalledProcessError=subprocess.CalledProcessError)
    helper.time = SimpleNamespace(monotonic=lambda: clock[0], sleep=lambda _: clock.__setitem__(0, clock[0] + 10))
    return helper.logout(), calls


windows = [{"address": "0x123", "pid": 1}, {"address": "0x456", "pid": 1}]
dialog = [{"address": "0x789", "pid": 1}]
result, calls = simulate([windows, windows, dialog, []])
assert result == 0 and calls[-1][-1] == "hl.dsp.exit()"
closes = [c for c in calls if "window.close" in c[-1]]
assert len(closes) == 2 and all(w["address"] in c[-1] for w, c in zip(windows, closes)), \
    "logout must request each window's close, including windows sharing a process"
result, calls = simulate([windows, dialog])
assert result == 1 and not any(c[-1] == "hl.dsp.exit()" for c in calls), "a refused close ended the session"
assert any(c[0] == "notify-send" for c in calls), "a timed-out logout gave no feedback"
result, calls = simulate([[]])
assert result == 0 and calls[-1][-1] == "hl.dsp.exit()", "an empty desktop could not log out"
for options in ({"failed_query": True}, {"failed_close": True}):
    result, calls = simulate([windows], **options)
    assert result == 1 and not any(c[-1] == "hl.dsp.exit()" for c in calls), "failed IPC ended the session"
result, calls = simulate([[{"address": '0x123"; injected()'}]])
assert result == 1 and len(calls) == 1, "invalid client data reached a dispatcher"
print("ok: logout waits for windows and save dialogs, and keeps the session on refusal or failed IPC")
assert re.search(r'hl\.bind\("SUPER \+ L", hl\.dsp\.global\("quickshell:lock"\)', keybinds), \
    "Super+L must reach the shell locker without depending on hypridle"
assert 'name: "lock"' in (II / "modules/common/panels/lock/LockScreen.qml").read_text()

subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const calls = [];
const Quickshell = {{ execDetached: command => calls.push(command), shellPath: path => '/shell/' + path }};
const HyprlandData = {{ windowList: [{{ pid: 123 }}, {{ pid: 456 }}] }};
const closeAllWindows = () => {{ {body('closeAllWindows') if 'function closeAllWindows()' in src else ''} }};
const actions = {json.dumps({name: body(name) for name in ['poweroff', 'reboot', 'rebootToFirmware', 'logout']})};
for (const [name, command] of [
    ['poweroff', ['systemctl', 'poweroff']],
    ['reboot', ['systemctl', 'reboot']],
    ['rebootToFirmware', ['systemctl', 'reboot', '--firmware-setup']],
    ['logout', ['python3', '/shell/scripts/session/logout.py']],
]) {{
    calls.length = 0;
    new Function('Quickshell', 'closeAllWindows', actions[name])(Quickshell, closeAllWindows);
    assert.deepEqual(calls, [command], name + ' killed apps or skipped graceful logout');
}}
console.log('ok: refused power requests cannot kill apps; logout uses the graceful helper');
"""], check=True)
