// The Hermes tab's empty-state greeting: by the hour, the weekday and the
// user's name. Variants rotate by the day of the year, so the line
// is steady while the tab is open and different tomorrow.
//
// The prompts stay casual on purpose: the user's Hermes profile asks it not to
// keep steering every chat toward work.

const TITLES = {
    night: ["Still up, {n}?", "Night owl mode, {n}", "Late one, {n}?"],
    morning: ["Good morning, {n}", "Morning, {n}", "Rise and shine, {n}"],
    afternoon: ["Good afternoon, {n}", "Afternoon, {n}", "Hey {n}"],
    evening: ["Good evening, {n}", "Evening, {n}", "Hey there, {n}"],
    late: ["Winding down, {n}?", "Evening, {n}", "Nearly bedtime, {n}"]
};

const PROMPTS = {
    night: ["Can't sleep, or just in the zone?", "The quiet hours are the best ones.", "What's keeping you up?"],
    morning: ["What's on your mind today?", "Coffee first, then whatever you like.", "Where do you want to start?"],
    afternoon: ["Need a hand, or just here to chat?", "How's the day going so far?", "What are you curious about?"],
    evening: ["How was your day?", "Anything fun on tonight?", "Want to talk something through?"],
    late: ["Anything before you call it a night?", "One last thing on your mind?", "Tell me how today went."]
};

function partOfDay(hour) {
    if (hour < 5) return "night";
    if (hour < 12) return "morning";
    if (hour < 17) return "afternoon";
    if (hour < 22) return "evening";
    return "late";
}

function dayOfYear(date) {
    return Math.floor((date - new Date(date.getFullYear(), 0, 0)) / 86400000);
}

function withName(template, name) {
    return name ? template.replace("{n}", name) : template.replace(/,? ?\{n\}/, "");
}

function template(date) {
    const part = partOfDay(date.getHours());
    const day = date.getDay();
    // The weekday wins over the rotation where it says more than the hour does.
    if (part === "morning" && day === 1) return "Fresh week, {n}";
    if (part === "evening" && day === 5) return "Happy Friday, {n}";
    if ((part === "morning" || part === "afternoon") && day === 6) return "Happy Saturday, {n}";
    if ((part === "morning" || part === "afternoon") && day === 0) return "Slow Sunday, {n}?";
    const pool = TITLES[part];
    return pool[dayOfYear(date) % pool.length];
}

function title(date, name) {
    return withName(template(date), name);
}

// The greeting split where the name goes, so the name can be set on its own
// line: "Still up," then "Ren?". With no name it is all lead.
function parts(date, name) {
    const t = template(date);
    if (!name)
        return { lead: withName(t, ""), name: "" };
    const at = t.indexOf("{n}");
    return { lead: t.slice(0, at).trim(), name: name + t.slice(at + 3) };
}

function subtitle(date) {
    const pool = PROMPTS[partOfDay(date.getHours())];
    return pool[dayOfYear(date) % pool.length];
}

function displayName(username) {
    // "user" is SystemInfo's placeholder until whoami answers.
    if (!username || username === "user") return "";
    return username.charAt(0).toUpperCase() + username.slice(1);
}

if (typeof module !== "undefined")
    module.exports = {
        title: title,
        parts: parts,
        subtitle: subtitle,
        displayName: displayName
    };
