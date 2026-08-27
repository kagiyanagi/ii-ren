// Minimal iCalendar (RFC 5545) parser for Google Calendar "secret address"
// feeds. Recurrence covers what Google emits for everyday events: FREQ=
// DAILY/WEEKLY/MONTHLY/YEARLY with INTERVAL, COUNT, UNTIL, BYDAY and EXDATE.
// ponytail: TZID times are read as local time and RECURRENCE-ID overrides
// aren't deduped against their original slot; swap in a real ical lib if
// cross-timezone calendars ever matter.

const DAY_MS = 24 * 60 * 60 * 1000;
const BYDAY_INDEX = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };
const MAX_STEPS = 20000; // runaway-recurrence guard (~55 years of daily steps)

function unfoldLines(text) {
    return text.replace(/\r?\n[ \t]/g, "").split(/\r?\n/);
}

function unescapeText(s) {
    return s.replace(/\\n/gi, "\n").replace(/\\([,;\\])/g, "$1");
}

// 20260827 | 20260827T130000 | 20260827T130000Z
function parseIcsDate(v) {
    const y = +v.slice(0, 4), mo = +v.slice(4, 6) - 1, d = +v.slice(6, 8);
    if (v.length === 8) return new Date(y, mo, d);
    const h = +v.slice(9, 11), mi = +v.slice(11, 13), s = +v.slice(13, 15) || 0;
    if (v[v.length - 1] === "Z") return new Date(Date.UTC(y, mo, d, h, mi, s));
    return new Date(y, mo, d, h, mi, s);
}

function startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function dayKey(d) {
    return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
}

function parseVevents(lines) {
    const events = [];
    let cur = null;
    for (const line of lines) {
        if (line === "BEGIN:VEVENT") { cur = {}; continue; }
        if (line === "END:VEVENT") { if (cur) events.push(cur); cur = null; continue; }
        if (!cur) continue;
        const colon = line.indexOf(":");
        if (colon < 0) continue;
        const name = line.slice(0, colon).split(";")[0];
        const value = line.slice(colon + 1);
        if (name === "SUMMARY") cur.summary = unescapeText(value);
        else if (name === "DESCRIPTION") cur.description = unescapeText(value);
        else if (name === "DTSTART") { cur.start = parseIcsDate(value); cur.allDay = value.length === 8; }
        else if (name === "DTEND") cur.end = parseIcsDate(value);
        else if (name === "RRULE") cur.rrule = value;
        else if (name === "EXDATE") {
            cur.exdates = cur.exdates || [];
            for (const part of value.split(","))
                cur.exdates.push(dayKey(parseIcsDate(part)));
        }
    }
    return events;
}

// "n-th <weekday> of the month", n < 0 counts from the end. month may
// overflow past 11; Date normalizes it. Returns null if the month lacks one.
function nthWeekdayOfMonth(year, month, weekday, n, hh, mm) {
    const first = new Date(year, month, 1);
    year = first.getFullYear();
    month = first.getMonth();
    let day;
    if (n > 0) {
        day = 1 + (weekday - first.getDay() + 7) % 7 + (n - 1) * 7;
    } else {
        const last = new Date(year, month + 1, 0);
        day = last.getDate() - (last.getDay() - weekday + 7) % 7 + (n + 1) * 7;
    }
    const d = new Date(year, month, day, hh, mm);
    return d.getMonth() === month ? d : null;
}

