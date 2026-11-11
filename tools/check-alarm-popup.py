#!/usr/bin/env python3
"""Fullscreen alarms must have a mounted, dismissible surface that exits visibly.

The setting used to suppress notifications without rendering anything. Keep the
popup in the shell (both families), tied to ringing and hidden under the lock,
and hold its loader until WindowDialog finishes closing.
"""
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
shell = (II / "shell.qml").read_text()
path = II / "modules/common/panels/AlarmPopup.qml"
assert path.exists(), "fullscreen alarms have no popup"
src = path.read_text()
assert "component: AlarmPopup {}" in shell, "alarm popup is not mounted"
assert 'import "modules/common/panels"' in shell
assert "active: root.rendered" in src, "popup must outlive the close request"
assert "WindowDialog {" in src, "reuse the shared dialog and its enter/exit"
assert "onDismiss: AlarmService.stopRinging()" in src
assert "onClicked: AlarmService.stopRinging()" in src
assert "WlrKeyboardFocus.Exclusive" in src, "alarm cannot receive Escape"
assert "onVisibleChanged:" in src and "!visible && !root.wanted" in src
assert "root.rendered = false" in src, "closed popup window leaks"
wanted = re.search(r"readonly property bool wanted: (.*(?:\n        .*)*)", src).group(1)
subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const Config = {{ready:true, options:{{time:{{alarms:{{useFullscreenPopup:true}}}}}}}};
const GlobalStates = {{alarmRinging:true, screenLocked:false}};
const wanted = () => ({wanted});
assert.equal(wanted(), true);
GlobalStates.screenLocked = true;
assert.equal(wanted(), false, 'private reminder appeared over the lock');
GlobalStates.screenLocked = false;
GlobalStates.alarmRinging = false;
assert.equal(wanted(), false);
GlobalStates.alarmRinging = true;
Config.options.time.alarms.useFullscreenPopup = false;
assert.equal(wanted(), false);
"""], check=True)
print("ok: fullscreen alarms have a mounted dialog, dismissal, lock gate and exit lifetime")
