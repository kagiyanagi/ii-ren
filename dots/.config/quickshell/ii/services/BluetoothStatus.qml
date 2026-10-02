pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick
import qs.services

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    // Connect and disconnect chimes, off the count: switching the adapter off
    // drops every device at once, and that is one sound, not one each.
    property int lastDeviceCount: 0
    onActiveDeviceCountChanged: {
        SoundService.playEvent("devices", activeDeviceCount > lastDeviceCount ? "device-added" : "device-removed");
        lastDeviceCount = activeDeviceCount;
    }

    function toggle(): void {
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
    }

    // BlueZ names a device that has not told it one after its address.
    readonly property var macNameRegex: /^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$/

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const aIsMac = root.macNameRegex.test(a.name);
        const bIsMac = root.macNameRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    // A nameless one you have never paired is a BLE advertiser nobody can
    // identify, and a café has dozens. Android hides them by default too.
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected && !root.macNameRegex.test(d.name)).sort(sortFunction)
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]

    // Pairing from the device lists, one device at a time. Quickshell
    // implements no org.bluez.Agent1, and BlueZ refuses to pair while no agent
    // is registered, so on a system without blueman or bluedevil Pair() went
    // nowhere. This borrows bluetoothctl's agent for one attempt, as FastPair
    // does.
    // ponytail: FastPair keeps its own copy of the agent because of its retry
    // loop; merge the two if a third caller appears.
    property BluetoothDevice pairTarget: null
    property BluetoothDevice pairFailed: null
    property bool agentUnavailable: false
    property bool resumeDiscovery: false

    function pair(device: BluetoothDevice): void {
        if (root.pairTarget || !device || device.paired)
            return;
        root.pairFailed = null;
        root.agentUnavailable = false;
        // Trusting it up front means BlueZ does not ask the agent to authorise
        // each service on a pipe nobody reads. It also lets the device
        // reconnect by itself next time.
        device.trusted = true;
        // Pairing during an inquiry is unreliable, so stop discovery for the
        // attempt. The dialog holds discovery on while it is open.
        root.resumeDiscovery = Bluetooth.defaultAdapter?.discovering ?? false;
        if (root.resumeDiscovery)
            Bluetooth.defaultAdapter.discovering = false;
        root.pairTarget = device;
        pairingAgent.running = true;
    }

    function endPair(ok: bool): void {
        const device = root.pairTarget;
        root.pairTarget = null;
        pairingAgent.running = false;
        if (root.resumeDiscovery && Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = true;
        root.pairFailed = ok ? null : device;
        // Pairing does not always bring up the profiles.
        if (ok && !device.connected)
            device.connect();
    }

    Connections {
        target: root.pairTarget
        // Quickshell holds `pairing` true for exactly the length of the Pair()
        // call, and `paired` has already been updated by the time it drops.
        function onPairingChanged() {
            if (!root.pairTarget.pairing)
                root.endPair(root.pairTarget.paired);
        }
    }

    // Only covers the agent coming up. Once Pair() is in flight, the D-Bus call
    // has its own timeout, and `pairing` drops when that fires.
    Timer {
        running: root.pairTarget !== null && !root.pairTarget.pairing
        interval: 10000
        onTriggered: root.endPair(false)
    }

    Process {
        id: pairingAgent
        command: ["bluetoothctl", "--agent", "NoInputNoOutput"]
        stdinEnabled: true
        onStarted: pairingAgent.write("default-agent\n")
        onRunningChanged: {
            if (pairingAgent.running || !root.pairTarget)
                return;
            // A binary that is not there emits no exited signal: running just
            // goes back to false. That is how "no bluetoothctl" arrives.
            root.agentUnavailable = true;
            root.endPair(false);
        }
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("Agent registered") && root.pairTarget && !root.pairTarget.pairing)
                    root.pairTarget.pair();
            }
        }
    }
}
