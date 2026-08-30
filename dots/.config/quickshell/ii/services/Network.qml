pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common
import qs.services.network

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        return b.strength - a.strength;
    })
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength

    property bool hotspotSupported: false
    property bool hotspotToggled: false
    property string hotspotName: ""
    property string hotspotSsid: ""

    property string hotspotConfigSsid: ""
    property string hotspotConfigPassword: ""
    property string hotspotConfigBand: "bg"
    property string hotspotConfigSecurity: "wpa-psk"
    property int hotspotClientCount: 0
    property double hotspotRxBytes: 0
    property double hotspotTxBytes: 0
    property string hotspotDevice: ""

    property string materialSymbol: root.ethernet
        ? "lan"
        : (root.wifiEnabled && root.wifiStatus === "connected")
            ? (
                // Android 16 dropped the filled cone for the arcs and dot, and
                // ships three levels rather than five.
                (root.active?.strength ?? 0) > 66 ? "wifi" :
                (root.active?.strength ?? 0) > 33 ? "wifi_2_bar" :
                "wifi_1_bar"
            )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (root.wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // Control
    function enableWifi(enabled = true): void {
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["nmcli", "radio", "wifi", cmd]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function toggleHotspot(): void {
        if (!root.hotspotSupported) return;
        enableHotspot(!root.hotspotToggled);
    }

    function enableHotspot(enabled = true): void {
        if (!root.hotspotSupported) return;
        if (enabled) {
            startHotspotProc.running = true;
        } else {
            stopHotspotProc.running = true;
        }
    }

    function fetchHotspotConfig(): void {
        fetchHotspotConfigProc.running = true;
    }

    function fetchHotspotUsage(): void {
        fetchHotspotUsageProc.running = true;
    }

    function applyHotspotConfig(ssid: string, password: string, band: string, security: string): void {
        applyHotspotConfigProc.environment = {
            "NEW_SSID": ssid,
            "NEW_PASS": password,
            "NEW_BAND": band,
            "NEW_SEC": security
        };
        applyHotspotConfigProc.running = true;
    }

    function rescanWifi(): void {
        wifiScanning = true;
        rescanProcess.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid])

    }

    function disconnectWifiNetwork(): void {
        if (active) disconnectProc.exec(["nmcli", "connection", "down", active.ssid]);
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        changePasswordProc.exec({
            "environment": {
                "PASSWORD": password,
                "SSID": network.ssid
            },
            "command": ["bash", "-c", 'nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"']
        })
    }

    Process {
        id: enableWifiProc
    }

    Process {
        id: connectProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: line => {
                // print(line)
                getNetworks.running = true
            }
        }
        stderr: SplitParser {
            onRead: line => {
                // print("err:", line)
                if (line.includes("Secrets were required")) {
                    root.wifiConnectTarget.askingPassword = true
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.wifiConnectTarget.askingPassword = (exitCode !== 0)
            root.wifiConnectTarget = null
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
    }

    Process {
        id: changePasswordProc
        onExited: { // Re-attempt connection after changing password
            connectProc.running = false
            connectProc.running = true
        }
    }

    Process {
        id: rescanProcess
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: SplitParser {
            onRead: {
                wifiScanning = false;
                getNetworks.running = true;
            }
        }
    }

    // Status update
    function update() {
        updateConnectionType.startCheck();
        wifiStatusProcess.running = true
        updateNetworkName.running = true;
        updateNetworkStrength.running = true;
        updateHotspotStateProc.running = true;
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.update()
        }
    }

    Process {
        id: updateConnectionType
        property string buffer
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        function startCheck() {
            buffer = "";
            updateConnectionType.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                updateConnectionType.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const lines = updateConnectionType.buffer.trim().split('\n');
            const connectivity = lines.pop() // none, limited, full
            let hasEthernet = false;
            let hasWifi = false;
            let wifiStatus = "disconnected";
            lines.forEach(line => {
                if (line.includes("ethernet") && line.includes("connected"))
                    hasEthernet = true;
                else if (line.includes("wifi:")) {
                    if (line.includes("disconnected")) {
                        wifiStatus = "disconnected"
                    }
                    else if (line.includes("connected")) {
                        hasWifi = true;
                        wifiStatus = "connected"

                        if (connectivity === "limited") {
                            hasWifi = false;
                            wifiStatus = "limited"
                        }
                    }
                    else if (line.includes("connecting")) {
                        wifiStatus = "connecting"
                    }
                    else if (line.includes("unavailable")) {
                        wifiStatus = "disabled"
                    }
                }
            });
            root.wifiStatus = wifiStatus;
            root.ethernet = hasEthernet;
            root.wifi = hasWifi;
        }
    }

    Process {
        id: updateNetworkName
        command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.networkName = data;
            }
        }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\\*/{if (NR!=1) {print $2}}'"]
        stdout: SplitParser {
            onRead: data => {
                root.networkStrength = parseInt(data);
            }
        }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        Component.onCompleted: running = true
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiEnabled = text.trim() === "enabled";
            }
        }
    }

    Process {
        id: getNetworks
        running: true
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                const allNetworks = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3],
                        bssid: net[4]?.replace(rep2, ":") ?? "",
                        security: net[5] || ""
                    };
                }).filter(n => n.ssid && n.ssid.length > 0);

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map();
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid);
                    if (!existing) {
                        networkMap.set(network.ssid, network);
                    } else {
                        // Prioritize active/connected networks
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network);
                        } else if (!network.active && !existing.active) {
                            // If both are inactive, keep the one with better signal
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network);
                            }
                        }
                        // If existing is active and new is not, keep existing
                    }
                }

                const wifiNetworks = Array.from(networkMap.values());

                const rNetworks = root.wifiNetworks;

                const destroyed = rNetworks.filter(rn => !wifiNetworks.find(n => n.frequency === rn.frequency && n.ssid === rn.ssid && n.bssid === rn.bssid));
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

                for (const network of wifiNetworks) {
                    const match = rNetworks.find(n => n.frequency === network.frequency && n.ssid === network.ssid && n.bssid === network.bssid);
                    if (match) {
                        match.lastIpcObject = network;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }));
                    }
                }
            }
        }
    }

    Process {
        id: checkHotspotSupportProc
        running: true
        command: ["sh", "-c", "nmcli -t -f GENERAL.TYPE,WIFI-PROPERTIES.AP dev show | awk -F: '$1==\"GENERAL.TYPE\" && $2==\"wifi\"{w=1} w && $1==\"WIFI-PROPERTIES.AP\" && $2==\"yes\"{found=1; exit} $1==\"GENERAL.TYPE\" && $2!=\"wifi\"{w=0} END{print (found ? \"yes\" : \"no\")}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hotspotSupported = text.trim() === "yes";
            }
        }
    }

    Process {
        id: updateHotspotStateProc
        running: true
        command: ["sh", "-c", "for u in $(nmcli -t -f UUID,TYPE c show --active | awk -F: '$2==\"802-11-wireless\"{print $1}'); do if [ \"$(nmcli -g 802-11-wireless.mode c show \"$u\" 2>/dev/null)\" = \"ap\" ]; then nmcli -g connection.id,802-11-wireless.ssid c show \"$u\"; exit 0; fi; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length > 0);
                if (lines.length > 0) {
                    root.hotspotToggled = true;
                    root.hotspotName = lines[0] || "Hotspot";
                    root.hotspotSsid = lines[1] || lines[0] || "Hotspot";
                    root.fetchHotspotUsage();
                } else {
                    root.hotspotToggled = false;
                    root.hotspotName = "";
                    root.hotspotSsid = "";
                    root.hotspotClientCount = 0;
                    root.hotspotRxBytes = 0;
                    root.hotspotTxBytes = 0;
                }
            }
        }
    }

    Process {
        id: startHotspotProc
        command: ["sh", "-c", "for u in $(nmcli -t -f UUID,TYPE c show | awk -F: '$2==\"802-11-wireless\"{print $1}'); do if [ \"$(nmcli -g 802-11-wireless.mode c show \"$u\" 2>/dev/null)\" = \"ap\" ]; then nmcli connection up \"$u\" && exit 0; fi; done; nmcli dev wifi hotspot"]
        onExited: (exitCode, exitStatus) => {
            updateHotspotStateProc.running = true;
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Hotspot"),
                    Translation.tr("Failed to start hotspot. Please inspect nmcli output."),
                    "-a", "Shell"
                ]);
            }
        }
    }

    Process {
        id: stopHotspotProc
        command: ["sh", "-c", "for u in $(nmcli -t -f UUID,TYPE c show --active | awk -F: '$2==\"802-11-wireless\"{print $1}'); do if [ \"$(nmcli -g 802-11-wireless.mode c show \"$u\" 2>/dev/null)\" = \"ap\" ]; then nmcli connection down \"$u\"; fi; done; nmcli connection down Hotspot 2>/dev/null || true"]
        onExited: (exitCode, exitStatus) => {
            updateHotspotStateProc.running = true;
        }
    }

    Process {
        id: fetchHotspotConfigProc
        running: true
        command: ["sh", "-c", "UUID=$(for u in $(nmcli -t -f UUID,TYPE c show | awk -F: '$2==\"802-11-wireless\"{print $1}'); do if [ \"$(nmcli -g 802-11-wireless.mode c show \"$u\" 2>/dev/null)\" = \"ap\" ]; then echo \"$u\"; exit 0; fi; done); if [ -n \"$UUID\" ]; then SSID=$(nmcli -g 802-11-wireless.ssid c show \"$UUID\" 2>/dev/null); PASS=$(nmcli -s -g 802-11-wireless-security.psk c show \"$UUID\" 2>/dev/null); BAND=$(nmcli -g 802-11-wireless.band c show \"$UUID\" 2>/dev/null); SEC=$(nmcli -g 802-11-wireless-security.key-mgmt c show \"$UUID\" 2>/dev/null); echo \"${SSID:-Hotspot}\"; echo \"${PASS}\"; echo \"${BAND:-bg}\"; echo \"${SEC:-wpa-psk}\"; else echo \"$(hostname)-Hotspot\"; echo \"\"; echo \"bg\"; echo \"wpa-psk\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length >= 4) {
                    root.hotspotConfigSsid = lines[0];
                    root.hotspotConfigPassword = lines[1];
                    root.hotspotConfigBand = lines[2] || "bg";
                    root.hotspotConfigSecurity = lines[3] || "wpa-psk";
                }
            }
        }
    }

    Process {
        id: fetchHotspotUsageProc
        command: ["sh", "-c", "DEV=$(for u in $(nmcli -t -f UUID,TYPE,DEVICE c show --active | awk -F: '$2==\"802-11-wireless\"{print $1\":\"$3}'); do uuid=\"${u%%:*}\"; dev=\"${u##*:}\"; if [ \"$(nmcli -g 802-11-wireless.mode c show \"$uuid\" 2>/dev/null)\" = \"ap\" ]; then echo \"$dev\"; exit 0; fi; done); if [ -n \"$DEV\" ]; then CLIENTS=$(iw dev \"$DEV\" station dump 2>/dev/null | grep -c '^Station' || echo 0); BYTES=$(awk -v d=\"$DEV:\" '$1==d {print $2, $10}' /proc/net/dev); echo \"$DEV\"; echo \"$CLIENTS\"; echo \"$BYTES\"; else echo \"none\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length >= 3 && lines[0] !== "none") {
                    root.hotspotDevice = lines[0];
                    root.hotspotClientCount = parseInt(lines[1]) || 0;
                    const byteParts = lines[2].split(" ");
                    if (byteParts.length >= 2) {
                        root.hotspotRxBytes = parseFloat(byteParts[0]) || 0;
                        root.hotspotTxBytes = parseFloat(byteParts[1]) || 0;
                    }
                } else {
                    root.hotspotDevice = "";
                    root.hotspotClientCount = 0;
                    root.hotspotRxBytes = 0;
                    root.hotspotTxBytes = 0;
                }
            }
        }
    }

    Process {
        id: applyHotspotConfigProc
        command: ["bash", "-c", "UUID=$(for u in $(nmcli -t -f UUID,TYPE c show | awk -F: '$2==\"802-11-wireless\"{print $1}'); do if [ \"$(nmcli -g 802-11-wireless.mode c show \"$u\" 2>/dev/null)\" = \"ap\" ]; then echo \"$u\"; exit 0; fi; done); if [ -n \"$UUID\" ]; then nmcli connection modify \"$UUID\" 802-11-wireless.ssid \"$NEW_SSID\" 802-11-wireless.band \"$NEW_BAND\"; if [ \"$NEW_SEC\" = \"none\" ]; then nmcli connection modify \"$UUID\" 802-11-wireless-security.key-mgmt none 802-11-wireless-security.psk \"\"; else nmcli connection modify \"$UUID\" 802-11-wireless-security.key-mgmt \"$NEW_SEC\" 802-11-wireless-security.psk \"$NEW_PASS\"; fi; if [ \"$(nmcli -g GENERAL.STATE c show \"$UUID\" 2>/dev/null)\" = \"activated\" ]; then nmcli connection up \"$UUID\"; fi; else nmcli connection add type wifi ifname \"*\" con-name \"Hotspot\" autoconnect no ssid \"$NEW_SSID\" 802-11-wireless.mode ap 802-11-wireless.band \"$NEW_BAND\" ipv4.method shared; if [ \"$NEW_SEC\" = \"none\" ]; then nmcli connection modify \"Hotspot\" 802-11-wireless-security.key-mgmt none; else nmcli connection modify \"Hotspot\" 802-11-wireless-security.key-mgmt \"$NEW_SEC\" 802-11-wireless-security.psk \"$NEW_PASS\"; fi; fi"]
        onExited: (exitCode, exitStatus) => {
            fetchHotspotConfigProc.running = true;
            updateHotspotStateProc.running = true;
            if (exitCode === 0) {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Hotspot"),
                    Translation.tr("Configuration updated successfully."),
                    "-a", "Shell"
                ]);
            } else {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Hotspot"),
                    Translation.tr("Failed to apply hotspot configuration."),
                    "-a", "Shell"
                ]);
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
