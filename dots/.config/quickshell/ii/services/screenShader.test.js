// node services/screenShader.test.js
const assert = require("assert");
const S = require("./screenShader.js");

assert.strictEqual(S.source({}), "", "nothing on is no shader");
assert.strictEqual(S.source({ comfort: null, reading: null, antiFlashbang: false }), "");

const comfort = S.source({ comfort: { intensity: 24 } });
assert.match(comfort, /mix\(vec3\(lum\), color, 0\.796\)/, "comfort's saturation, as the old 24% shader");
assert.match(comfort, /color \*= vec3\(1\.024, 1\.006, 0\.910\)/, "comfort's warm shift");
assert.match(comfort, /min\(color, vec3\(0\.964\)\)/, "comfort's glare cap");
assert.match(comfort, /precision mediump float/);
assert.doesNotMatch(comfort, /screenBrightness/);

const reading = S.source({ reading: { intensity: 100, paperTone: true }, comfort: { intensity: 24 } });
assert.match(reading, /mix\(color, vec3\(lum\), 1\.000\)/, "reading's grayscale");
assert.match(reading, /color\.b \* 0\.88/, "paper tone");
assert.match(reading, /vec3\(0\.964\)/, "comfort's cap still applies under reading");
assert.doesNotMatch(reading, /color \*= vec3/, "reading replaces comfort's warm shift, as before");
assert.doesNotMatch(S.source({ reading: { intensity: 50, paperTone: false } }), /0\.88/);

// The point of composing: anti-flashbang stacks on the others instead of replacing them.
const all = S.source({ comfort: { intensity: 50 }, reading: { intensity: 60 }, antiFlashbang: true });
for (const piece of [/vec3\(lum\), 0\.600/, /min\(color, vec3\(0\.925\)\)/, /screenBrightness\(\) \* 0\.75/, /precision highp/])
    assert.match(all, piece);
assert.ok(all.indexOf("min(color") < all.indexOf("screenBrightness() * 0.75"), "darkening comes last");
const alone = S.source({ antiFlashbang: true });
assert.match(alone, /screenBrightness/);
assert.doesNotMatch(alone, /vec3\(lum\)/);

// Out of range intensities clamp instead of writing GLSL that inverts the screen.
assert.match(S.source({ reading: { intensity: 250 } }), /vec3\(lum\), 1\.000\)/);
assert.match(S.source({ reading: { intensity: -5 } }), /vec3\(lum\), 0\.000\)/);

// Every float literal has a decimal point; GLSL ES rejects `mix(a, b, 1)`.
for (const glsl of [comfort, reading, all])
    assert.doesNotMatch(glsl, /[(,] ?-?\d+\)/, "an integer literal where GLSL needs a float");

assert.strictEqual(S.lua("/s/a.glsl", false),
    'hl.config({ decoration = { screen_shader = "/s/a.glsl" } }); if ii_damage_tracking ~= nil then hl.config({ debug = { damage_tracking = ii_damage_tracking } }); ii_damage_tracking = nil end');
assert.match(S.lua("/s/b.glsl", true), /^if ii_damage_tracking == nil then .*damage_tracking = 1 .*screen_shader = "\/s\/b\.glsl"/);
assert.match(S.lua('/odd "dir"/x.glsl', false), /screen_shader = "\/odd \\"dir\\"\/x\.glsl"/, "a quote cannot end the Lua string");
assert.match(S.lua("", false), /screen_shader = ""/);
console.log("ok: screen shader composes comfort view, reading mode and anti-flashbang");
