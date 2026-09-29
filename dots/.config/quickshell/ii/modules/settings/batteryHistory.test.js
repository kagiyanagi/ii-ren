// node modules/settings/batteryHistory.test.js
// Shapes are real `busctl --json=short ... GetHistory` output, newest first, with
// the 0%/state-0 marker UPower writes when it restarts.
const assert = require("assert");
const H = require("./batteryHistory.js");

const charge = H.parse(JSON.stringify({ type: "a(udu)", data: [[
    [1000, 60, 2], [700, 0, 0], [600, 80, 4], [400, 70, 1], [100, 50, 2]
]] }));
assert.deepStrictEqual(charge.map(p => p.t), [100, 400, 600, 1000], "ascending, restart marker dropped");
assert.ok(charge.every(p => p.v > 0), "no 0% dip at a restart");

// The line enters from the sample before the range and ends on the live reading.
const live = { t: 1200, v: 58, s: 2 };
const series = H.levelSeries(charge, 500, live);
assert.deepStrictEqual(series.map(p => p.t), [400, 600, 1000, 1200]);
assert.deepStrictEqual(H.levelSeries([], 500, live), [live], "no history still draws now");

// Charging then full is one span on the charger, cut at the range's edge.
assert.deepStrictEqual(H.pluggedSpans(series, 500, 1200), [[500, 1000]]);
assert.strictEqual(H.levelAt(series, 500).v, 75);
assert.strictEqual(H.levelAt(series, 50), null, "nothing is invented before the data");

// A night asleep that moved the level is a break, not a ramp; a flat plateau joins.
const night = [{ t: 0, v: 60, s: 1 }, { t: 100, v: 64, s: 1 }, { t: 100 + 36000, v: 100, s: 4 }, { t: 100 + 72000, v: 99, s: 2 }];
assert.deepStrictEqual(H.segments(night).map(r => r.length), [2, 2]);
assert.strictEqual(H.levelAt(night, 20000), null, "nothing is read out of a gap");
assert.strictEqual(Math.round(H.levelAt(night, 100 + 54000).v), 100, "the plateau still reads");
assert.deepStrictEqual(H.segments([]), []);

// Draw: only discharging counts, weighted by how long each sample stood, and a
// sample stands no longer than HOLD, so a night asleep is not time on battery.
const rate = [{ t: 0, v: 10, s: 2 }, { t: 100, v: 20, s: 2 }, { t: 300, v: 30, s: 1 }, { t: 400, v: 5, s: 2 }];
const d = H.draw(rate, [0, 200, 400 + H.HOLD + 5000], 400 + H.HOLD + 5000);
assert.deepStrictEqual(d.bins, [15, (20 * 100 + 5 * H.HOLD) / (100 + H.HOLD)]);
assert.strictEqual(d.seconds, 300 + H.HOLD);
assert.deepStrictEqual(H.draw([], [0, 10], 10), { bins: [null], seconds: 0, mean: 0 }, "no data is no bar, not NaN");
assert.deepStrictEqual(H.draw([{ t: 0, v: 0, s: 2 }], [0, 10], 10).bins, [null], "a 0 W sample at plug-in is no bar");

// Edges sit on the local clock: 25 hour marks ending past now, 8 midnights.
const now = new Date(2026, 8, 29, 13, 50).getTime() / 1000;
const day = H.edges("day", now), week = H.edges("week", now);
assert.strictEqual(day.length, 25);
assert.strictEqual(new Date(day[24] * 1000).getHours(), 14);
assert.ok(day.every(t => new Date(t * 1000).getMinutes() === 0));
assert.strictEqual(week.length, 8);
assert.ok(week.every(t => new Date(t * 1000).getHours() === 0));
assert.ok(week[7] > now && week[6] <= now);

assert.strictEqual(H.duration(45 * 60), "45 m");
assert.strictEqual(H.duration(3 * 3600 + 20 * 60), "3 h 20 m");
console.log("ok");
