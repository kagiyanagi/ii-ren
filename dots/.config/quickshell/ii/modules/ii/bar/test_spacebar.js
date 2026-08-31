// Self-check: node modules/ii/bar/test_spacebar.js
const assert = require("assert");

function getItemStyle(modelData) {
    const raw = (modelData && (modelData.style || modelData.type)) ? (modelData.style || modelData.type) : "pipe";
    const s = raw.toString().toLowerCase();
    if (s === "line" || s === "pipe") return "pipe";
    if (s === "dot" || s === "circle") return "dot";
    if (s === "dash" || s === "hyphen") return "dash";
    if (s === "empty" || s === "space" || s === "none") return "empty";
    return "pipe";
}

function getPadding(modelData) {
    const leftPadding = Math.max(0, Number(modelData && modelData.leftPadding !== undefined ? modelData.leftPadding : (modelData && modelData.paddingLeft !== undefined ? modelData.paddingLeft : 4)));
    const rightPadding = Math.max(0, Number(modelData && modelData.rightPadding !== undefined ? modelData.rightPadding : (modelData && modelData.paddingRight !== undefined ? modelData.paddingRight : 4)));
    return { leftPadding, rightPadding };
}

function getContentSpan(itemStyle, vertical, barHeight, verticalBarWidth, marginScale, thickness) {
    if (itemStyle === "pipe") return thickness;
    if (itemStyle === "dot") return Math.min((vertical ? verticalBarWidth : barHeight) * marginScale, 6);
    if (itemStyle === "dash") return 12;
    return 0;
}

// 1. Style parsing
assert.strictEqual(getItemStyle(null), "pipe");
assert.strictEqual(getItemStyle({}), "pipe");
assert.strictEqual(getItemStyle({ style: "PIPE" }), "pipe");
assert.strictEqual(getItemStyle({ style: "line" }), "pipe");
assert.strictEqual(getItemStyle({ style: "Dot" }), "dot");
assert.strictEqual(getItemStyle({ style: "circle" }), "dot");
assert.strictEqual(getItemStyle({ style: "dash" }), "dash");
assert.strictEqual(getItemStyle({ style: "hyphen" }), "dash");
assert.strictEqual(getItemStyle({ style: "empty" }), "empty");
assert.strictEqual(getItemStyle({ style: "space" }), "empty");
assert.strictEqual(getItemStyle({ type: "dot" }), "dot");

// 2. Padding defaults & overrides
assert.deepStrictEqual(getPadding(null), { leftPadding: 4, rightPadding: 4 });
assert.deepStrictEqual(getPadding({}), { leftPadding: 4, rightPadding: 4 });
assert.deepStrictEqual(getPadding({ leftPadding: 10, rightPadding: 20 }), { leftPadding: 10, rightPadding: 20 });
assert.deepStrictEqual(getPadding({ paddingLeft: 8, paddingRight: 12 }), { leftPadding: 8, rightPadding: 12 });
assert.deepStrictEqual(getPadding({ leftPadding: -5, rightPadding: 0 }), { leftPadding: 0, rightPadding: 0 });

// 3. Content span
const barHeight = 40;
const verticalBarWidth = 48;
const marginScale = 0.3;
const thickness = 3;

assert.strictEqual(getContentSpan("pipe", false, barHeight, verticalBarWidth, marginScale, thickness), 3);
assert.strictEqual(getContentSpan("dot", false, barHeight, verticalBarWidth, marginScale, thickness), 6);
assert.strictEqual(getContentSpan("dash", false, barHeight, verticalBarWidth, marginScale, thickness), 12);
assert.strictEqual(getContentSpan("empty", false, barHeight, verticalBarWidth, marginScale, thickness), 0);

console.log("All Spacebar self-checks passed!");
