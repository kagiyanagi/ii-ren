// Weather arithmetic for CheatsheetWeather.qml, kept out of QML so node can
// check it: weather_math.test.js.

// Minutes past midnight on the forecast location's own clock, not this
// machine's -- a city set by hand can be timezones away.
function locationMinutes(nowMs, utcOffsetSec) {
    var d = new Date(nowMs + utcOffsetSec * 1000);
    return d.getUTCHours() * 60 + d.getUTCMinutes();
}

// Weather.hourlyData is 3-hour slots counted from midnight today, so the next
// 24 hours are nine slots starting at the current one.
function nextDay(slots, slot) {
    return slots.slice(slot, slot + 9);
}

// The range a chart divides by, over the finite readings only: one NaN poisons
// Math.min/max for the whole set. `minPad` > 0 pads it (20%, at least minPad);
// either way the span is at least 1, so a flat run never divides by zero.
function span(values, minPad) {
    var v = values.filter(Number.isFinite);
    if (!v.length)
        return { lo: 0, hi: 1 };
    var lo = Math.min.apply(null, v), hi = Math.max.apply(null, v);
    var pad = minPad > 0 ? Math.max(minPad, (hi - lo) * 0.2) : 0;
    return { lo: lo - pad, hi: Math.max(hi + pad, lo - pad + 1) };
}

// Where a reading sits in a span, 0..1. A missing one lands on 0, not NaN.
function position(value, s) {
    return Number.isFinite(value) ? Math.max(0, Math.min(1, (value - s.lo) / (s.hi - s.lo))) : 0;
}

// "2026-09-29T06:12" -> 372. NaN for anything else.
function isoMinutes(iso) {
    var hm = (String(iso || "").split("T")[1] || "").split(":");
    return parseInt(hm[0]) * 60 + parseInt(hm[1]);
}

// How far the sun is between rising and setting, 0..1, held at either end
// through the night. 0 when the times make no sense (polar day, bad data).
function sunFraction(riseIso, setIso, minutes) {
    var rise = isoMinutes(riseIso), set = isoMinutes(setIso);
    if (!(set > rise))
        return 0;
    return Math.max(0, Math.min(1, (minutes - rise) / (set - rise)));
}

if (typeof module !== "undefined")
    module.exports = { locationMinutes: locationMinutes, nextDay: nextDay, span: span,
        position: position, isoMinutes: isoMinutes, sunFraction: sunFraction };
