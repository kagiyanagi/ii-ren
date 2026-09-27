// Colour scales for the periodic table, and the trends it can be coloured by.
//
// These hexes are DELIBERATE and are the one place in this surface that does not
// read from Appearance.colors -- the colour here *is* the data, the same
// argument that keeps PrivacyIndicator's privacy-chip colours fixed. A family
// hue that shifts with the wallpaper stops meaning "halogen",
// and a heat map whose ramp is re-themed per wallpaper cannot be read against
// its own legend. Each set is stepped separately for the dark and light surface
// rather than flipped, and every one was produced by search and then validated
// with the data-viz validator rather than picked by eye:
//
//   family, 10 slots, adjacent pairlist  -- CVD dE 11.9 (target >= 8),
//     normal-vision dE 15.2 (floor 15), lightness band and chroma floor pass.
//     The pairlist is adjacent rather than all-pairs because the slots are
//     ordered the way the families are laid out, so "adjacent" is exactly the
//     set of families that touch on screen. Ten hues cannot pass all-pairs --
//     no ten can -- which is why `block` exists below.
//   block, 4 slots, ALL pairs -- CVD dE 8.8, normal-vision dE 21.1, contrast
//     >= 3:1. This is the colour-blind-safe view of the same table, and it is
//     also a mode a chemistry student wants for its own sake.
//   trend, 7 steps, one hue -- monotone in lightness, >= 2:1 against the surface
//     at the dim end so a low value is still a visible tile.
//
// Every tile is directly labelled with its symbol, number and name, and a legend
// is always on screen, so identity never rests on colour alone.

.pragma library

const familyOrder = [
    "alkali metal",
    "alkaline earth metal",
    "transition metal",
    "post-transition metal",
    "metalloid",
    "nonmetal",
    "halogen",
    "noble gas",
    "lanthanide",
    "actinide",
];

const familyDark = [
    "#a2413d", "#cb7a35", "#7f6000", "#67a351", "#007b5c",
    "#00a6b6", "#0f68aa", "#8d82db", "#834994", "#cb6d9c",
];
const familyLight = [
    "#a03f3c", "#e79551", "#7e5f00", "#81be6b", "#007a5b",
    "#00c2d2", "#0b67a9", "#a79df8", "#814893", "#e887b6",
];

const blockOrder = ["s", "p", "d", "f"];
const blockDark = ["#c16400", "#00b16e", "#2c78f3", "#dd4ea9"];
const blockLight = ["#9c4b00", "#00b97c", "#195cc7", "#e263b1"];

const trendDark = ["#28567f", "#326898", "#3c7bb3", "#478ece", "#52a2ea", "#5eb6ff", "#6acbff"];
const trendLight = ["#a5d7ff", "#88c0f6", "#6baae5", "#4e94d5", "#2d7fc4", "#0069b3", "#0054a2"];

// The ways the table can be coloured. `key` is null for the two categorical
// modes; the rest read one number off an element and are drawn on the ramp.
const modes = [
    { id: "family", label: "Family", key: null },
    { id: "block", label: "Block", key: null },
    { id: "radiusEmpirical", label: "Atomic radius", key: "radiusEmpirical", unit: "pm" },
    { id: "electronegativity", label: "Electronegativity", key: "electronegativity", unit: "" },
    { id: "ionisation", label: "Ionisation enthalpy", key: "ionisation1", unit: "kJ/mol" },
    { id: "electronAffinity", label: "Electron gain", key: "electronAffinity", unit: "kJ/mol" },
    { id: "melt", label: "Melting point", key: "melt", unit: "K" },
    { id: "density", label: "Density", key: "density", unit: "" },
];

function modeById(id) {
    for (let i = 0; i < modes.length; i++)
        if (modes[i].id === id)
            return modes[i];
    return modes[0];
}

/** The number a trend mode reads, or null where the element has no value. */
function trendValue(element, mode) {
    if (!mode || !mode.key)
        return null;
    if (mode.key === "ionisation1")
        return (element.ionisation && element.ionisation.length) ? element.ionisation[0] : null;
    const value = element[mode.key];
    return (value === undefined || value === null) ? null : value;
}

function familyColor(family, dark) {
    const index = familyOrder.indexOf(family);
    const palette = dark ? familyDark : familyLight;
    return index < 0 ? palette[palette.length - 1] : palette[index];
}

function blockColor(block, dark) {
    const index = blockOrder.indexOf(block);
    const palette = dark ? blockDark : blockLight;
    return index < 0 ? palette[0] : palette[index];
}

/**
 * Where a value sits on the ramp, 0..6. Density spans five orders of magnitude
 * between hydrogen and osmium, so it is stepped on a log scale -- on a linear
 * one every element but the handful of heavy metals lands on the same step and
 * the map says nothing.
 */
function rampStep(value, min, max, logarithmic) {
    if (value === null || max === min)
        return 0;
    let t;
    if (logarithmic && min > 0) {
        t = (Math.log(value) - Math.log(min)) / (Math.log(max) - Math.log(min));
    } else {
        t = (value - min) / (max - min);
    }
    return Math.max(0, Math.min(6, Math.round(t * 6)));
}

function trendColor(step, dark) {
    const ramp = dark ? trendDark : trendLight;
    return ramp[Math.max(0, Math.min(ramp.length - 1, step))];
}

/** min/max of a trend across every element that has a value for it. */
function trendDomain(elements, mode) {
    let min = null;
    let max = null;
    for (let i = 0; i < elements.length; i++) {
        const value = trendValue(elements[i], mode);
        if (value === null)
            continue;
        if (min === null || value < min)
            min = value;
        if (max === null || value > max)
            max = value;
    }
    return { min: min, max: max };
}
