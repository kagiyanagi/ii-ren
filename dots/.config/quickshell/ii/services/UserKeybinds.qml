pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The user's own Hyprland keybinds -- `~/.config/hypr/custom/keybinds.lua`, which
 * is the file `hyprland.lua` sources last and the one `iiren save` pulls back
 * into the repo.
 *
 * This service only ever **appends** a line or **removes a line it parsed
 * itself**. The file is hand-edited as well, and a rewrite that reformats it
 * would be a silent edit of someone's config; a line this parser does not
 * recognise is left exactly as it is and is simply not offered for deletion.
 *
 * Applying a change is `hyprctl reload`, not `hyprctl keyword bind`: the lua
 * file stays the single source of truth, there is one code path instead of two,
 * and Hyprland emits `configreloaded`, which is already what makes
 * `HyprlandKeybinds` re-read the live list.
 */
Singleton {
    id: root

    readonly property string filePath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)

    // One entry per `hl.bind(...)` line this parser understood.
    property var binds: []
    // `name -> description` for every global the shell has registered, straight
    // from Hyprland, so the editor offers the real list rather than a copy that
    // drifts.
    property var globalShortcuts: []
    property bool ready: false

    // Hyprland's modifier bits, the same ones `hyprctl binds -j` reports in
    // `modmask` and the cheatsheet decodes for display.
    readonly property var modBits: ({
        "SHIFT": 1,
        "CAPS": 2, "CAPSLOCK": 2,
        "CTRL": 4, "CONTROL": 4,
        "ALT": 8, "MOD1": 8,
        "MOD2": 16,
        "MOD3": 32,
        "SUPER": 64, "WIN": 64, "LOGO": 64, "MOD4": 64,
        "MOD5": 128
    })

    /** "SUPER + SHIFT + K" -> { modmask: 65, key: "K" }, or null if it is empty. */
    function parseCombo(combo) {
        const parts = String(combo).split("+").map(p => p.trim()).filter(p => p.length > 0);
        if (parts.length === 0)
            return null;
        let modmask = 0;
        let key = "";
        for (const part of parts) {
            const bit = root.modBits[part.toUpperCase()];
            if (bit !== undefined)
                modmask |= bit;
            else
                key = part;
        }
        if (key.length === 0)
            return null;
        return { modmask: modmask, key: key };
    }

    /**
     * A modmask back into modifier names, in the order this shell prints them.
     * Lives here rather than in the cheatsheet because the editor, the search
     * and the list all need it and the bit table is already here.
     */
    function modNames(modmask) {
        const order = [
            [4, "Ctrl"], [64, "Super"], [1, "Shift"], [8, "Alt"],
            [2, "Caps"], [16, "Mod2"], [32, "Mod3"], [128, "Mod5"]
        ];
        const out = [];
        for (const pair of order) {
            if (modmask & pair[0])
                out.push(pair[1]);
        }
        return out;
    }

    function indexOfBind(modmask, key) {
        const wanted = String(key).toLowerCase();
        for (let i = 0; i < root.binds.length; i++) {
            const bind = root.binds[i];
            if (bind.modmask === modmask && bind.key.toLowerCase() === wanted)
                return i;
        }
        return -1;
    }

    /**
     * A lua double-quoted string. Anything with a newline or a control character
     * in it is refused rather than escaped -- a bind argument never legitimately
     * contains one, and writing it would split the line and corrupt the file.
     */
    function luaString(value) {
        const text = String(value);
        if (/[\x00-\x1f]/.test(text))
            return null;
        return '"' + text.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }

    function bindLine(combo, dispatcher, argument, description) {
        const comboLiteral = root.luaString(combo);
        const argLiteral = root.luaString(argument);
        const descLiteral = root.luaString(description);
        if (comboLiteral === null || argLiteral === null || descLiteral === null)
            return null;
        if (!/^[a-z_]+$/.test(dispatcher))
            return null;
        const tail = description.length > 0 ? `, {description = ${descLiteral}}` : "";
        return `hl.bind(${comboLiteral}, hl.dsp.${dispatcher}(${argLiteral})${tail})`;
    }

    /**
     * Appends a bind and reloads Hyprland. Returns false if it was not written.
     *
     * This **appends**; it does not rewrite. An earlier version read the file
     * into a string, concatenated the new line and wrote the whole thing back,
     * and that lost three of the user's binds during testing. Whatever the exact
     * race was -- a stale cached read, a reload landing mid-write -- the shape
     * was the bug: a whole-file rewrite can only ever be as correct as the copy
     * it started from, and this file is hand-edited underneath us. `>>` cannot
     * delete a line that is already there, so the failure mode does not exist.
     * The line is passed as an argv element, never interpolated into the shell.
     */
    function add(combo, dispatcher, argument, description) {
        const line = root.bindLine(combo, dispatcher, argument, description);
        if (line === null || root.parseCombo(combo) === null)
            return false;
        appendProcess.command = ["sh", "-c",
            // Start on a fresh line if the file does not end on one, so the new
            // bind is never glued onto a hand-written last line.
            'f=$2; [ -s "$f" ] && [ "$(tail -c1 "$f" | wc -l)" -eq 0 ] && printf "\\n" >> "$f"; printf "%s\\n" "$1" >> "$f"',
            "sh", line, root.filePath];
        appendProcess.running = true;
        return true;
    }

    /**
     * Removes one bind this service parsed. A removal has to rewrite, so it is
     * done in one pass over the file on disk rather than over a cached copy, it
     * takes only the **first** exact match, and it writes through a temporary
     * file so a failure leaves the original untouched.
     */
    function remove(index) {
        if (index < 0 || index >= root.binds.length)
            return false;
        removeProcess.command = ["python3", "-c", root.removeScript, root.filePath, root.binds[index].line];
        removeProcess.running = true;
        return true;
    }

    readonly property string removeScript: `
import os, sys
path, target = sys.argv[1], sys.argv[2]
with open(path) as handle:
    lines = handle.read().split("\n")
if target not in lines:
    sys.exit(1)
lines.remove(target)
tmp = path + ".ii-tmp"
with open(tmp, "w") as handle:
    handle.write("\n".join(lines))
os.replace(tmp, path)
`

    function parse(text) {
        // hl.bind("<combo>", hl.dsp.<dispatcher>(<arg>) [, { ... }])
        const pattern = /^\s*hl\.bind\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*hl\.dsp\.([a-z_]+)\(\s*"((?:[^"\\]|\\.)*)"\s*\)\s*(?:,\s*\{([^}]*)\})?\s*\)\s*$/;
        const unescape = value => value.replace(/\\"/g, '"').replace(/\\\\/g, "\\");
        const out = [];
        for (const line of String(text).split("\n")) {
            const match = pattern.exec(line);
            if (!match)
                continue;
            const combo = unescape(match[1]);
            const parsed = root.parseCombo(combo);
            if (parsed === null)
                continue;
            const options = match[4] ?? "";
            const described = /description\s*=\s*"((?:[^"\\]|\\.)*)"/.exec(options);
            out.push({
                line: line,
                combo: combo,
                modmask: parsed.modmask,
                key: parsed.key,
                dispatcher: match[2],
                argument: unescape(match[3]),
                description: described ? unescape(described[1]) : ""
            });
        }
        return out;
    }

    FileView {
        id: fileView
        path: root.filePath
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onLoaded: {
            root.binds = root.parse(fileView.text());
            root.ready = true;
        }
        onLoadFailed: error => {
            // No custom binds yet is the normal state on a fresh machine, not an
            // error -- the first add creates the file.
            root.binds = [];
            root.ready = true;
        }
    }

    Timer {
        id: reloadTimer
        interval: 100
        onTriggered: fileView.reload()
    }

    Process {
        id: reload
        command: ["hyprctl", "reload"]
    }

    Process {
        id: appendProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.error("[UserKeybinds] could not append to", root.filePath, "- exit", exitCode);
            reload.running = true;
        }
    }

    Process {
        id: removeProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.error("[UserKeybinds] could not remove a bind from", root.filePath, "- exit", exitCode);
            reload.running = true;
        }
    }

    /**
     * Read the shell's registered globals. Deferred rather than run when the
     * singleton is created: this service wakes up the moment the cheatsheet
     * opens, and spawning hyprctl there put a subprocess in the open path for a
     * list only the editor dialog ever shows.
     */
    function loadGlobals() {
        if (root.globalShortcuts.length === 0)
            readGlobals.running = true;
    }

    Process {
        id: readGlobals
        command: ["hyprctl", "globalshortcuts"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    // "quickshell:barToggle -> Toggles bar on press"
                    const match = /^\s*([^\s]+)\s*->\s*(.*)$/.exec(line);
                    if (match)
                        out.push({ name: match[1], description: match[2].trim() });
                }
                out.sort((a, b) => a.name.localeCompare(b.name));
                root.globalShortcuts = out;
            }
        }
    }
}
