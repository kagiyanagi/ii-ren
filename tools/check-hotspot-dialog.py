#!/usr/bin/env python3
"""The hotspot dialog's switch says what the hotspot is doing, and the dialog holds still.

The switch was a `ConfigSwitch`, which runs `checked = !checked` on click. That broke its
`checked: Network.hotspotToggled` binding, so a hotspot that failed to start went on
showing as on. The row owns the state now, and its switch is not checkable.

Picking "None" used to hide the password field. That shrank the card, which re-centres,
and moved the security buttons out from under the pointer, so the next click landed
outside the card and dismissed it. The field dims instead.

The status line is evaluated under node against each state. It is the only place the
dialog says why the switch is greyed out, that a tap is in flight, or that turning the
hotspot on drops the Wi-Fi uplink.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
dialog = (II / "modules/ii/sidebarDashboard/hotspot/HotspotDialog.qml").read_text()
network = (II / "services/Network.qml").read_text()

assert "ConfigSwitch" not in dialog, "HotspotDialog: a ConfigSwitch toggles itself and breaks its checked binding"
switch = re.search(r"StyledSwitch \{(.*?)\n                \}", dialog, re.S)
assert switch, "HotspotDialog: no StyledSwitch in the switch row"
assert re.search(r"checkable:\s*false", switch.group(1)), "HotspotDialog: the switch must not be checkable"
assert re.search(r"checked:\s*Network\.hotspotToggled", switch.group(1)), "HotspotDialog: the switch must read Network.hotspotToggled"

assert not re.search(r"visible:\s*!?\s*root\.openNetwork", dialog), \
    "HotspotDialog: hiding the password field on an open network moves the buttons under the pointer"
assert re.search(r"enabled:\s*!root\.openNetwork", dialog), "HotspotDialog: the password field no longer dims for an open network"

assert re.search(r"readonly property bool hotspotSwitching:\s*startHotspotProc\.running\s*\|\|\s*stopHotspotProc\.running", network), \
    "Network: hotspotSwitching must be the start and stop processes running"
assert re.search(r"onClicked:\s*if \(!Network\.hotspotSwitching\)", dialog), "HotspotDialog: a tap mid-switch must be ignored"

body = re.search(r"readonly property string status: \{\n(.*?)\n    \}\n", dialog, re.S)
assert body, "HotspotDialog: could not lift the status binding"

JS = """
const tr = s => Object.assign(new String(s), { arg(v) { return tr(this.replace('%%1', v)); } });
const Translation = { tr };
const root = { formatBytes: b => b + ' B' };
const cases = %s;
const out = cases.map(Network => { const r = (() => { %s })(); return String(r); });
console.log(JSON.stringify(out));
"""
base = dict(hotspotSupported=True, hotspotSwitching=False, hotspotToggled=False, hotspotClientCount=0,
            hotspotRxBytes=0, hotspotTxBytes=0, wifiStatus="disconnected", networkName="")
cases = [
    ({**base, "hotspotSupported": False, "hotspotToggled": True}, "Not supported by this Wi-Fi adapter"),
    ({**base, "hotspotSwitching": True}, "Turning on…"),
    ({**base, "hotspotSwitching": True, "hotspotToggled": True}, "Turning off…"),
    ({**base, "hotspotToggled": True}, "No devices connected · 0 B used"),
    ({**base, "hotspotToggled": True, "hotspotClientCount": 1, "hotspotRxBytes": 3, "hotspotTxBytes": 4}, "1 device connected · 7 B used"),
    ({**base, "hotspotToggled": True, "hotspotClientCount": 3}, "3 devices connected · 0 B used"),
    ({**base, "wifiStatus": "connected", "networkName": "Home"}, "Disconnects from Home"),
    ({**base, "wifiStatus": "connected", "networkName": "Home", "hotspotToggled": True}, "No devices connected · 0 B used"),
    (base, "Off"),
]
src = JS % (json.dumps([c for c, _ in cases]), body.group(1))
got = json.loads(subprocess.run(["node", "-e", src], capture_output=True, text=True, check=True).stdout)
for (state, want), line in zip(cases, got):
    assert line == want, f"HotspotDialog status: {state} gave {line!r}, want {want!r}"

print(f"ok: the switch is not checkable, the dialog holds still, and {len(cases)} status lines are right")
