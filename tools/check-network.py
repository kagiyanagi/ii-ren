#!/usr/bin/env python3
"""Network state reaches the icon without opening a dialog or bouncing the uplink.

Run the real Network.qml, RefreshProcess and KeepAliveProcess in a windowless
Quickshell with a fake nmcli on PATH. This exercises QML list bindings and process
completion, including a monitor event during a read, without touching real radios,
profiles or connections. Only the directory/translation helpers are stubbed.

    python3 tools/check-network.py
"""
import argparse
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"

FAKE_NMCLI = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
state_file = Path(os.environ["NETWORK_FIXTURE"])
def read():
    return json.loads(state_file.read_text())
args = sys.argv[1:]
state = read()
if args == ["monitor"]:
    event = state["event"]
    Path(os.environ["NETWORK_MONITOR_READY"]).touch()
    while True:
        state = read()
        if state["event"] != event:
            event = state["event"]
            print("wlan0: fixture changed", flush=True)
        time.sleep(0.02)
with open(os.environ["NETWORK_CALLS"], "a") as log:
    log.write(json.dumps(args) + "\n")
if "--rescan" in args and "list" not in args:
    print("Error: argument '--rescan' not understood without wifi list", file=sys.stderr)
    sys.exit(2)
def escape(s):
    return str(s).replace("\\", "\\\\").replace(":", "\\:")
if args == ["radio", "wifi"]:
    print(state["radio"])
elif "TYPE,STATE" in args:
    print(state["devices"])
elif "CONNECTIVITY" in args:
    print(state["connectivity"])
elif "NAME" in args:
    print("\n".join(escape(p[0]) for p in state["profiles"]))
elif "NAME,TYPE" in args:
    print("\n".join(escape(p[0]) + ":" + p[1] for p in state["profiles"]))
elif "yes" in args and "--rescan" in args:
    print(state.get("scan_output", ""), end="", flush=True)
    time.sleep(state.get("scan_delay", 0))
    sys.exit(state.get("scan_exit", 0))
elif any(a.startswith("ACTIVE,SIGNAL") for a in args):
    Path(os.environ["NETWORK_AP_STARTED"]).touch()
    time.sleep(state.get("ap_delay", 0))
    fields = args[args.index("-g") + 1].split(",")
    print("\n".join(":".join(escape(ap[f]) for f in fields) for ap in state["aps"]))
elif "IN-USE,SIGNAL,SSID" in args:
    print("IN-USE SIGNAL SSID")
    for ap in state["aps"]:
        if ap["ACTIVE"] == "yes":
            print("*", ap["SIGNAL"], ap["SSID"])
'''

PROBE = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    IpcHandler {
        target: "networkCheck"
        function snapshot(): string {
            return JSON.stringify({
                enabled: Network.wifiEnabled, status: Network.wifiStatus,
                ethernet: Network.ethernet, name: Network.networkName,
                strength: Network.networkStrength, icon: Network.materialSymbol,
                active: Network.active ? { ssid: Network.active.ssid,
                    strength: Network.active.strength, bssid: Network.active.bssid } : null,
                scanning: Network.wifiScanning
            });
        }
        function refresh(): void { Network.update(); }
        function rescan(): void { Network.rescanWifi(); }
        function disconnect(): void { Network.disconnectWifiNetwork(); }
    }
}
'''


