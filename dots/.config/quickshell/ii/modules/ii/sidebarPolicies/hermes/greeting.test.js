// node modules/ii/sidebarPolicies/hermes/greeting.test.js
const assert = require("assert");
const { title, parts, subtitle, displayName } = require("./greeting.js");

// 2026-10-03 is a Saturday; 2026-10-05 a Monday; 2026-10-02 a Friday.
const at = (day, hour) => new Date(2026, 9, day, hour, 30);

assert.strictEqual(title(at(3, 10), "Ren"), "Happy Saturday, Ren");
assert.strictEqual(title(at(5, 8), "Ren"), "Fresh week, Ren");
assert.strictEqual(title(at(2, 19), "Ren"), "Happy Friday, Ren");
assert.match(title(at(3, 2), "Ren"), /Ren/);

// Every slot of a plain weekday reads cleanly without a name too.
for (let hour = 0; hour < 24; hour++) {
    const t = title(at(7, hour), "");
    assert.ok(!t.includes("{n}") && !/[, ]$/.test(t) && !t.includes(" ?") && !t.includes(",?"), `${hour}: "${t}"`);
}

assert.deepStrictEqual(parts(at(3, 10), "Ren"), { lead: "Happy Saturday,", name: "Ren" });
assert.deepStrictEqual(parts(at(4, 10), "Ren"), { lead: "Slow Sunday,", name: "Ren?" });
assert.deepStrictEqual(parts(at(4, 10), ""), { lead: "Slow Sunday?", name: "" });
assert.ok(subtitle(at(7, 20)).length > 0 && !subtitle(at(7, 20)).includes("\n"));

assert.strictEqual(displayName("ren"), "Ren");
assert.strictEqual(displayName("user"), "");

console.log("ok: the greeting follows the hour and weekday, and splits cleanly around the name, or with none");
