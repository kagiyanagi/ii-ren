// node modules/ii/cheatsheet/weather_math.test.js
const assert = require("assert");
const W = require("./weather_math.js");

// 05:45 UTC is 11:15 in Delhi (+5:30) and 22:45 the day before in LA (-7).
const t = Date.UTC(2026, 8, 29, 5, 45);
assert.strictEqual(W.locationMinutes(t, 19800), 11 * 60 + 15);
assert.strictEqual(W.locationMinutes(t, -25200), 22 * 60 + 45);

// 11:15 is slot 3 (09:00); the next day runs slot 3..11.
const slots = Array.from({ length: 16 }, (_, i) => i);
assert.deepStrictEqual(W.nextDay(slots, Math.floor((11 * 60 + 15) / 180)), [3, 4, 5, 6, 7, 8, 9, 10, 11]);
assert.strictEqual(W.nextDay(slots, 7).length, 9);

// A NaN reading does not poison the range, and every span is finite and > 0.
for (const [values, pad] of [[[20, NaN, 24], 2], [[], 2], [[NaN], 0], [[18, 18, 18], 0], [[18, 18], 2]]) {
    const s = W.span(values, pad);
    assert.ok(Number.isFinite(s.lo) && Number.isFinite(s.hi) && s.hi - s.lo >= 1, JSON.stringify([values, s]));
}
assert.deepStrictEqual(W.span([20, NaN, 24], 2), { lo: 18, hi: 26 });
assert.deepStrictEqual(W.span([15, 26], 0), { lo: 15, hi: 26 });

assert.strictEqual(W.position(22, { lo: 18, hi: 26 }), 0.5);
assert.strictEqual(W.position(NaN, { lo: 18, hi: 26 }), 0);
assert.strictEqual(W.position(40, { lo: 18, hi: 26 }), 1);

// Sun: halfway at solar noon, held at the ends overnight, 0 on nonsense.
assert.strictEqual(W.isoMinutes("2026-09-29T06:12"), 372);
assert.strictEqual(W.sunFraction("2026-09-29T06:00", "2026-09-29T18:00", 12 * 60), 0.5);
assert.strictEqual(W.sunFraction("2026-09-29T06:00", "2026-09-29T18:00", 2 * 60), 0);
assert.strictEqual(W.sunFraction("2026-09-29T06:00", "2026-09-29T18:00", 23 * 60), 1);
assert.strictEqual(W.sunFraction("", undefined, 600), 0);
assert.strictEqual(W.sunFraction("2026-09-29T18:00", "2026-09-29T06:00", 600), 0);

console.log("weather_math: ok");
