// node services/ics.test.js
// Synthetic Google-style feed: folded+escaped summary, all-day span, weekly
// recurrence with COUNT+EXDATE, monthly nth-weekday, UTC timestamp parse.
const assert = require("assert");
const { parseEvents, parseIcsDate } = require("./ics.js");

const ICS = [
    "BEGIN:VCALENDAR",
    "BEGIN:VEVENT",
    "DTSTART:20260910T090000",
    "DTEND:20260910T093000",
    "SUMMARY:Dentist\\, ma",
    " ybe",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "DTSTART;VALUE=DATE:20260901",
    "DTEND;VALUE=DATE:20260904",
    "SUMMARY:Fest",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "DTSTART:20260907T100000",
    "DTEND:20260907T110000",
    "RRULE:FREQ=WEEKLY;COUNT=4;BYDAY=MO,WE",
    "EXDATE:20260909T100000",
    "SUMMARY:Standup",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "DTSTART:20260908T180000",
    "DTEND:20260908T190000",
    "RRULE:FREQ=MONTHLY;COUNT=2;BYDAY=2TU",
    "SUMMARY:Meetup",
    "END:VEVENT",
    "END:VCALENDAR",
].join("\r\n");

const events = parseEvents(ICS, new Date(2026, 7, 1), new Date(2026, 11, 31));
const days = title => events.filter(e => e.title === title)
    .map(e => `${e.start.getMonth() + 1}/${e.start.getDate()}`).join(" ");

assert.strictEqual(days("Dentist, maybe"), "9/10"); // unfolds + unescapes
assert.strictEqual(days("Fest"), "9/1 9/2 9/3"); // all-day span, DTEND exclusive
assert.strictEqual(days("Standup"), "9/7 9/14 9/16"); // COUNT=4 minus EXDATE 9/9
assert.strictEqual(days("Meetup"), "9/8 10/13"); // 2nd Tuesday of each month
assert.strictEqual(parseIcsDate("20260827T130000Z").getTime(),
    Date.UTC(2026, 7, 27, 13, 0, 0));

console.log("ics.test.js: all assertions passed");
