// The VPN tile's half that needs neither NetworkManager nor Tailscale: what their
// output says is up, and what a tap on the tile switches. services/vpn.test.js
// runs it under node.

// Vpn.qml's read: nmcli -t's TYPE,UUID,STATE,NAME, one profile a line, then "---",
// then `tailscale status --json` when Tailscale is installed and its daemon answers.
function parseState(text) {
    var parts = String(text).split(/^---$/m);
    return { connections: parseConnections(parts[0]), tailscale: parseTailscale(parts[1] || "") };
}

// WireGuard and the VPN plugins' profiles (OpenVPN, vpnc, OpenConnect...); nothing
// else NetworkManager lists is a tunnel the user brings up. The name goes last:
// it is the one field that can hold a ':'.
function parseConnections(text) {
    return String(text).split("\n").map(function (line) {
        var f = line.split(":");
        if (f.length < 4 || (f[0] !== "vpn" && f[0] !== "wireguard")) return null;
        return {
            id: "nm:" + f[1],
            kind: "nm",
            uuid: f[1],
            type: f[0],
            name: f.slice(3).join(":").replace(/\\:/g, ":"),
            state: f[2] === "activated" ? "on" : f[2] === "activating" ? "connecting" : "off",
            signedOut: false
        };
    }).filter(function (c) { return c !== null; });
}

// Tailscale's MagicDNS name for a machine is what `tailscale set --exit-node` and
// the admin console call it; HostName is only what the machine calls itself.
function peerName(p) {
    return (p.DNSName || "").split(".")[0] || p.HostName || "";
}

function parseTailscale(text) {
    var s;
    try { s = JSON.parse(text); } catch (e) { return null; }
    if (!s || !s.BackendState || s.BackendState === "NoState") return null;
    var peers = Object.keys(s.Peer || {}).map(function (k) { return s.Peer[k]; });
    // Online first, so the ones that work are the ones on top.
    var exitNodes = peers.filter(function (p) { return p.ExitNodeOption; }).map(function (p) {
        var loc = p.Location || {};
        return {
            id: p.ID,
            name: peerName(p),
            ip: (p.TailscaleIPs || [])[0] || "",
            online: !!p.Online,
            active: !!p.ExitNode,
            place: [loc.City, loc.Country].filter(Boolean).join(", ")
        };
    }).sort(function (a, b) { return (b.online - a.online) || a.name.localeCompare(b.name); });
    var via = exitNodes.filter(function (n) { return n.active; })[0];
    return {
        id: "tailscale",
        kind: "tailscale",
        type: "tailscale",
        name: "Tailscale",
        state: s.BackendState === "Running" ? "on" : s.BackendState === "Starting" ? "connecting" : "off",
        signedOut: s.BackendState === "NeedsLogin" || s.BackendState === "NeedsMachineAuth",
        account: (s.CurrentTailnet && s.CurrentTailnet.Name) || "",
        ip: (s.Self && s.Self.TailscaleIPs || [])[0] || "",
        exitNodes: exitNodes,
        exitNode: via ? via.name : ""
    };
}

// What a tap on the tile switches: whatever is up goes down, or else the last one
// used comes up, or the only one there is. A signed-out Tailscale needs a browser,
// so a tap never picks it. Empty is nothing a tap can do; the dialog opens instead.
function tileTargets(tunnels, last) {
    var up = tunnels.filter(function (t) { return t.state !== "off"; });
    if (up.length > 0) return up;
    var usable = tunnels.filter(function (t) { return !t.signedOut; });
    var pick = usable.filter(function (t) { return t.id === last; })[0] || (usable.length === 1 ? usable[0] : null);
    return pick ? [pick] : [];
}

// A failed command's stderr as the row says it: its first line, which is the
// error in both CLIs (Tailscale follows it with a sudo hint). Null is nothing said.
function failure(text) {
    var t = String(text || "");
    if (/secrets were required/i.test(t)) return "password";
    if (/access denied/i.test(t)) return "permission";
    var l = t.split("\n").map(function (s) { return s.trim(); }).filter(Boolean)[0];
    return l ? l.replace(/^Error:\s*/, "") : null;
}

if (typeof module !== "undefined")
    module.exports = {
        parseState: parseState,
        tileTargets: tileTargets,
        failure: failure
    };
