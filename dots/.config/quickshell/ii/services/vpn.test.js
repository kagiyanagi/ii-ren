// node services/vpn.test.js
const assert = require("assert");
const { parseState, tileTargets, failure } = require("./vpn.js");

// nmcli -t's own shape: Wi-Fi and Tailscale's tun are not tunnels to list; a ':' in a name survives.
const nm = "802-11-wireless:05b3:activated:Home\n"
    + "tun:8f6a:activated:tailscale0\n"
    + "wireguard:aa11:activated:Work\\: office\n"
    + "vpn:bb22::Proton NL\n"
    + "vpn:cc33:activating:Uni";
const ts = JSON.stringify({
    BackendState: "Running",
    CurrentTailnet: { Name: "me@example.com" },
    Self: { TailscaleIPs: ["100.64.0.1", "fd7a::1"] },
    Peer: {
        a: { ID: "1", HostName: "pi", DNSName: "pi.tail.ts.net.", TailscaleIPs: ["100.64.0.2"], Online: false, ExitNodeOption: true },
        b: { ID: "2", HostName: "Desktop-PC", DNSName: "box.tail.ts.net.", TailscaleIPs: ["100.64.0.3"], Online: true, ExitNodeOption: true, ExitNode: true },
        c: { ID: "3", HostName: "phone", DNSName: "phone.tail.ts.net.", Online: true, ExitNodeOption: false },
        d: { ID: "4", DNSName: "nl-ams-wg-1.mullvad.ts.net.", TailscaleIPs: ["100.64.0.4"], Online: true, ExitNodeOption: true,
             Location: { City: "Amsterdam", Country: "Netherlands" } }
    }
});

const s = parseState(`${nm}\n---\n${ts}`);
assert.deepStrictEqual(s.connections.map(c => [c.name, c.type, c.state]), [
    ["Work: office", "wireguard", "on"], ["Proton NL", "vpn", "off"], ["Uni", "vpn", "connecting"]]);
assert.strictEqual(s.connections[0].uuid, "aa11");

const t = s.tailscale;
assert.strictEqual(t.state, "on");
assert.strictEqual(t.ip, "100.64.0.1");
assert.strictEqual(t.account, "me@example.com");
// The MagicDNS name, not the OS hostname; online first; a peer that offers nothing is not listed.
assert.deepStrictEqual(t.exitNodes.map(n => n.name), ["box", "nl-ams-wg-1", "pi"]);
assert.strictEqual(t.exitNode, "box");
assert.strictEqual(t.exitNodes[1].place, "Amsterdam, Netherlands");

// No VPN profiles, Tailscale absent or its daemon down: an empty list, not a broken one.
assert.deepStrictEqual(parseState("---\n"), { connections: [], tailscale: null });
assert.strictEqual(parseState("vpn:x::A\n---\nfailed to connect to local tailscaled").tailscale, null);
const out = parseState(`---\n${JSON.stringify({ BackendState: "NeedsLogin", Peer: null })}`).tailscale;
assert.deepStrictEqual([out.state, out.signedOut, out.exitNodes.length], ["off", true, 0]);

// The tile: anything up goes down, together.
const [work, proton, uni] = s.connections;
assert.deepStrictEqual(tileTargets([work, proton, uni, t], "nm:bb22").map(x => x.id), ["nm:aa11", "nm:cc33", "tailscale"]);
// Otherwise the last one used, or the only one there is.
const off = x => Object.assign({}, x, { state: "off" });
assert.deepStrictEqual(tileTargets([off(work), proton, off(t)], "nm:bb22").map(x => x.id), ["nm:bb22"]);
assert.deepStrictEqual(tileTargets([proton], "gone").map(x => x.id), ["nm:bb22"]);
// Two to choose from and no memory, or only a signed-out Tailscale: the tap opens the dialog.
assert.deepStrictEqual(tileTargets([off(work), proton], "gone"), []);
assert.deepStrictEqual(tileTargets([out], "tailscale"), []);
assert.deepStrictEqual(tileTargets([], ""), []);

assert.strictEqual(failure("Error: Connection activation failed: Secrets were required, but not provided"), "password");
// Tailscale's own refusal, word for word: the reason first, a sudo hint last.
assert.strictEqual(failure("Access denied: checkprefs access denied\n\nUse 'sudo tailscale down'.\n"
    + "To not require root, use 'sudo tailscale set --operator=$USER' once."), "permission");
assert.strictEqual(failure("Error: Connection activation failed: The VPN service stopped unexpectedly."),
    "Connection activation failed: The VPN service stopped unexpectedly.");
assert.strictEqual(failure("  "), null);

console.log("vpn ok");
