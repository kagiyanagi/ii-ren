// node services/dns.test.js
const assert = require("assert");
const { parseServers, parseState, match, modifyArgs } = require("./dns.js");

// nmcli's own output for a Wi-Fi network with a ':' in its name and Cloudflare set.
const state = "802-11-wireless:05b3cb58-5971:wlan0:Cafe\\: upstairs\n"
    + "1.1.1.1,1.0.0.1\n2606\\:4700\\:4700\\:\\:1111,2606\\:4700\\:4700\\:\\:1001\n-1\nauto\nauto";
const link = parseState(state);
assert.strictEqual(link.name, "Cafe: upstairs");
assert.strictEqual(link.device, "wlan0");
assert.deepStrictEqual(link.v6, ["2606:4700:4700::1111", "2606:4700:4700::1001"]);
assert.strictEqual(match(link), "cloudflare");
assert.strictEqual(parseState(""), null, "offline is no connection, not a broken one");

// Nothing set is the network's own; the SNI suffix and order do not hide a provider.
assert.strictEqual(match({ v4: [], v6: [] }), "auto");
assert.strictEqual(match({ v4: ["8.8.4.4#dns.google", "8.8.8.8#dns.google"], v6: [] }), "google");
assert.strictEqual(match({ v4: [], v6: ["2620:fe::9", "2620:fe::fe"] }), "quad9");
assert.strictEqual(match({ v4: ["1.1.1.1"], v6: [] }), "custom", "half a provider is the user's own list");

const parsed = parseServers(" 1.1.1.1, 2606:4700::1111\n9.9.9.9#dns.quad9.net ");
assert.deepStrictEqual(parsed, { v4: ["1.1.1.1", "9.9.9.9#dns.quad9.net"], v6: ["2606:4700::1111"], bad: [] });
assert.deepStrictEqual(parseServers("256.1.1.1 dns.google 1.1.1 ::: 1.1.1.1#a#b").bad,
    ["256.1.1.1", "dns.google", "1.1.1", ":::", "1.1.1.1#a#b"]);

// A provider takes both families, off the network's servers; encrypted tags each with its name.
assert.deepStrictEqual(modifyArgs(link, { provider: "quad9", encrypted: true }), [
    "ipv4.dns", "9.9.9.9#dns.quad9.net,149.112.112.112#dns.quad9.net", "ipv4.ignore-auto-dns", "yes",
    "ipv6.dns", "2620:fe::fe#dns.quad9.net,2620:fe::9#dns.quad9.net", "ipv6.ignore-auto-dns", "yes",
    "connection.dns-over-tls", "2"]);
// Automatic clears everything back, encryption included.
assert.deepStrictEqual(modifyArgs(link, { provider: "auto", encrypted: true }), [
    "ipv4.dns", "", "ipv4.ignore-auto-dns", "no", "ipv6.dns", "", "ipv6.ignore-auto-dns", "no",
    "connection.dns-over-tls", "-1"]);
// IPv6 off: nmcli refuses ipv6.dns outright, so it is left out.
const v4only = Object.assign({}, link, { v6Off: true });
assert.deepStrictEqual(modifyArgs(v4only, { provider: "custom", custom: "1.1.1.1 2606:4700::1111" }), [
    "ipv4.dns", "1.1.1.1", "ipv4.ignore-auto-dns", "yes", "connection.dns-over-tls", "-1"]);
// Nothing usable is no write, not a connection with no DNS.
assert.strictEqual(modifyArgs(v4only, { provider: "custom", custom: "2606:4700::1111" }), null);
assert.strictEqual(modifyArgs(link, { provider: "custom", custom: "" }), null);
assert.strictEqual(modifyArgs(link, { provider: "custom", custom: "1.1.1.1 nope" }), null);
assert.strictEqual(modifyArgs(link, { provider: "gone" }), null);

console.log("dns ok");