// Occurrence start times of one VEVENT, bounded by [winStart, winEnd].
function occurrences(ev, winStart, winEnd) {
    if (!ev.rrule) return [ev.start];
    const rule = {};
    for (const part of ev.rrule.split(";")) {
        const eq = part.indexOf("=");
        if (eq > 0) rule[part.slice(0, eq)] = part.slice(eq + 1);
    }
    const interval = Math.max(1, +(rule.INTERVAL || 1));
    const until = rule.UNTIL ? parseIcsDate(rule.UNTIL) : null;
    let count = rule.COUNT ? +rule.COUNT : Infinity;
    const stop = until && until < winEnd ? until : winEnd;
    const hh = ev.start.getHours(), mm = ev.start.getMinutes();
    const out = [];

    if (rule.FREQ === "DAILY" || rule.FREQ === "WEEKLY") {
        const weekly = rule.FREQ === "WEEKLY";
        const days = weekly
            ? (rule.BYDAY || "").split(",").filter(Boolean).map(t => BYDAY_INDEX[t.slice(-2)])
            : [];
        if (weekly && !days.length) days.push(ev.start.getDay());
        const anchor = startOfDay(ev.start);
        // ponytail: weeks anchored to DTSTART's Monday; WKST is ignored
        const weekAnchor = anchor.getTime() - ((ev.start.getDay() + 6) % 7) * DAY_MS;
        for (let i = 0; i < MAX_STEPS && count > 0; i++) {
            const d = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate() + i, hh, mm);
            if (d > stop) break;
            let hit;
            if (weekly) {
                // Math.round absorbs DST hour drift before the week division
                const weekIdx = Math.floor(Math.round((startOfDay(d) - weekAnchor) / DAY_MS) / 7);
                hit = days.indexOf(d.getDay()) >= 0 && weekIdx % interval === 0;
            } else {
                hit = i % interval === 0;
            }
            if (!hit) continue;
            if (d >= winStart) out.push(d);
            count--;
        }
    } else if (rule.FREQ === "MONTHLY") {
        const byday = /^(-?\d)([A-Z]{2})$/.exec(rule.BYDAY || "");
        for (let k = 0; k < MAX_STEPS && count > 0; k += interval) {
            const y = ev.start.getFullYear(), mo = ev.start.getMonth() + k;
            let d;
            if (byday) {
                d = nthWeekdayOfMonth(y, mo, BYDAY_INDEX[byday[2]], +byday[1], hh, mm);
            } else {
                d = new Date(y, mo, ev.start.getDate(), hh, mm);
                if (d.getDate() !== ev.start.getDate()) d = null; // month lacks a 31st etc.
            }
            if (!d) continue;
            if (d > stop) break;
            if (d >= winStart) out.push(d);
            count--;
        }
    } else if (rule.FREQ === "YEARLY") {
        for (let k = 0; k < MAX_STEPS && count > 0; k += interval) {
            const d = new Date(ev.start.getFullYear() + k, ev.start.getMonth(), ev.start.getDate(), hh, mm);
            if (d > stop) break;
            if (d >= winStart) out.push(d);
            count--;
        }
    } else {
        return [ev.start]; // unknown FREQ: at least show the first instance
    }
    return out;
}

// -> [{title, description, start, end, allDay}], one entry per covered day
// for multi-day all-day events so a fest dots every day it spans.
function parseEvents(text, winStart, winEnd) {
    const out = [];
    for (const ev of parseVevents(unfoldLines(text))) {
        if (!ev.start || !ev.summary) continue;
        const durMs = ev.end && ev.end > ev.start ? ev.end - ev.start : 0;
        const spanDays = ev.allDay ? Math.max(1, Math.round(durMs / DAY_MS)) : 1;
        for (const occ of occurrences(ev, winStart, winEnd)) {
            if (ev.exdates && ev.exdates.indexOf(dayKey(occ)) >= 0) continue;
            for (let i = 0; i < spanDays; i++) {
                const start = ev.allDay
                    ? new Date(occ.getFullYear(), occ.getMonth(), occ.getDate() + i)
                    : occ;
                if (start < winStart || start > winEnd) continue;
                out.push({
                    title: ev.summary,
                    description: ev.description || "",
                    start: start,
                    end: ev.allDay
                        ? new Date(start.getFullYear(), start.getMonth(), start.getDate(), 23, 59)
                        : new Date(start.getTime() + durMs),
                    allDay: !!ev.allDay
                });
            }
        }
    }
    return out;
}

if (typeof module !== "undefined")
    module.exports = { parseEvents: parseEvents, parseIcsDate: parseIcsDate };
