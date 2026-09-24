// Self-check: node modules/ii/sidebarPolicies/translator/test_refine.js
// Pulls the refine helpers straight out of Translator.qml so the two can't drift.
const assert = require("assert");
const qml = require("fs").readFileSync(__dirname + "/../Translator.qml", "utf8");
const lift = name => qml.match(new RegExp(`function ${name}\\(([^)]*)\\)[^{]*\\{([\\s\\S]*?)\\n    \\}`))
    .slice(1).map((s, i) => i ? s : s.split(",").map(a => a.split(":")[0].trim()));
const root = {};
for (const name of ["ltCode", "fixKind", "applyFixes"]) {
    const [args, body] = lift(name);
    root[name] = new Function("root", ...args, body).bind(null, root);
}

// Real /v2/languages codes, trimmed.
root.ltLanguages = ["ar", "de", "de-DE", "de-AT", "en", "en-US", "en-GB", "fr", "pt", "pt-PT", "pt-BR", "zh-CN", "sv", "sv-SE", "uk-UA"];
assert.strictEqual(root.ltCode("en"), "en-US"); // bare "en" has no spell checker
assert.strictEqual(root.ltCode("de"), "de-DE");
assert.strictEqual(root.ltCode("pt"), "pt-PT");
assert.strictEqual(root.ltCode("uk"), "uk-UA");
assert.strictEqual(root.ltCode("ar"), "ar");
assert.strictEqual(root.ltCode("zh-CN"), "zh-CN");
assert.strictEqual(root.ltCode("zh-TW"), "");
assert.strictEqual(root.ltCode("hi"), "");

// The en-US answer for "i has a eror , in this sentance".
const text = "i has a eror , in this sentance";
const m = (offset, length, cat, value) => ({ offset, length, rule: { category: { id: cat } }, replacements: value === null ? [] : [{ value }] });
const matches = [m(0, 1, "TYPOS", "I"), m(2, 3, "GRAMMAR", "have"), m(6, 1, "MISC", "an"),
    m(8, 4, "TYPOS", "error"), m(12, 2, "TYPOGRAPHY", ","), m(23, 8, "TYPOS", "sentence"), m(17, 4, "STYLE", null)];
const all = ["grammar", "spelling", "punctuation", "style"];
assert.strictEqual(root.applyFixes(text, matches, all), "I have an error, in this sentence");
assert.strictEqual(root.applyFixes(text, matches, ["spelling"]), "I has a error , in this sentence");
assert.strictEqual(root.applyFixes(text, matches, ["grammar"]), "i have an eror , in this sentance");
assert.strictEqual(root.applyFixes(text, matches, ["punctuation"]), "i has a eror, in this sentance");
assert.strictEqual(root.applyFixes(text, matches, []), text);
// Overlapping matches: the later one wins, the earlier is dropped rather than splicing garbage.
assert.strictEqual(root.applyFixes("abcdef", [m(0, 4, "TYPOS", "X"), m(2, 4, "TYPOS", "Y")], all), "abY");
// Input order does not matter, and the caller's array is not reordered.
const rev = [...matches].reverse();
assert.strictEqual(root.applyFixes(text, rev, all), "I have an error, in this sentence");
assert.strictEqual(rev[0].rule.category.id, "STYLE");
console.log("ok");
