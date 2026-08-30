pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Tailnet state from `tailscale status --json`.
 *
 * Polled rather than streamed: tailscale has no change signal worth the
 * plumbing, and the poll only runs while something is actually watching -
 * see `watchers`, which the Continuity page increments while it is visible.
 */
Singleton {
    id: root

    property bool installed: false
    property bool running: false
    property string backendState: ""
    property string tailnet: ""
    property string magicDnsSuffix: ""
    property var self: null
    property list<var> peers: []
    property list<string> health: []

    /** Reference count so the poll idles when no page is open. */
    property int watchers: 0

    readonly property string exitNodeIp: {
        const active = root.peers.find(p => p.exitNode);
        return active ? active.ip : "";
    }

    function refresh(): void {
        if (!root.installed) return;
        statusProc.running = false;
        statusProc.running = true;
    }

    function shortName(dnsName: string): string {
        return String(dnsName).replace(/\.$/, "").split(".")[0];
    }

    function copyIp(ip: string): void {
        Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(ip)}' | wl-copy`]);
    }
    function ssh(host: string): void {
        Quickshell.execDetached(["bash", "-c",
            `${Config.options.apps.terminal} -e tailscale ssh '${StringUtils.shellSingleQuoteEscape(host)}'`]);
    }
    function setExitNode(ip: string): void {
        // Empty ip clears it. --exit-node-allow-lan-access keeps the printer
        // and the NAS reachable while everything else is tunnelled.
        Quickshell.execDetached(["bash", "-c",
            ip === "" ? "tailscale set --exit-node=" 
                      : `tailscale set --exit-node='${StringUtils.shellSingleQuoteEscape(ip)}' --exit-node-allow-lan-access`]);
        refreshDelay.restart();
    }
    function sendFiles(host: string): void {
        sendProc.targetHost = host;
        sendProc.running = false;
        sendProc.running = true;
    }

    Timer {
        interval: 8000
        repeat: true
        running: root.installed && root.watchers > 0
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer { // `tailscale set` returns before the state settles
        id: refreshDelay
        interval: 1200
        onTriggered: root.refresh()
    }

    Process {
        id: availabilityProc
        running: true
        command: ["which", "tailscale"]
        onExited: exitCode => {
            root.installed = (exitCode === 0);
            root.refresh();
        }
    }

    Process {
        id: statusProc
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.backendState = d.BackendState ?? "";
                    root.running = root.backendState === "Running";
                    root.tailnet = d.CurrentTailnet?.Name ?? "";
                    root.magicDnsSuffix = d.MagicDNSSuffix ?? "";
                    root.health = d.Health ?? [];
                    root.self = root._toPeer(d.Self);
                    root.peers = Object.values(d.Peer ?? {})
                        .map(p => root._toPeer(p))
                        .sort((a, b) => (b.online - a.online) || a.name.localeCompare(b.name));
                } catch (e) {
                    console.warn("[Tailscale] Bad status JSON:", e);
                    root.running = false;
                }
            }
        }
    }

    Process {
        id: sendProc
        property string targetHost: ""
        command: ["bash", "-c",
            "files=$(kdialog --getopenfilename ~ --multiple --separate-output 2>/dev/null "
            + "|| zenity --file-selection --multiple --separator='\\n' 2>/dev/null); "
            + "[ -z \"$files\" ] && exit 0; "
            + "printf '%s\\n' \"$files\" | while IFS= read -r f; do "
            + "[ -n \"$f\" ] && tailscale file cp \"$f\" \"$1:\"; done",
            "bash", sendProc.targetHost]
        onExited: exitCode => {
            if (exitCode !== 0) console.warn("[Tailscale] Taildrop send failed with", exitCode);
        }
    }

    function _toPeer(p) {
        if (!p) return null;
        return {
            id: p.PublicKey ?? p.ID ?? "",
            name: p.HostName ?? "",
            dns: root.shortName(p.DNSName ?? ""),
            fqdn: String(p.DNSName ?? "").replace(/\.$/, ""),
            ip: (p.TailscaleIPs ?? [])[0] ?? "",
            os: p.OS ?? "",
            online: p.Online ?? false,
            active: p.Active ?? false,
            lastSeen: p.LastSeen ?? "",
            exitNode: p.ExitNode ?? false,
            offersExit: p.ExitNodeOption ?? false,
            // A peer with a CurAddr is peer-to-peer; without one it is going
            // through a DERP relay, which is the thing worth showing.
            direct: (p.CurAddr ?? "") !== "",
            relay: p.Relay ?? "",
            rx: p.RxBytes ?? 0,
            tx: p.TxBytes ?? 0,
            taildrop: (p.TaildropTarget ?? 0) === 1,
            ssh: Boolean((p.sshHostKeys ?? p.SSHHostKeys)?.length)
        };
    }
}