class Probe:
    def __init__(self, directory, **initial):
        self.directory = Path(directory)
        self.state = dict(event=0, radio="enabled", devices="wifi:disconnected",
                          connectivity="full", profiles=[], aps=[])
        self.state.update(initial)
        self.fixture = self.directory / "state.json"
        self.calls_file = self.directory / "calls.jsonl"
        self.started = self.directory / "ap-started"
        self.write()
        for relative in ("services/Network.qml", "services/network/WifiAccessPoint.qml",
                         "modules/common/utils/RefreshProcess.qml", "modules/common/utils/KeepAliveProcess.qml"):
            target = self.directory / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(II / relative, target)
        stubs = {
            "modules/common/Directories.qml": 'property string scriptPath: "file:///nonexistent-network-check"',
            "modules/common/Translation.qml": 'function tr(s) { return s; }',
            "modules/common/functions/FileUtils.qml": 'function trimFileProtocol(s) { return s.replace(/^file:\\/\\//, ""); }',
        }
        for relative, body in stubs.items():
            target = self.directory / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("pragma Singleton\nimport QtQuick\nQtObject { " + body + " }\n")
        binary = self.directory / "bin/nmcli"
        binary.parent.mkdir()
        binary.write_text(FAKE_NMCLI)
        binary.chmod(0o755)
        self.shell = self.directory / "shell.qml"
        self.shell.write_text(PROBE)
        self.log = self.directory / "qs.log"
        env = {**os.environ, "PATH": str(binary.parent) + os.pathsep + os.environ["PATH"],
               "NETWORK_FIXTURE": str(self.fixture), "NETWORK_CALLS": str(self.calls_file),
               "NETWORK_AP_STARTED": str(self.started),
               "NETWORK_MONITOR_READY": str(self.directory / "monitor-ready"),
               "QT_QPA_PLATFORM": "offscreen"}
        with self.log.open("w") as log:
            self.process = subprocess.Popen(["qs", "-p", str(self.shell), "--no-color"],
                                            env=env, stdout=log, stderr=subprocess.STDOUT)

    def write(self, event=False, **changes):
        self.state.update(changes)
        self.state["event"] += int(event)
        pending = self.fixture.with_suffix(".new")
        pending.write_text(json.dumps(self.state))
        pending.replace(self.fixture)

    def call(self, method):
        result = subprocess.run(["qs", "-p", str(self.shell), "ipc", "call", "networkCheck", method],
                                capture_output=True, text=True, timeout=3)
        return result.stdout.strip() if result.returncode == 0 else ""

    def snapshot(self):
        answer = self.call("snapshot")
        return json.loads(answer) if answer else {}

    def wait(self, condition, why, timeout=3):
        deadline = time.monotonic() + timeout
        last = {}
        while time.monotonic() < deadline:
            assert self.process.poll() is None, self.log.read_text()
            last = self.snapshot()
            if last and condition(last):
                return last
            time.sleep(0.03)
        raise AssertionError(f"{why}: {last}\n{self.log.read_text()[-1500:]}")

    def calls(self):
        return [json.loads(line) for line in self.calls_file.read_text().splitlines()]

    def close(self):
        self.process.terminate()
        self.process.wait(timeout=5)


def ap(ssid, strength, active="yes", bssid="00:11:22:33:44:55", device="wlan0"):
    return dict(ACTIVE=active, SIGNAL=strength, FREQ="5240 MHz", SSID=ssid,
                BSSID=bssid, SECURITY="WPA2", DEVICE=device)


def check_refresh(probe):
    probe.wait(lambda s: s["enabled"] and (probe.directory / "monitor-ready").exists(), "probe startup")
    probe.write(event=True, devices="wifi:connected", profiles=[["Home", "802-11-wireless"]], aps=[ap("Home", 92)])
    probe.wait(lambda s: s["status"] == "connected" and s["active"] and s["icon"] == "wifi",
               "a Wi-Fi connection after startup never reaches the active AP and icon")

    probe.write(event=True, profiles=[["Cafe", "802-11-wireless"]], aps=[ap("Cafe", 25)])
    probe.wait(lambda s: s["active"] and s["active"]["ssid"] == "Cafe" and s["strength"] == 25
               and s["icon"] == "wifi_1_bar", "roaming leaves the old AP or strength")

    probe.write(event=True, aps=[ap("Cafe", 29, bssid="66:77:88:99:AA:BB"), ap("Cafe", 99, active="no")])
    probe.wait(lambda s: s["active"] and s["active"]["bssid"] == "66:77:88:99:AA:BB" and s["strength"] == 29,
               "roaming within one SSID keeps the previous BSSID or chooses a stronger inactive AP")

    # NM's monitor reports connection state, not every signal-strength update.
    probe.write(aps=[ap("Cafe", 55)])
    probe.wait(lambda s: s["active"] and s["active"]["strength"] == 55 and s["strength"] == 55
               and s["icon"] == "wifi_2_bar", "a signal-only change never reaches the icon", timeout=12)

    # An event during a slow read must queue another read, not lose the change.
    probe.started.unlink(missing_ok=True)
    probe.write(event=True, ap_delay=0.4, aps=[ap("Cafe", 15)])
    probe.wait(lambda s: probe.started.exists(), "slow AP read never started")
    probe.write(event=True, ap_delay=0, aps=[ap("Office", 89)])
    probe.wait(lambda s: s["active"] and s["active"]["ssid"] == "Office" and s["icon"] == "wifi",
               "a monitor event during an AP read was lost")
    reads = [c for c in probe.calls() if any(a.startswith("ACTIVE,SIGNAL") for a in c)]
    assert reads and all(c[-2:] == ["--rescan", "no"] for c in reads), "background reads must use NM's cache"
    probe.write(event=True, devices="wifi:disconnected", profiles=[], aps=[])
    probe.wait(lambda s: s["status"] == "disconnected" and s["active"] is None and s["strength"] == 0,
               "dropping Wi-Fi keeps an active AP or stale strength")
    print("ok: startup connection, roaming, signal-only changes and in-flight events refresh the active AP and icon")


