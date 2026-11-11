#!/usr/bin/env python3
"""An OSD appearing under a resting pointer must stay open, not flicker shut.

Run the real hover and timeout handlers: hovering pauses dismissal, more key
presses keep it paused, leaving restarts a full timeout, and a finished timeout
still closes it. The loader must release the hover state when it is destroyed.
"""
import re
import subprocess
from pathlib import Path

src = (Path(__file__).resolve().parent.parent
       / "dots/.config/quickshell/ii/modules/ii/onScreenDisplay/OnScreenDisplay.qml").read_text()
hover = re.search(r"onHoveredChanged: (.*)", src).group(1)
update = re.search(r"    function updateTimeout\(\) \{\n(.*?)\n    \}", src, re.S)
trigger = re.search(r"    function triggerOsd\(\) \{\n(.*?)\n    \}", src, re.S).group(1)
subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const GlobalStates = {{ osdVolumeOpen: true }};
const Config = {{ osdIndicatorEnabled: () => true, ready: false }};
const root = {{ hovered: true, currentIndicator: 'volume', protectionMessage: '' }};
let hovered = true;
const osdTimeout = {{ running: true, starts: 0, stop() {{ this.running = false; }},
    restart() {{ this.running = true; this.starts++; }} }};
root.updateTimeout = () => {{ {update.group(1) if update else ''} }};
const changed = () => {{ {hover} }};
changed();
assert.equal(GlobalStates.osdVolumeOpen, true, 'hovering immediately closed the OSD');
assert.equal(osdTimeout.running, false, 'the timeout kept running under the pointer');
(function () {{ {trigger} }})();
assert.equal(osdTimeout.running, false, 'a repeated key restarted dismissal while hovered');
hovered = root.hovered = false;
changed();
assert.equal(osdTimeout.running, true);
assert.equal(osdTimeout.starts, 1, 'leaving did not start one full timeout');
GlobalStates.osdVolumeOpen = false;
root.updateTimeout();
assert.equal(osdTimeout.running, false, 'a closed OSD retained its timer');
console.log('ok: hover holds the OSD, repeated keys keep it held, and leaving restarts the timeout');
"""], check=True)
assert 'property bool hovered: osdLoader.item?.hovered ?? false' in src
assert 'readonly property bool hovered: osdHover.hovered' in src
