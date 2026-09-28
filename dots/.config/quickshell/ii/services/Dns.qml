pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import "dns.js" as D

/**
 * DNS servers on the active Wi-Fi or Ethernet connection, through nmcli, so no
 * password is asked. Per connection, as NetworkManager keeps them: each network
 * remembers its own. What is set now is always read back, never assumed.
 */
Singleton {
    id: root

    readonly property var providers: D.PROVIDERS
    // parseState's result; null with no Wi-Fi or Ethernet up.
    property var link: null
    readonly property bool available: link !== null
    readonly property string provider: link ? D.match(link) : "auto"
    readonly property bool encrypted: link?.tls ?? false
    readonly property string servers: link ? [...link.v4, ...link.v6].map(s => s.split("#")[0]).join(", ") : ""
    readonly property bool busy: applyProc.running
    property bool failed: false

    // A typed server list by family, and what in it is not an address.
    function parse(text: string): var {
        return D.parseServers(text);
    }

    function refresh(): void {
        readProc.running = true;
    }

    // { provider, custom, encrypted }. False when it names no usable server, and
    // nothing is written.
    function apply(choice): bool {
        const args = link ? D.modifyArgs(link, choice) : null;
        if (!args) return false;
        root.failed = false;
        // Arguments, not a script: a custom server list is the user's text.
        applyProc.exec(["sh", "-c", 'dev=$1; shift; nmcli connection modify "$@" && nmcli device reapply "$dev"',
            "sh", link.device, link.uuid, ...args]);
        return true;
    }

    // The tile: off to the network's own servers, on to the last choice made.
    function toggle(): void {
        const last = Config.options.networking.dns;
        root.apply(root.provider !== "auto" ? { provider: "auto" }
            : { provider: last.provider, custom: last.custom, encrypted: last.encrypted });
    }

    Connections {
        target: Network
        function onNetworkNameChanged() { root.refresh(); }
        function onEthernetChanged() { root.refresh(); }
    }

    Process {
        id: readProc
        running: true
        // Ethernet first: with both up it is the one that carries the default route.
        command: ["sh", "-c", `a=$(nmcli -t -f TYPE,UUID,DEVICE,NAME connection show --active)
            line=$(printf '%s\\n' "$a" | grep -m1 '^802-3-ethernet:' || printf '%s\\n' "$a" | grep -m1 '^802-11-wireless:') || exit 0
            printf '%s\\n' "$line"
            nmcli -g ipv4.dns,ipv6.dns,connection.dns-over-tls,ipv4.method,ipv6.method connection show "$(printf '%s' "$line" | cut -d: -f2)"`]
        stdout: StdioCollector {
            onStreamFinished: root.link = D.parseState(text.trim())
        }
    }

    Process {
        id: applyProc
        onExited: (exitCode, exitStatus) => {
            root.failed = exitCode !== 0;
            root.refresh();
        }
    }
}
