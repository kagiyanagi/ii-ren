// shellOverrides/main.lua as data, and the bookkeeping for overrides the shell sets
// for a while and takes back (game mode). tools/check-game-mode.py runs it under node
// against the real hyprset.lua.

// hyprset.lua's own lines only: one key per hl.config, `hl.config({a={b=VALUE}})` for
// "a:b". Strings are written quoted and come back unquoted, the way `hyprset key` takes
// them. A key set twice is what Hyprland runs last.
function parse(text) {
    var out = {};
    String(text).split("\n").forEach(function (line) {
        var m = /^hl\.config\(\{(.*)\}\)$/.exec(line.trim());
        if (!m) return;
        var rest = m[1];
        var parts = [];
        for (;;) {
            var name = /^([A-Za-z0-9_.]+)=/.exec(rest);
            if (!name) return;
            parts.push(name[1]);
            rest = rest.slice(name[0].length);
            if (rest[0] !== "{") break;
            rest = rest.slice(1);
        }
        var closing = parts.length - 1;
        if (closing > 0) {
            if (rest.slice(-closing) !== "}".repeat(closing)) return;
            rest = rest.slice(0, -closing);
        }
        if (rest.length >= 2 && rest[0] === '"' && rest[rest.length - 1] === '"')
            rest = rest.slice(1, -1);
        out[parts.join(":")] = rest;
    });
    return out;
}

// hyprset writes a number back as Lua prints it, so "1" and "1.0" are one value.
function same(a, b) {
    if (a === undefined || b === undefined) return a === b;
    var x = String(a).trim(), y = String(b).trim();
    if (x !== "" && y !== "" && isFinite(x) && isFinite(y)) return Number(x) === Number(y);
    return x === y;
}

// What each key's override is before the shell takes it over: [{ key, had, value }].
function snapshot(overrides, keys) {
    return keys.map(function (key) {
        var had = Object.prototype.hasOwnProperty.call(overrides, key);
        return { key: key, had: had, value: had ? String(overrides[key]) : "" };
    });
}

// Taking them back: the override each key had before, or none if it had none. A key
// that no longer holds the value the shell wrote was changed since (Settings,
// `iiren hyprset`), and that newer choice stays. A key missing from `saved` had no
// override, as far as anything recorded.
function restorePlan(saved, applied, overrides) {
    var plan = { set: {}, reset: [] };
    Object.keys(applied).forEach(function (key) {
        if (!same(overrides[key], applied[key])) return;
        var before = (saved || []).filter(function (e) { return e && e.key === key; })[0];
        if (before && before.had) plan.set[key] = before.value;
        else plan.reset.push(key);
    });
    return plan;
}

// Whether main.lua shows a change made with HyprlandSettings.updateKeys(set, reset).
function reached(overrides, change) {
    return Object.keys(change.set).every(function (key) { return same(overrides[key], change.set[key]); })
        && change.reset.every(function (key) { return !Object.prototype.hasOwnProperty.call(overrides, key); });
}

if (typeof module !== "undefined")
    module.exports = {
        parse: parse,
        same: same,
        snapshot: snapshot,
        restorePlan: restorePlan,
        reached: reached
    };
