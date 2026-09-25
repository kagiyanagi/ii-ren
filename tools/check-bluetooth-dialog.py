#!/usr/bin/env python3
"""The Bluetooth dialog can pair, says what a device is doing, and hides nobody.

`modules/ii/sidebarDashboard/bluetoothDevices` got three things wrong, and none
of them showed up on screen:

- **Pairing went nowhere.** Quickshell implements no org.bluez.Agent1, and
  BlueZ refuses to pair while no agent is registered, so on a system without
  blueman or bluedevil every "Always connect" was a no-op that logged a warning.
  `BluetoothStatus.pair()` now borrows bluetoothctl's agent for one attempt,
  as FastPair does. `Pair()` must wait for the agent, and the agent must be let
  go on every ending. That includes the one where it never came up at all.
- **A failure looked like nothing happening.** Quickshell drops a failed
  `connect()` straight back to Disconnected and a failed `pair()` back to
  `pairing: false` with no signal of its own. The status line is the only place
  that can say so. Its order matters: a device mid-attempt must never show the
  previous attempt's error. So the expression is lifted out and evaluated.
- **A MAC address is not a name.** A nameless BLE advertiser shows up as its
  address. The filter must drop unpaired ones and never a paired one, since a
  hidden paired device could not be forgotten.

    python3 tools/check-bluetooth-dialog.py
"""

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"
SERVICE = (SHELL / "services/BluetoothStatus.qml").read_text()
ITEM = (SHELL / "modules/ii/sidebarDashboard/bluetoothDevices/BluetoothDeviceItem.qml").read_text()
DIALOG = (SHELL / "modules/ii/sidebarDashboard/bluetoothDevices/BluetoothDialog.qml").read_text()


def block(src, opener):
    """The brace-balanced body that follows `opener`."""
    start = src.find(opener)
    assert start >= 0, f"{opener!r} is gone -- this check is stale"
    i = src.index("{", start)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i + 1:j]
    raise AssertionError(f"unbalanced braces after {opener!r}")


def check_nameless_filter():
    m = re.search(r"macNameRegex:\s*/(.+)/\s*$", SERVICE, re.M)
    assert m, "macNameRegex is gone -- this check is stale"
    mac = re.compile(m.group(1))
    for name in ("61-F5-EE-19-D9-F0", "61:f5:ee:19:d9:f0"):
        assert mac.search(name), f"{name} reads as a name"
    for name in ("Nirvana Ion", "Galaxy Fit3 (1E9B)", "AA-BB-CC-DD-EE-FF Speaker"):
        assert not mac.search(name), f"{name!r} reads as an address and would be hidden"

    lists = {k: v for k, v in re.findall(r"property list<var> (\w+):(.*)", SERVICE)}
    assert "macNameRegex" in lists["unpairedDevices"], "nameless unpaired devices are listed again"
    for paired in ("connectedDevices", "pairedButNotConnectedDevices"):
        assert "macNameRegex" not in lists[paired], f"{paired} hides nameless devices -- they could not be forgotten"


def check_agent():
    agent = block(SERVICE, "Process {")
    assert re.search(r'"bluetoothctl",\s*"--agent"', SERVICE), "no agent is borrowed -- BlueZ will not pair"
    reader = block(agent, "SplitParser")
    assert '"Agent registered"' in reader and ".pair()" in reader, "Pair() does not wait for the agent"
    assert SERVICE.count(".pair()") == 1, "Pair() is called somewhere the agent may not be up yet"
    assert "root.agentUnavailable = true" in block(agent, "onRunningChanged"), \
        "a missing bluetoothctl is not reported -- it emits no exited signal, only running = false"

    end = block(SERVICE, "function endPair(")
    clear, release = end.find("root.pairTarget = null"), end.find("pairingAgent.running = false")
    assert 0 <= clear < release, \
        "endPair must clear pairTarget before releasing the agent, or onRunningChanged reads that as no bluetoothctl"
    assert re.search(r"Timer\s*\{[^}]*root\.pairTarget !== null && !root\.pairTarget\.pairing[^}]*endPair\(false\)", SERVICE), \
        "nothing ends an attempt whose agent never came up"

    start = block(SERVICE, "function pair(")
    assert "device.trusted = true" in start, "untrusted, BlueZ asks the agent to authorise services on a pipe nobody reads"
    assert "discovering = false" in start and "discovering = true" in end, "discovery is left running through the pairing"


def check_row():
    click = block(ITEM, "onClicked:")
    assert re.match(r"\s*if \(busy \|\| !device\)\s*return;", click), "a tap mid-transition starts a second attempt"
    assert "BluetoothStatus.pair(device)" in click, "an unpaired device is not paired through the borrowed agent"
    assert ".pair()" not in ITEM, "the row calls Pair() itself, with no agent"
    forget = ITEM[ITEM.index("id: forgetButton"):]
    assert ITEM.count("forget()") == 1 and "forget()" in forget, "Forget is reachable from somewhere other than its button"
    assert "return root.expanded ? 1 : 0" in forget and "visible: opacity > 0" in forget, \
        "Forget must stay one level down, behind the chevron"
    assert "PagePlaceholder" in DIALOG, "an empty list is a blank card again"


def status(**state):
    expr = block(ITEM, "text: {")
    js = f"""
    const BluetoothDeviceState = {{ Disconnected: 0, Connected: 1, Disconnecting: 2, Connecting: 3 }};
    const Translation = {{ tr: s => s }};
    const s = {json.dumps(state)};
    const device = {{ name: "x", connected: !!s.connected, batteryAvailable: "battery" in s, battery: s.battery,
                     state: s.state ?? 0, paired: !!s.paired }};
    const BluetoothStatus = {{ pairFailed: s.pairFailed ? device : null, agentUnavailable: !!s.agentUnavailable }};
    const root = {{ device, pairing: !!s.pairing, paired: device.paired, failure: s.failure ?? "",
                   connecting: device.state === 3, busy: !!s.pairing || device.state === 3 || device.state === 2 }};
    console.log(JSON.stringify((() => {{ {expr} }})()));
    """
    out = subprocess.run(["node", "-e", js], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def check_status_line():
    cases = [
        (dict(), ""),
        (dict(paired=True), "Paired"),
        (dict(paired=True, connected=True), "Connected"),
        (dict(paired=True, connected=True, battery=0.8), "Connected • 80%"),
        (dict(pairing=True), "Pairing…"),
        (dict(pairing=True, pairFailed=True), "Pairing…"),
        (dict(paired=True, state=3), "Connecting…"),
        (dict(paired=True, state=3, failure="Couldn't connect"), "Connecting…"),
        (dict(paired=True, connected=True, state=2), "Disconnecting…"),
        (dict(pairFailed=True), "Couldn't pair"),
        (dict(pairFailed=True, agentUnavailable=True), "Can't pair: bluetoothctl not available"),
        (dict(paired=True, failure="Couldn't connect"), "Couldn't connect"),
    ]
    for state, want in cases:
        got = status(**state)
        assert got == want, f"{state}: status line says {got!r}, want {want!r}"


if __name__ == "__main__":
    check_nameless_filter()
    check_agent()
    check_row()
    check_status_line()
    print("check-bluetooth-dialog: ok")
