// Self-check: qmljs/node modules/ii/bar/test_duration.js
const src = require("fs").readFileSync(__dirname + "/duration.js", "utf8").replace(".pragma library", "");
eval(src);

const cases = [["25", 1500], ["25:00", 1500], ["1:02:03", 3723], ["0:30", 30], ["", 0], ["abc", 0], ["-5", 0], ["1:2:3:4", 0]];
for (const [input, want] of cases) {
    const got = parse(input);
    console.assert(got === want, `parse(${JSON.stringify(input)}) = ${got}, want ${want}`);
    if (got !== want) process.exit(1);
}
console.assert(format(parse("25")) === "25:00");
console.log("ok");
