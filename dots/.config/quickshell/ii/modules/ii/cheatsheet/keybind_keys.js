// Turning a real key press into the name Hyprland uses for it.
//
// The numbers are `Qt.Key_*` values, which are part of Qt's ABI and do not move.
// The names are not guessed: they are the ones this machine's own bind list
// already reports, read off `hyprctl binds -j` rather than transcribed from the
// xkb tables, so a captured combo is written in the same vocabulary the rest of
// the config is written in.
//
// Anything not in this map falls back to the character the key produced, which
// is what covers A-Z, 0-9 and whatever else the user's layout emits.

.pragma library

const modifierKeys = [
    0x01000020, // Qt.Key_Shift
    0x01000021, // Qt.Key_Control
    0x01000022, // Qt.Key_Meta
    0x01000023, // Qt.Key_Alt
    0x01000024, // Qt.Key_CapsLock
    0x01000025, // Qt.Key_NumLock
    0x01000026, // Qt.Key_ScrollLock
    0x01001103, // Qt.Key_AltGr
];

const keyNames = {
    0x01000000: "Escape",
    0x01000001: "Tab",
    0x01000002: "Backtab",
    0x01000003: "BackSpace",
    0x01000004: "Return",
    0x01000005: "KP_Enter",
    0x01000006: "Insert",
    0x01000007: "Delete",
    0x01000009: "Print",
    0x01000010: "Home",
    0x01000011: "End",
    0x01000012: "Left",
    0x01000013: "Up",
    0x01000014: "Right",
    0x01000015: "Down",
    0x01000016: "Page_Up",
    0x01000017: "Page_Down",
    0x01000030: "F1",
    0x01000031: "F2",
    0x01000032: "F3",
    0x01000033: "F4",
    0x01000034: "F5",
    0x01000035: "F6",
    0x01000036: "F7",
    0x01000037: "F8",
    0x01000038: "F9",
    0x01000039: "F10",
    0x0100003a: "F11",
    0x0100003b: "F12",
    0x20: "Space",
    0x27: "Apostrophe",
    0x2c: "Comma",
    0x2d: "Minus",
    0x2e: "Period",
    0x2f: "Slash",
    0x3b: "Semicolon",
    0x3d: "Equal",
    0x5b: "BracketLeft",
    0x5c: "Backslash",
    0x5d: "BracketRight",
    0x60: "Grave",
};

// Qt.KeyboardModifier bits, paired with Hyprland's names for them. The order is
// the one `CheatsheetKeybindsCategory.modMaskToStringList` prints, so a combo
// reads the same in the editor as it does in the list behind it.
const modifiers = [
    [0x04000000, "CTRL"],   // Qt.ControlModifier
    [0x10000000, "SUPER"],  // Qt.MetaModifier
    [0x02000000, "SHIFT"],  // Qt.ShiftModifier
    [0x08000000, "ALT"],    // Qt.AltModifier
];

function isModifier(qtKey) {
    return modifierKeys.indexOf(qtKey) !== -1;
}

/** The Hyprland name for a pressed key, or null if it cannot be bound alone. */
function keyName(qtKey, text) {
    if (isModifier(qtKey))
        return null;
    const known = keyNames[qtKey];
    if (known !== undefined)
        return known;
    // A printable character the layout produced. Uppercased because that is how
    // Hyprland reports letters, and rejected if it is a control character.
    if (typeof text === "string" && text.length === 1 && text.charCodeAt(0) >= 0x20)
        return text.toUpperCase();
    return null;
}

/** "SUPER + SHIFT + K" for a key press, or null if only modifiers are held. */
function combo(qtKey, text, modifierFlags) {
    const key = keyName(qtKey, text);
    if (key === null)
        return null;
    const parts = [];
    for (let i = 0; i < modifiers.length; i++) {
        if (modifierFlags & modifiers[i][0])
            parts.push(modifiers[i][1]);
    }
    parts.push(key);
    return parts.join(" + ");
}
