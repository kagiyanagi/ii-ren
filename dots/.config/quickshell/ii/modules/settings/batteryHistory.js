// What the Battery page draws, out of UPower's own history: `busctl --system
// --json=short call org.freedesktop.UPower <battery> org.freedesktop.UPower.Device
// GetHistory suu charge|rate <span> <resolution>`. UPower logs a charge sample on
// every 1% step and a rate sample on every poll, and keeps about a week of them,
// so there is nothing to record here. batteryHistory.test.js checks it with `node`.

var CHARGING = 1;
var DISCHARGING = 2;
var FULL = 4;
var PENDING_CHARGE = 5;
// A sample stands for at most this long. Past it the machine was asleep or off,
// and neither is time spent on battery. Rate samples come every ~30-60s while
// awake. ponytail: fixed cap, not logind's suspend log, which says exactly when.
var HOLD = 600;

// Ascending [{ t, v, s }]. State 0 is the marker UPower writes at a daemon
// restart, always 0%: kept, it drops the line to the floor at every boot.
function parse(text) {
    return JSON.parse(text).data[0]
        .filter(r => r[2] !== 0)
        .map(r => ({ t: r[0], v: r[1], s: r[2] }))
        .sort((a, b) => a.t - b.t);
}

// Bin edges on the local clock, so the axis labels land on them: 24 hours up to
// the end of this hour, or 7 days up to the end of today.
function edges(mode, now) {
    const d = new Date(now * 1000);
    const out = [];
    if (mode === "week") {
        d.setHours(24, 0, 0, 0);
        for (let i = 0; i <= 7; i++, d.setDate(d.getDate() - 1)) out.unshift(d / 1000);
    } else {
        d.setMinutes(60, 0, 0);
        for (let i = 0; i <= 24; i++, d.setHours(d.getHours() - 1)) out.unshift(d / 1000);
    }
    return out;
}

function pluggedIn(s) {
    return s === CHARGING || s === FULL || s === PENDING_CHARGE;
}

// The charge line from the left edge to now: the last sample before `from`, so
// the line enters from the edge rather than starting mid-chart, then the live
// reading, since the newest sample can be hours old on a plateau.
function levelSeries(points, from, live) {
    let i = points.findIndex(p => p.t >= from);
    if (i === -1) i = points.length;
    return points.slice(Math.max(0, i - 1)).filter(p => p.t < live.t).concat([live]);
}

// [start, end] spans spent on the charger. A sample's state holds until the next.
function pluggedSpans(series, from, to) {
    const out = [];
    for (let i = 0; i < series.length - 1; i++) {
        if (!pluggedIn(series[i].s)) continue;
        const a = Math.max(from, series[i].t), b = Math.min(to, series[i + 1].t);
        if (b <= a) continue;
        if (out.length && out[out.length - 1][1] >= a) out[out.length - 1][1] = b;
        else out.push([a, b]);
    }
    return out;
}

// No sample for half an hour while the level moved: the machine slept or was
// off, and the path between is unknown, so the line breaks there instead of
// drawing a ramp. A long flat stretch (full, on the charger) is real and joins.
var GAP = 1800;
function isGap(a, b) {
    return b.t - a.t > GAP && Math.abs(b.v - a.v) >= 2;
}

// The series as runs to draw, split at each gap.
function segments(series) {
    const out = [];
    series.forEach((p, i) => {
        if (i === 0 || isGap(series[i - 1], p)) out.push([]);
        out[out.length - 1].push(p);
    });
    return out;
}

// Linear between samples; null outside them and inside a gap.
function levelAt(series, t) {
    for (let i = 0; i < series.length - 1; i++) {
        const a = series[i], b = series[i + 1];
        if (t < a.t || t > b.t) continue;
        if (isGap(a, b)) return null;
        return { v: b.t === a.t ? b.v : a.v + (b.v - a.v) * (t - a.t) / (b.t - a.t), s: a.s };
    }
    return null;
}

// Per bin, the time-weighted mean draw while on battery (null where the bin saw
// none), and over the whole range the same mean and how long it covers.
function draw(rate, bins, now) {
    const w = bins.slice(1).map(() => 0), e = w.slice();
    for (let i = 0; i < rate.length; i++) {
        const p = rate[i];
        // UPower logs a 0 W "discharging" sample as the charger goes in: not a draw.
        if (p.s !== DISCHARGING || p.v <= 0) continue;
        const end = Math.min(p.t + HOLD, i + 1 < rate.length ? rate[i + 1].t : now);
        for (let b = 0; b < w.length; b++) {
            const span = Math.min(end, bins[b + 1]) - Math.max(p.t, bins[b]);
            if (span <= 0) continue;
            w[b] += span;
            e[b] += span * p.v;
        }
    }
    const seconds = w.reduce((a, b) => a + b, 0);
    return {
        bins: w.map((s, b) => s > 0 ? e[b] / s : null),
        seconds: seconds,
        mean: seconds > 0 ? e.reduce((a, b) => a + b, 0) / seconds : 0
    };
}

// "3 h 20 m", "45 m". Minutes round, so a 59.6-minute estimate reads 1 h.
function duration(seconds) {
    const m = Math.round(seconds / 60);
    const h = Math.floor(m / 60);
    return h > 0 ? `${h} h ${m % 60} m` : `${m} m`;
}

if (typeof module !== "undefined")
    module.exports = { parse, edges, pluggedIn, levelSeries, pluggedSpans, segments, levelAt, draw, duration, HOLD };
