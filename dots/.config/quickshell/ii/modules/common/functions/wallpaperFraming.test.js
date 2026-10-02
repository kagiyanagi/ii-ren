// node modules/common/functions/wallpaperFraming.test.js
const assert = require("assert");
const F = require("./wallpaperFraming.js");

const near = (a, b, what) => assert.ok(Math.abs(a - b) < 1e-6, `${what}: ${a} != ${b}`);
const W = 1920, H = 1080;
const def = F.entry({}, "/w.png");

// Garbage in a hand-edited file falls back instead of reaching the wallpaper's x.
const junk = F.entry({ "/w.png": { mode: "zoom", zoom: NaN, x: "1", y: null, subject: { path: "" } } }, "/w.png");
assert.deepStrictEqual(junk, def, "junk entry reads as the default");
assert.ok(F.isDefault(def));
assert.strictEqual(F.entry({ "/w.png": { y: 7 } }, "/w.png").y, 1, "out of range clamps");

// The default is what the desktop drew before framing existed: cover x baseZoom, centred.
const s = F.baseZoom(3840, 2160, W, H, 1.07, false);
near(s, 1.07, "oversized wallpaper gets the preferred zoom");
let r = F.rect(def, 3840, 2160, W, H, s);
near(r.width, W * 1.07, "cover width"); near(r.x, -(W * 1.07 - W) / 2, "centred");
// An undersized one is covered once, not zoomed again by its shortfall.
near(F.baseZoom(1280, 720, W, H, 1.07, false), 1, "undersized: no second zoom");
near(F.baseZoom(1920, 1080, W, H, 1.07, true), 1.07, "parallax gets room from an exact fit");
near(F.baseZoom(0, 0, W, H, 1.07, true), 1, "unknown size");

// Fit shows all of a 4:3 picture, bars left and right, and ignores baseZoom.
const fit = Object.assign({}, def, { mode: "fit" });
r = F.rect(fit, 1600, 1200, W, H, 1.07);
near(r.height, H, "fit height"); near(r.width, 1440, "fit width"); near(r.x, 240, "fit centred");
assert.ok(!F.covers(r, W, H), "fit leaves bars");
assert.ok(F.covers(F.rect(def, 1600, 1200, W, H, 1), W, H), "fill covers");
r = F.rect(Object.assign({}, def, { mode: "stretch" }), 1600, 1200, W, H, 1.07);
assert.deepStrictEqual([r.x, r.y, r.width, r.height], [0, 0, W, H], "stretch is the screen");

// Panning: one to one until an edge meets the screen's, then no further.
let f = Object.assign({}, def, { zoom: 2 });
r = F.rect(f, 1920, 1080, W, H, 1);
let g = F.pan(f, r, W, H, 100, 0);
near(F.rect(g, 1920, 1080, W, H, 1).x - r.x, 100, "drag moves the picture by the drag");
g = F.pan(f, r, W, H, 1e6, -1e6);
assert.deepStrictEqual([g.x, g.y], [0, 1], "clamped at the edges");
near(F.rect(g, 1920, 1080, W, H, 1).x, 0, "left edge on the screen's");
// Nothing to pan at zoom 1 on a same-shaped picture: the drag is ignored, not divided by 0.
assert.strictEqual(F.pan(def, F.rect(def, 1920, 1080, W, H, 1), W, H, 50, 50).x, 0.5);
// A 4:3 picture covering 16:9 has vertical slack at zoom 1: you can pick the top of it.
g = F.pan(def, F.rect(def, 1600, 1200, W, H, 1), W, H, 0, 1e6);
near(F.rect(g, 1600, 1200, W, H, 1).y, 0, "panned to its top");

// Zooming keeps the point under the pointer still.
f = F.zoomAt(def, 1920, 1080, W, H, 1, 2, 480, 270);
r = F.rect(f, 1920, 1080, W, H, 1);
near(r.x + (480 - 0) / W * r.width, 480, "pointer x fixed");
near(r.y + 270 / H * r.height, 270, "pointer y fixed");
assert.strictEqual(F.zoomAt(def, 1920, 1080, W, H, 1, 99, 0, 0).zoom, F.MAX_ZOOM);
assert.strictEqual(F.zoomAt(def, 1920, 1080, W, H, 1, 0.2, 0, 0).zoom, 1);

// The subject's box sits on the wallpaper, registered at its defaults.
const sub = { path: "/s.png", x: 0.5, y: 0.5, zoom: 1 };
assert.deepStrictEqual(F.subjectRect(sub, 200, 100), { x: 0, y: 0, width: 200, height: 100 });
let t = F.subjectZoomAt(sub, 0.5, 0, 0);
assert.deepStrictEqual([t.x, t.y, t.zoom], [0.25, 0.25, 0.5], "zoom about the top-left corner");
t = F.subjectPan(sub, 200, 100, 1000, -20);
assert.deepStrictEqual([t.x, t.y], [1, 0.3], "centre stays on the wallpaper");
assert.ok(!F.isDefault(Object.assign({}, def, { subject: sub })), "a subject is worth storing");

// Parallax: the default framing swings exactly as the old symmetric formula did...
const w = W * 1.07, m = (w - W) / 2;
for (const vx of [0, 0.25, 0.5, 1, 1.15, -0.15]) {
    const d = -(vx - 0.5) * 2;
    near(F.travel((W - w) / 2, w, W, d), -m - (vx - 0.5) * 2 * m, `old swing at ${vx}`);
}
// ...and one panned to its left edge never pulls that edge into the screen.
for (const d of [-1, -0.5, 0, 0.5, 1]) {
    const x = F.travel(0, w, W, d);
    assert.ok(x <= 0 && x + w >= W, `no gap at d=${d}: ${x}`);
}
assert.strictEqual(F.travel(240, 1440, W, 1), 240, "a fitted picture holds still");

console.log("ok: wallpaper framing");
