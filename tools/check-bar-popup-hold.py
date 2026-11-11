#!/usr/bin/env python3
"""An open bar popup/menu holds only its owning bar through the exit animation.

Hover ends when the pointer enters a separate popup window. The auto-hidden bar
must remain in place while that window or a nested tray menu is mapped, then
release its hold on hide/destruction, including a bar rebuild while open.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
bars = {name: (II / name).read_text() for name in (
    "modules/ii/bar/Bar.qml", "modules/ii/verticalBar/VerticalBar.qml")}
expressions = {name: re.search(r"property bool mustShow: (.*)", src).group(1) for name, src in bars.items()}
subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const hoverRegion = {{ containsMouse: false }}, superShow = false, barRoot = {{}};
const BarPopupState = {{ hasOpenPopup: window => window === barRoot }};
for (const [name, expression] of Object.entries({json.dumps(expressions)}))
    assert.equal(eval(expression), true, name + ': the bar hides while its popup is open');
console.log('ok: both bar orientations stay revealed for their open popups');
"""], check=True)

state = (II / "services/BarPopupState.qml").read_text()


def function(name, args):
    match = re.search(rf"^    function {name}\({args}\) \{{\n(.*?)^    \}}", state, re.M | re.S)
    assert match, f"BarPopupState.qml: missing {name}"
    return match.group(1)


subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const root = {{ popups: [] }};
root.setOpen = (popup, owner, open) => {{ {function('setOpen', 'popup, owner, open')} }};
root.hasOpenPopup = owner => {{ {function('hasOpenPopup', 'owner')} }};
const left = {{}}, right = {{}}, overflow = {{}}, menu = {{}}, clock = {{}};
root.setOpen(overflow, left, true);
assert.ok(root.hasOpenPopup(left));
assert.ok(!root.hasOpenPopup(right), 'a popup held bars on other monitors');
root.setOpen(menu, overflow, true);
root.setOpen(overflow, null, false);
assert.ok(root.hasOpenPopup(left), 'the nested tray menu lost its bar when its parent closed');
root.setOpen(clock, left, true);
root.setOpen(menu, null, false);
assert.ok(root.hasOpenPopup(left), 'closing one popup hid a bar with another popup open');
root.setOpen(clock, left, true);
assert.equal(root.popups.length, 1, 'reopening duplicated a hold');
root.setOpen(clock, null, false);
assert.ok(!root.hasOpenPopup(left), 'destroying the last popup left the bar held');
root.setOpen(menu, null, true);
assert.equal(root.popups.length, 0, 'an unattached popup added a hold');
console.log('ok: holds are per bar, nested menus inherit ownership, and hide/destruction releases each hold');
"""], check=True)

for name, window in (("StyledPopup.qml", "popupWindow"), ("SysTrayMenu.qml", "root")):
    popup = (II / "modules/ii/bar" / name).read_text()
    for signal in ("onVisibleChanged", "onOwnerWindowChanged", "Component.onDestruction"):
        assert re.search(rf"{signal}: BarPopupState\.setOpen\({window},", popup), \
            f"{name}: {signal} does not update the bar hold"
    assert f"BarPopupState.setOpen({window}, ownerWindow, visible)" in popup
