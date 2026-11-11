#!/usr/bin/env python3
"""Session actions must reach their owner without destroying work first.

`loginctl lock-session` only emits a signal: hypridle used to be the only thing
listening for it, so stopping the idle daemon broke both Lock and Super+L. Run
Session.qml's action under node and check the keybind reaches the shell's own
lock shortcut, which also honours the external-locker setting.
"""
import re
import subprocess
from pathlib import Path

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
const Quickshell = {{ execDetached: command => calls.push(command) }};
(function () {{ {body('lock')} }})();
assert.deepEqual(calls, [['hyprctl', 'dispatch', 'hl.dsp.global("quickshell:lock")']],
    'Lock depends on a loginctl signal consumer instead of calling the shell');
console.log('ok: the session Lock action directly calls the shell locker');
"""], check=True)
assert re.search(r'hl\.bind\("SUPER \+ L", hl\.dsp\.global\("quickshell:lock"\)', keybinds), \
    "Super+L must reach the shell locker without depending on hypridle"
assert 'name: "lock"' in (II / "modules/common/panels/lock/LockScreen.qml").read_text()