def check_ethernet(probe):
    probe.wait(lambda s: s["enabled"] and (probe.directory / "monitor-ready").exists(), "probe startup")
    probe.write(event=True, devices="ethernet:disconnected\nwifi:connected",
                profiles=[["Home", "802-11-wireless"]], aps=[ap("Home", 90)])
    probe.wait(lambda s: s["status"] == "connected" and s["icon"] == "wifi" and not s["ethernet"],
               "an inactive ethernet cable takes the Wi-Fi icon")
    for state, connected in [("connected", True), ("disconnected", False),
                             ("connected (externally)", True), ("connecting (getting IP configuration)", False),
                             ("unavailable", False), ("unmanaged", False)]:
        probe.write(devices=f"ethernet:{state}\nwifi:connected")
        probe.call("refresh")
        # Wait for this read to finish before accepting an unchanged value.
        time.sleep(0.15)
        probe.wait(lambda s: s["ethernet"] == connected and s["icon"] == ("lan" if connected else "wifi"),
                   f"ethernet state {state!r} reports the wrong connection state")
    probe.write(event=True, devices="veth:connected\nbridge:connected\ntun:connected\nwifi:connected")
    probe.wait(lambda s: not s["ethernet"] and s["icon"] == "wifi", "a virtual interface counts as ethernet")
    print("ok: only an activated ethernet device selects the LAN icon")


def check_name(probe):
    probe.wait(lambda s: s["enabled"] and (probe.directory / "monitor-ready").exists(), "probe startup")
    virtual = [["tailscale0", "tun"], ["lo", "loopback"], ["waydroid0", "bridge"], ["VPN", "vpn"]]
    name = "Cafe: upstairs\\desk"
    probe.write(event=True, devices="wifi:connected", profiles=virtual + [[name, "802-11-wireless"]],
                aps=[ap("Cafe", 90)])
    probe.wait(lambda s: s["name"] == name, "virtual connections hide the Wi-Fi name or its escapes leak")
    probe.write(event=True, devices="wifi:connected\nethernet:connected",
                profiles=virtual + [[name, "802-11-wireless"], ["Wired: office", "802-3-ethernet"]])
    probe.wait(lambda s: s["name"] == "Wired: office" and s["icon"] == "lan",
               "the displayed name and LAN icon select different transports")
    probe.write(event=True, devices="wifi:disconnected", profiles=virtual, aps=[])
    probe.wait(lambda s: s["name"] == "" and s["active"] is None,
               "dropping Wi-Fi shows a VPN, loopback or container interface as the network")
    probe.write(event=True, devices="wifi:connected", profiles=[[name, "802-11-wireless"]], aps=[ap("Cafe", 90)])
    probe.wait(lambda s: s["name"] == name, "reconnecting does not restore the name")
    probe.write(event=True, devices="wifi:disconnected", profiles=[], aps=[])
    probe.wait(lambda s: s["name"] == "", "no active connections leaves a stale name")
    print("ok: network names select Ethernet then Wi-Fi, skip virtual links, unescape and clear on disconnect")


if __name__ == "__main__":
    checks = dict(refresh=check_refresh, ethernet=check_ethernet, name=check_name)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", choices=checks, help="run one regression instead of all of them")
    args = parser.parse_args()
    for name in ([args.check] if args.check else checks):
        with tempfile.TemporaryDirectory(prefix="ii-network-check-") as directory:
            probe = Probe(directory)
            try:
                checks[name](probe)
            finally:
                probe.close()
