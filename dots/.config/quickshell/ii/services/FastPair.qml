pragma Singleton
pragma ComponentBehavior: Bound

import "fastPairAdverts.js" as Adverts
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

/**
 * Offers nearby unpaired Bluetooth devices for one-tap pairing, like Android's
 * Fast Pair. Drives modules/ii/fastPair/FastPairPopup.qml.
 *
 * Off by default: it keeps the adapter discovering for as long as nothing is
 * connected, which costs radio time and battery.
 */
Singleton {
    id: root

    readonly property var options: Config.options.bluetooth.fastPair
    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter

    // Device currently being offered, and whether the card is up.
    property BluetoothDevice candidate: null
    property bool popupShown: false
    // A pair/connect attempt is in flight. Deliberately independent of
    // popupShown: closing the card must not abort a connect already running.
    property bool busy: false
    property bool failed: false
    // No pairing agent could be brought up, which on most systems means
    // bluetoothctl is not installed. Worth telling the user apart from an
    // ordinary failure, since nothing they do to the device will help.
    property bool agentUnavailable: false

    // address -> advert, straight from BlueZ. See fastPairAdverts.js.
    property var adverts: ({})
    // key -> ms timestamp before which a device must not be offered again.
    // Dismissing is a snooze, never a blacklist: closing the card means "not
    // now", and earbuds sitting in pairing mode are worth offering again later.
    // Permanent ignores go in options.ignoredDevices instead.
    // ponytail: in memory, so a snooze does not survive a shell restart. The
    // mute does, because it is one number; a map needs a schema in Config.
    property var suppressedUntil: ({})

    // Snoozes and permanent ignores are keyed by the address and the name
    // both, because one address is not one device. A pair of earbuds shows up
    // as two BlueZ objects during discovery - the classic one from the inquiry
    // and the LE one from the scan - with different addresses and the same
    // name, and an unbonded LE address is rotated by the peripheral every few
    // minutes. Suppressing only the address the card happened to be showing is
    // why a snooze looked like it did nothing: the sibling was offered on the
    // next dump, two seconds later.
    function identityKeys(device) {
        return [device?.address, device?.name].filter(key => !!key);
    }

    function suppressed(device) {
        const now = Date.now();
        return root.identityKeys(device).some(key => (root.suppressedUntil[key] ?? 0) > now);
    }

    function ignored(device) {
        return root.identityKeys(device).some(key => root.options.ignoredDevices.includes(key));
    }

    // Wall-clock ms before which nothing at all is offered. Kept in Config:
    // "do not offer anything for six hours" is a promise about the clock, not
    // about how long the shell happens to stay up, and a QML reload or an
    // `iiren run` used to void it.
    readonly property real mutedUntil: root.options.mutedUntil
    readonly property bool muted: root.mutedUntil > 0
    // Set by the popup while the pointer is on the card or the options are
    // open. Holds autoDismiss off; see the timer.
    property bool interacting: false

    // An unresolved name is just the MAC, which is nothing worth offering.
    readonly property var macNameRegex: /^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$/

    function pickCandidate() {
        // busy, because discovery is shared: the Bluetooth dialog or blueman
        // can hold the adapter in discovery while an attempt of ours is in
        // flight, and a dump that landed then used to overwrite the candidate
        // and clear busy - orphaning the pairing and leaking the agent.
        if (root.popupShown || root.busy || root.muted)
            return;
        let best = null;
        let bestRssi = -999;
        for (const device of (Bluetooth.devices?.values ?? [])) {
            if (!device || device.paired || device.connected || device.pairing)
                continue;
            if (root.suppressed(device))
                continue;
            if (root.ignored(device))
                continue;
            if (root.macNameRegex.test(device.name ?? ""))
                continue;
            const advert = root.adverts[device.address];
            if (!advert || advert.rssi < root.options.rssiThreshold)
                continue;
            if (root.options.audioOnly && !advert.audio)
                continue;
            if (advert.rssi > bestRssi) {
                best = device;
                bestRssi = advert.rssi;
            }
        }
        if (!best)
            return;
        root.candidate = best;
        root.busy = false;
        root.failed = false;
        root.agentUnavailable = false;
        root.popupShown = true;
    }

    function connectCandidate() {
        const device = root.candidate;
        if (!device)
            return;
        // Drops shouldScan, which stops discovery: pairing during an inquiry is
        // unreliable.
        root.busy = true;
        root.failed = false;
        root.agentUnavailable = false;
        connectTimeout.restart();
        // Trusting up front stops BlueZ asking the agent to authorize the
        // service, which the borrowed bluetoothctl agent would only prompt for
        // on a pipe nobody reads. It is also what makes the device reconnect on
        // its own next time, which is the half of Fast Pair that matters most.
        device.trusted = true;
        if (device.paired)
            return; // connectRetry takes it from here
        pairingAgent.running = true;
    }

    // Ends the attempt. Only reached once the link has actually held.
    function finishConnect() {
        console.log("FastPair: connected", root.candidate?.name ?? "device");
        root.busy = false;
        root.releaseAgent();
        root.dismiss(0);
    }

    function releaseAgent() {
        pairingAgent.running = false;
    }

    // One place to end a failed attempt. busy is cleared first so that releasing
    // the agent cannot re-enter this through pairingAgent's onRunningChanged.
    function abandon() {
        if (!root.busy)
            return;
        root.busy = false;
        connectTimeout.stop();
        settle.stop();
        root.releaseAgent();
        root.failed = true;
    }

    // Hides the card. UI only: an in-flight attempt keeps running.
    function dismiss(suppressMs) {
        const keys = suppressMs > 0 ? root.identityKeys(root.candidate) : [];
        if (keys.length > 0) {
            let next = Object.assign({}, root.suppressedUntil);
            for (const key of keys)
                next[key] = Date.now() + suppressMs;
            root.suppressedUntil = next;
        }
        root.popupShown = false;
    }

    function muteAll(ms) {
        root.options.mutedUntil = Date.now() + ms;
        root.dismiss(0);
    }

    function unmute() {
        root.options.mutedUntil = 0;
    }

    // Unlike a snooze, this survives a restart. Stored by name for the same
    // reason snoozes are: the address it was offered under may be gone in a
    // quarter of an hour. Addresses written by earlier versions still match.
    function ignoreCandidate() {
        const key = root.candidate?.name || root.candidate?.address;
        if (key && !root.options.ignoredDevices.includes(key))
            root.options.ignoredDevices = [...root.options.ignoredDevices, key];
        root.dismiss(0);
    }

    // Polled rather than armed for the remaining time: a Qt interval is not
    // the wall clock across a suspend, and a mute read back from Config at
    // startup has usually already expired.
    Timer {
        running: root.muted
        repeat: true
        triggeredOnStart: true
        interval: 30000
        onTriggered: {
            if (Date.now() >= root.mutedUntil)
                root.unmute();
        }
    }

    Connections {
        target: root.candidate
        enabled: root.candidate !== null

        // BlueZ raises the link during pairing and then tears it down a few
        // seconds later, so the first "connected" is not the real one. Wait for
        // it to hold before closing the card, otherwise connectRetry gets
        // switched off right before the drop it exists to catch.
        function onConnectedChanged() {
            if (!root.busy)
                return;
            if (!root.candidate?.connected) {
                settle.stop();
                return;
            }
            settle.restart();
        }
    }

    Timer {
        id: settle
        interval: 9000
        onTriggered: {
            if (root.candidate?.connected)
                root.finishConnect();
        }
    }

    // Pair() fails outright with "Page Timeout" when the device does not answer
    // the page, which is routine while earbuds settle into pairing mode. Keep
    // asking for as long as the attempt is alive.
    Timer {
        id: pairRetry
        running: root.busy && pairingAgent.agentReady && root.candidate && !root.candidate.paired
        repeat: true
        interval: 5000
        triggeredOnStart: true
        onTriggered: {
            console.log("FastPair: pairing", root.candidate.name);
            root.candidate.pair();
        }
    }

    // Pair() returns before BlueZ has finished SDP, and the link drops once more
    // after bonding, so a single Connect() is never enough. Quickshell exposes
    // no ServicesResolved, so keep asking until it holds or connectTimeout gives
    // up.
    Timer {
        id: connectRetry
        running: root.busy && root.candidate && root.candidate.paired && !root.candidate.connected
        repeat: true
        interval: 2000
        triggeredOnStart: true
        onTriggered: {
            console.log("FastPair: connecting", root.candidate.name);
            root.candidate.connect();
        }
    }

    Timer {
        id: connectTimeout
        interval: 60000
        onTriggered: {
            if (!root.busy)
                return;
            console.warn("FastPair: gave up on", root.candidate?.name ?? "device", "- paired =", root.candidate?.paired ?? false, "connected =", root.candidate?.connected ?? false);
            root.abandon();
        }
    }

    // Declarative, so every reason to hold it off is in one place: an attempt
    // in flight, and the pointer resting on the card or its options open. The
    // countdown used to run through the options menu, so opening it to pick an
    // hour could snooze the device for five minutes instead, mid-reach.
    Timer {
        id: autoDismiss
        running: root.popupShown && !root.busy && !root.interacting && root.options.popupTimeout > 0
        interval: 1000 * root.options.popupTimeout
        onTriggered: root.dismiss(root.options.snoozeSeconds * 1000)
    }

    // Discovery just runs whenever the adapter is idle. Short scan windows do
    // not work: a BR/EDR inquiry round takes ~10s, so a few seconds of scanning
    // turns up BLE beacons and misses the earbuds. It still stops the moment
    // anything connects, since scanning stutters A2DP.
    readonly property bool shouldScan: Config.ready && root.options.enable && !root.muted && (root.adapter?.enabled ?? false) && !BluetoothStatus.connected && !root.busy

    function applyScanState() {
        if (!root.adapter)
            return;
        // No ownership tracking: Quickshell shares one D-Bus connection across
        // the whole shell, so our discovery reference cannot be told apart from
        // the Bluetooth dialog's. Both cases where this stops scanning (pairing,
        // and a device connecting) are reasons to stop anyway.
        if (root.adapter.discovering !== root.shouldScan)
            root.adapter.discovering = root.shouldScan;
    }

    // callLater, and the guard above: all three fire in one tick at startup, and
    // BlueZ answers a second StartDiscovery before the first lands with
    // "Operation already in progress".
    onShouldScanChanged: Qt.callLater(root.applyScanState)
    onAdapterChanged: Qt.callLater(root.applyScanState)
    Component.onCompleted: Qt.callLater(root.applyScanState)

    // Quickshell's discovering setter is fire-and-forget, and BlueZ answers
    // "Resource Not Ready" while the adapter is still coming up, so one bad
    // moment at startup would otherwise kill discovery for the whole session.
    // Re-assert until it sticks; this also covers BlueZ dropping discovery on
    // its own. Costs nothing once scanning, since running goes false.
    Timer {
        running: root.shouldScan && !(root.adapter?.discovering ?? false)
        repeat: true
        interval: 3000
        onTriggered: root.applyScanState()
    }

    // Discovery can also be running because the user opened the Bluetooth dialog,
    // so this checks the option too: the singleton outlives the popup when the
    // option is switched off, and must go quiet rather than keep polling.
    Timer {
        running: root.options.enable && !root.muted && !root.busy && (root.adapter?.discovering ?? false) && !root.popupShown
        repeat: true
        interval: 2000
        triggeredOnStart: true
        onTriggered: busctlDump.running = true
    }

    // Quickshell implements no org.bluez.Agent1 (only Adapter1, Device1 and
    // Battery1) and BlueZ refuses to pair when no agent is registered anywhere
    // on the bus, so Pair() fails silently on a system with no blueman or
    // bluedevil running. bluetoothctl brings its own agent. Borrow it only for
    // the duration of the pairing, so a system that does have a proper agent
    // (one that can actually show a PIN) keeps it as the default.
    Process {
        id: pairingAgent
        property bool agentReady: false
        command: ["bluetoothctl", "--agent", "NoInputNoOutput"]
        stdinEnabled: true
        onStarted: pairingAgent.write("default-agent\n")
        onRunningChanged: {
            if (pairingAgent.running)
                return;
            pairingAgent.agentReady = false;
            if (!root.busy)
                return;
            // Quickshell emits no exited signal for a binary it could not find,
            // it just puts running back to false, so this is also how
            // "bluetoothctl is not installed" arrives. Fail now rather than
            // letting the attempt sit there until connectTimeout.
            console.warn("FastPair: pairing agent went away - is bluetoothctl installed?");
            root.agentUnavailable = true;
            root.abandon();
        }
        stdout: SplitParser {
            onRead: line => {
                if (pairingAgent.agentReady || !line.includes("Agent registered"))
                    return;
                pairingAgent.agentReady = true;
            }
        }
    }

    Process {
        id: busctlDump
        command: ["busctl", "--system", "--json=short", "call", "org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"]
        stdout: StdioCollector {
            id: dumpCollector
            onStreamFinished: {
                const parsed = Adverts.parseAdverts(dumpCollector.text);
                if (!parsed)
                    return; // busctl raced or failed; keep the previous map
                root.adverts = parsed;
                root.pickCandidate();
            }
        }
    }
}
