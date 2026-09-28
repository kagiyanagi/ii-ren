pragma Singleton

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import "vpn.js" as V

/**
 * Tunnels the user brings up by hand: NetworkManager's WireGuard and VPN-plugin
 * profiles through nmcli, and Tailscale through its CLI. What is up is always
 * read back, never assumed from what was asked for.
 */
Singleton {
    id: root

    property var connections: []
    property var tailscale: null
    readonly property var tunnels: root.tailscale ? [root.tailscale, ...root.connections] : root.connections
    readonly property var up: root.tunnels.filter(t => t.state !== "off")
    // Tunnel id (or "import", "operator") -> true while its command runs.
    property var pending: ({})
    // Tunnel id (or "import") -> vpn.js failure(): "password", or nmcli's own words.
    property var errors: ({})
    // Tailscale refuses pref writes until this user is its operator.
    property bool needsOperator: false
    property var retry: null

    // Any command that failed, from the dialog or the tile: the tile opens the
    // dialog, where the reason and any fix are.
    signal failed()

    property bool stale: false

    // A read already running may predate the change being read for: go again after it.
    function refresh(): void {
        if (readProc.running) root.stale = true;
        else readProc.running = true;
    }

    function setUp(tunnel, on: bool): void {
        if (root.pending[tunnel.id]) return;
        if (on) Config.options.networking.vpn.last = tunnel.id;
        const cmd = tunnel.kind === "tailscale"
            ? (tunnel.signedOut ? ["tailscale", "login"] : ["tailscale", on ? "up" : "down"])
            : ["nmcli", "-w", "60", "connection", on ? "up" : "down", "uuid", tunnel.uuid];
        root.run(tunnel.id, cmd);
    }

    // The tile: vpn.js tileTargets() says which. False when there is nothing to
    // switch, and the caller opens the dialog.
    function toggle(): bool {
        const targets = V.tileTargets(root.tunnels, Config.options.networking.vpn.last);
        const on = root.up.length === 0;
        targets.forEach(t => root.setUp(t, on));
        return targets.length > 0;
    }

    // An exit node's Tailscale IP, or "" for none.
    function setExitNode(ip: string): void {
        root.run("tailscale", ["tailscale", "set", `--exit-node=${ip}`]);
    }

    // The fix Tailscale's own error suggests, once, then what was refused.
    function allowOperator(): void {
        root.run("operator", ["pkexec", "tailscale", "set", `--operator=${Quickshell.env("USER")}`], () => {
            root.needsOperator = false;
            root.retry?.();
            root.retry = null;
        });
    }

    // A .ovpn is OpenVPN; anything else is taken as a wg-quick file, the usual .conf.
    function importFile(): void {
        root.run("import", ["sh", "-c", `f=$(if command -v kdialog >/dev/null; then kdialog --getopenfilename ~ '*.conf *.ovpn|VPN configuration'
            else zenity --file-selection --file-filter='VPN configuration | *.conf *.ovpn'; fi) && [ -n "$f" ] || exit 0
            case "$f" in *.ovpn) t=openvpn ;; *) t=wireguard ;; esac
            nmcli connection import type "$t" file "$f"`]);
    }

    function run(id: string, command: var, then: var): void {
        const next = Object.assign({}, root.pending);
        next[id] = true;
        root.pending = next;
        runner.createObject(root, { tunnelId: id, command: command, then: then ?? null }).running = true;
    }

    function finish(id: string, error: var): void {
        const next = Object.assign({}, root.pending);
        delete next[id];
        root.pending = next;
        const errs = Object.assign({}, root.errors);
        if (error && error !== "permission") errs[id] = error;
        else delete errs[id];
        root.errors = errs;
        if (error) root.failed();
        root.refresh();
    }

    Component {
        id: runner
        Process {
            id: proc
            property string tunnelId
            property var then
            property string errText: ""
            property bool opened: false
            stderr: SplitParser {
                onRead: line => {
                    proc.errText += line + "\n";
                    // `tailscale login`, and `up` when signed out, wait on a browser.
                    const url = line.match(/https:\/\/login\.tailscale\.com\/\S+/);
                    if (url && !proc.opened) {
                        proc.opened = true;
                        Qt.openUrlExternally(url[0]);
                    }
                }
            }
            onExited: (exitCode, exitStatus) => {
                const error = exitCode === 0 ? null : (V.failure(proc.errText) ?? "failed");
                if (error === "permission") {
                    root.needsOperator = true;
                    const command = proc.command, id = proc.tunnelId;
                    root.retry = () => root.run(id, command);
                }
                root.finish(proc.tunnelId, error);
                if (exitCode === 0) proc.then?.();
                proc.destroy();
            }
        }
    }

    // ponytail: polled while the sidebar is open, where the tile and dialog are.
    // Tailscale has no stable change stream; `tailscale debug watch-ipn` is one if
    // a bar indicator ever needs the state with the sidebar shut.
    Timer {
        running: GlobalStates.sidebarRightOpen
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: readProc
        command: ["sh", "-c", `nmcli -t -f TYPE,UUID,STATE,NAME connection show
            echo ---
            command -v tailscale >/dev/null && tailscale status --json 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = V.parseState(text);
                root.connections = s.connections;
                root.tailscale = s.tailscale;
            }
        }
        onExited: {
            if (!root.stale) return;
            root.stale = false;
            readProc.running = true;
        }
    }
}
