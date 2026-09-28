// The DNS tile's half that needs no NetworkManager: which provider a connection's
// servers are, what the user typed, and the nmcli properties that set either.
// services/dns.test.js runs it under node.

// Each with its DNS-over-TLS name, which resolved checks the certificate against.
var PROVIDERS = [
    { id: "cloudflare", name: "Cloudflare", note: "Fast and private", host: "cloudflare-dns.com",
      v4: ["1.1.1.1", "1.0.0.1"], v6: ["2606:4700:4700::1111", "2606:4700:4700::1001"] },
    { id: "google", name: "Google", note: "Public DNS", host: "dns.google",
      v4: ["8.8.8.8", "8.8.4.4"], v6: ["2001:4860:4860::8888", "2001:4860:4860::8844"] },
    { id: "quad9", name: "Quad9", note: "Blocks malware", host: "dns.quad9.net",
      v4: ["9.9.9.9", "149.112.112.112"], v6: ["2620:fe::fe", "2620:fe::9"] },
    { id: "adguard", name: "AdGuard", note: "Blocks ads and trackers", host: "dns.adguard-dns.com",
      v4: ["94.140.14.14", "94.140.15.15"], v6: ["2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"] }
];

function provider(id) {
    for (var i = 0; i < PROVIDERS.length; i++)
        if (PROVIDERS[i].id === id) return PROVIDERS[i];
    return null;
}

function isV4(ip) {
    var m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(ip);
    return !!m && m.slice(1).every(function (o) { return Number(o) <= 255; });
}

// Loose on purpose: nmcli has the real parser and says no to the rest.
function isV6(ip) {
    return /^[0-9a-fA-F:]+$/.test(ip) && ip.split(":").length >= 3 && ip.indexOf(":::") < 0;
}

function bare(server) {
    return server.split("#")[0];
}

// "1.1.1.1, 2606:4700::1111  9.9.9.9#dns.quad9.net" -> by family, and what is not an address.
function parseServers(text) {
    var out = { v4: [], v6: [], bad: [] };
    String(text).split(/[\s,]+/).forEach(function (token) {
        if (!token) return;
        var parts = token.split("#");
        var host = parts.length === 2 && /^[A-Za-z0-9.-]+$/.test(parts[1]);
        if (parts.length > 2 || (parts.length === 2 && !host)) out.bad.push(token);
        else if (isV4(parts[0])) out.v4.push(token);
        else if (isV6(parts[0])) out.v6.push(token);
        else out.bad.push(token);
    });
    return out;
}

// nmcli -g lists are comma-separated, with ':' escaped.
function list(field) {
    return field ? field.replace(/\\:/g, ":").split(",").filter(function (s) { return s.length > 0; }) : [];
}

// The shape of Dns.qml's read: "TYPE:UUID:DEVICE:NAME", then nmcli -g's ipv4.dns,
// ipv6.dns, connection.dns-over-tls, ipv4.method, ipv6.method, one per line. Nothing
// printed is no connection to set DNS on.
function parseState(text) {
    var lines = String(text).split("\n");
    var head = lines[0].split(":");
    if (head.length < 4) return null;
    return {
        uuid: head[1],
        device: head[2],
        name: head.slice(3).join(":").replace(/\\:/g, ":"),
        v4: list(lines[1]),
        v6: list(lines[2]),
        tls: lines[3] === "2" || lines[3] === "yes",
        v4Off: lines[4] === "disabled" || lines[4] === "ignore",
        v6Off: lines[5] === "disabled" || lines[5] === "ignore"
    };
}

function sameSet(a, b) {
    return a.length === b.length && a.every(function (x) { return b.indexOf(x) >= 0; });
}

// "auto", a provider id, or "custom".
function match(link) {
    var v4 = link.v4.map(bare), v6 = link.v6.map(bare);
    if (v4.length === 0 && v6.length === 0) return "auto";
    for (var i = 0; i < PROVIDERS.length; i++) {
        var p = PROVIDERS[i];
        // One family matching is enough: the other may be off on this connection.
        if ((v4.length > 0 && sameSet(v4, p.v4)) || (v4.length === 0 && sameSet(v6, p.v6))) return p.id;
    }
    return "custom";
}

// The nmcli connection-modify properties for a choice, { provider, custom, encrypted },
// or null when it leaves no server this connection can use. A family the connection
// has off takes no DNS at all: nmcli refuses the write.
function modifyArgs(link, choice) {
    var v4 = [], v6 = [];
    var auto = choice.provider === "auto";
    if (choice.provider === "custom") {
        var parsed = parseServers(choice.custom || "");
        if (parsed.bad.length > 0) return null;
        v4 = parsed.v4;
        v6 = parsed.v6;
    } else if (!auto) {
        var p = provider(choice.provider);
        if (!p) return null;
        var tag = function (ip) { return choice.encrypted ? ip + "#" + p.host : ip; };
        v4 = p.v4.map(tag);
        v6 = p.v6.map(tag);
    }
    if (link.v4Off) v4 = [];
    if (link.v6Off) v6 = [];
    if (!auto && v4.length === 0 && v6.length === 0) return null;

    // Off the network's own servers too, or resolved goes on asking them.
    var ignore = auto ? "no" : "yes";
    var args = [];
    if (!link.v4Off) args.push("ipv4.dns", v4.join(","), "ipv4.ignore-auto-dns", ignore);
    if (!link.v6Off) args.push("ipv6.dns", v6.join(","), "ipv6.ignore-auto-dns", ignore);
    // Strict, as Android's Private DNS is: no quiet fallback to plain DNS.
    args.push("connection.dns-over-tls", !auto && choice.encrypted ? "2" : "-1");
    return args;
}

if (typeof module !== "undefined")
    module.exports = {
        PROVIDERS: PROVIDERS,
        provider: provider,
        parseServers: parseServers,
        parseState: parseState,
        match: match,
        modifyArgs: modifyArgs
    };
