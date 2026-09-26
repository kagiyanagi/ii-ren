#!/usr/bin/env python3
"""The Wi-Fi dialog never drops the current network to ask for a password, and says how
an attempt went.

Every tap used to run `nmcli dev wifi connect` straight away. On a secured network with no
saved profile, that took the adapter off the current network, failed on "Secrets were
required", and only then showed the password field, so the machine was offline while the
password was typed. A tap on the connected row ran the connect again and bounced the link.
The password went through `nmcli connection modify "$SSID"`, which misses a profile NM had
named "SSID 1", and then re-ran the connect after its target had been nulled: both
handlers threw, and the row never said whether the password worked. Any failure, an open
network out of range included, opened a password field.

Rows were keyed on SSID + BSSID + band, so the row being typed into was destroyed whenever
a scan picked a different access point for that SSID, or missed it once.

None of this is safe to reproduce live: every real attempt takes the only adapter off the
session's uplink. So the decision, the exit handler, the saved-profile parse and the
status line are lifted out of the QML and evaluated under node.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
network = (II / "services/Network.qml").read_text()
row = (II / "modules/ii/sidebarDashboard/wifiNetworks/WifiNetworkItem.qml").read_text()
dialog = (II / "modules/ii/sidebarDashboard/wifiNetworks/WifiDialog.qml").read_text()


def lift(pattern, text, what):
    m = re.search(pattern, text, re.S)
    assert m, f"could not lift {what}"
    return m.group(1)


def node(src):
    return json.loads(subprocess.run(["node", "-e", src], capture_output=True, text=True, check=True).stdout)


# Structure: one command for a password, no profile edited by name, no bare ListView.
assert "wifi-sec.psk" not in network and "changePassword" not in network, \
    "Network: a password goes through `dev wifi connect ... password`, which updates the matching profile"
assert "changePassword" not in row, "WifiNetworkItem: Network.changePassword is gone"
assert re.search(r"onClicked:\s*if \(tappable\)", row), "WifiNetworkItem: a tap on a row that cannot act must do nothing"
assert re.search(r"rippleEnabled:\s*tappable", row), "WifiNetworkItem: a row a tap cannot act on must not ripple"
assert not re.search(r"^\s*enabled:", row.split("contentItem")[0], re.M), \
    "WifiNetworkItem: a busy row must stay at full opacity; 0.4 means disabled"
assert "backgroundHeight" not in dialog, "WifiDialog: the card fits its rows; a fixed height left a third of it empty"
assert "StyledListView" in dialog, "WifiDialog: use StyledListView"
assert "PagePlaceholder" in dialog, "WifiDialog: an empty list needs its empty state"

# Rows keyed on SSID, and a row in use outlives a scan that missed it.
reconcile = lift(r"(const destroyed = .*?)\n\s*if \(match\)", network, "the scan reconcile")
assert "bssid" not in reconcile and "frequency" not in reconcile, \
    "Network: rows are keyed on the SSID; a key with the BSSID destroyed the row being typed into"
assert "!rn.askingPassword" in reconcile and "rn !== root.wifiConnectTarget" in reconcile, \
    "Network: a network asking for a password or connecting must survive a scan that missed it"

# The tap's decision.
connect = lift(r"function connectToWifiNetwork\(accessPoint: WifiAccessPoint, password = \"\"\): void \{\n(.*?)\n    \}\n",
               network, "connectToWifiNetwork")
JS = """
const results = %s.map(([ap, password, saved, running]) => {
    const root = { savedWifiSsids: saved, wifiConnectTarget: null };
    let command = null;
    const connectProc = { running, needsSecrets: true, exec: c => { command = c; } };
    ap = Object.assign({ askingPassword: false, failure: "old" }, ap);
    (function (accessPoint, password) { %s })(ap, password);
    return { command, asking: ap.askingPassword, target: root.wifiConnectTarget === ap, failure: ap.failure,
             needsSecrets: connectProc.needsSecrets };
});
console.log(JSON.stringify(results));
"""
secured = {"ssid": "Cafe", "isSecure": True, "active": False}
cases = [
    # unsaved + secured: ask, run nothing
    ((secured, "", [], False), dict(command=None, asking=True, target=False)),
    # saved + secured: connect with no password
    ((secured, "", ["Cafe"], False), dict(command=["nmcli", "dev", "wifi", "connect", "Cafe"], asking=False, target=True)),
    # open: connect
    (({"ssid": "Free", "isSecure": False, "active": False}, "", [], False),
     dict(command=["nmcli", "dev", "wifi", "connect", "Free"], asking=False, target=True)),
    # a password: connect with it, whatever is saved
    ((secured, "hunter22", [], False),
     dict(command=["nmcli", "dev", "wifi", "connect", "Cafe", "password", "hunter22"], asking=False, target=True)),
    # connected: nothing, not even a reconnect
    (({**secured, "active": True}, "", ["Cafe"], False), dict(command=None, asking=False, target=False)),
    # another attempt running: nothing, or its exit lands on this target
    ((secured, "", ["Cafe"], True), dict(command=None, asking=False, target=False)),
]
got = node(JS % (json.dumps([c for c, _ in cases]), connect))
for (case, want), res in zip(cases, got):
    for k, v in want.items():
        assert res[k] == v, f"connectToWifiNetwork{tuple(case)}: {k} = {res[k]!r}, want {v!r}"
    if res["command"]:
        assert res["failure"] == "" and res["needsSecrets"] is False, \
            f"connectToWifiNetwork{tuple(case)}: an attempt must start with no failure and no stale secrets flag"

# How an attempt ended.
proc = lift(r"id: connectProc\n(.*?)\n    \}\n", network, "connectProc")
exited = lift(r"onExited: \(exitCode, exitStatus\) => \{\n(.*?)\n        \}", proc, "connectProc.onExited")
JS = """
const results = %s.map(([exitCode, needsSecrets]) => {
    const target = { askingPassword: false, failure: "" };
    const root = { wifiConnectTarget: target };
    const getNetworks = {}, savedWifiProc = {};
    (function (exitCode, exitStatus) { %s })(exitCode, 0);
    return { asking: target.askingPassword, failure: target.failure, cleared: root.wifiConnectTarget === null,
             refreshed: !!(getNetworks.running && savedWifiProc.running) };
});
console.log(JSON.stringify(results));
""".replace("%s })(exitCode", "const needsSecrets = arguments[2]; %s })(exitCode").replace("(exitCode, 0)", "(exitCode, 0, needsSecrets)")
cases = [
    ((0, False), dict(asking=False, failure="")),
    ((4, True), dict(asking=True, failure="password")),
    ((4, False), dict(asking=False, failure="connect")),  # out of range: no password field on an open network
]
got = node(JS % (json.dumps([c for c, _ in cases]), exited))
for (case, want), res in zip(cases, got):
    assert res["cleared"] and res["refreshed"], f"connectProc exit {case}: target not cleared or lists not refreshed"
    for k, v in want.items():
        assert res[k] == v, f"connectProc exit {case}: {k} = {res[k]!r}, want {v!r}"

# Saved profiles: one SSID per profile, blank lines between, ':' escaped.
parse = lift(r"id: savedWifiProc.*?onStreamFinished: root\.savedWifiSsids = (.*?)\n", network, "the saved-SSID parse")
got = node("const text = %s; console.log(JSON.stringify(%s));" % (json.dumps("Home\n\nCafe\\:5G\n\nAi’s iPhone\n"), parse))
assert got == ["Home", "Cafe:5G", "Ai’s iPhone"], f"saved-SSID parse gave {got!r}"

# The status line.
status = lift(r"\n\s*text: (root\.connecting \?.*?: \"\")\n", row, "the status line")
JS = """
const Translation = { tr: s => s };
console.log(JSON.stringify(%s.map(root => (%s))));
"""
base = dict(connecting=False, connected=False, failure="", saved=False)
cases = [
    (base, ""),
    ({**base, "saved": True}, "Saved"),
    ({**base, "connected": True, "saved": True}, "Connected"),
    ({**base, "connecting": True, "failure": "password"}, "Connecting…"),  # never the last attempt's error
    ({**base, "failure": "password", "saved": True}, "Wrong password"),
    ({**base, "failure": "connect"}, "Couldn't connect"),
]
got = node(JS % (json.dumps([c for c, _ in cases]), status))
for (state, want), line in zip(cases, got):
    assert line == want, f"WifiNetworkItem status: {state} gave {line!r}, want {want!r}"

print("ok: no tap drops the network to ask for a password, failures are said, and rows survive a scan")
