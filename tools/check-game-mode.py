#!/usr/bin/env python3
"""Game mode gives back the user's own Hyprland settings when it is turned off.

Game mode writes its values (no animations, blur, shadows, gaps or rounding; tearing on)
as overrides in shellOverrides/main.lua. Turning it off used to `hyprset reset` every
one of those keys, which deleted the user's own overrides with them: the owner's
`rounding = 18` line went, and their blur, off in main.lua, came back on from
general.lua. Its on/off was read off
animations:enabled, so turning animations off in Settings showed game mode as on, and a
click assigned `toggled`, breaking that binding for the rest of the session.

Now on/off is its own Persistent state, turning it on saves main.lua's override for each
key (or that there was none), and turning it off puts exactly that back. A key that no
longer holds game mode's value was changed while it was on (Settings, `iiren hyprset`),
and the newer value stays. None of it shows in a still frame, so HyprlandGameMode's own
setActive() and HyprlandSettings' own updateKeys() are lifted out of the QML and run
under node, against the real hyprset.lua writing a main.lua in a throwaway HOME: what is
asserted is the file Hyprland would load.
"""
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
II = REPO / "dots/.config/quickshell/ii"
HYPRSET = REPO / "sdata/cli/lib/hyprset.sh"
OVERRIDES_JS = II / "services/hyprlandOverrides.js"
service = (II / "services/HyprlandGameMode.qml").read_text()
settings = (II / "services/HyprlandSettings.qml").read_text()
persistent = (II / "modules/common/Persistent.qml").read_text()
model = (II / "modules/common/models/quickToggles/GameModeToggle.qml").read_text()
classic = (II / "modules/ii/sidebarDashboard/quickToggles/classicStyle/GameMode.qml").read_text()
waffle = (II / "modules/waffle/actionCenter/toggles/ActionCenterTogglesDelegateChooser.qml").read_text()


def block(src, start):
    """The brace-balanced block opening at the first `{` after `start`, strings skipped."""
    i = src.index("{", start)
    depth, j, quote = 0, i, None
    while j < len(src):
        c = src[j]
        if quote:
            if c == "\\":
                j += 1
            elif c == quote:
                quote = None
        elif c in "'\"`":
            quote = c
        elif c in "{}":
            depth += 1 if c == "{" else -1
            if depth == 0:
                return src[i:j + 1]
        j += 1
    raise AssertionError("unbalanced block")


def function(src, name):
    """A member function, up to the `}` at its own indent (its body may hold a regex)."""
    m = re.search(rf"^( *)function {name}\(.*?^\1\}}$", src, re.S | re.M)
    assert m, f"no function {name}()"
    return m.group(0).strip()


# --- the toggles show the state and only ask for a change -------------------------------
for name, src in (("GameModeToggle.qml", model), ("classicStyle/GameMode.qml", classic)):
    assert "toggled: HyprlandGameMode.active" in src, f"{name}: the toggle must show the persisted state"
    assert "HyprlandGameMode.toggle()" in src, f"{name}: a click must call the service"
    assert not re.search(r"\btoggled\s*=[^=]", src), f"{name}: assigning `toggled` breaks its binding"
    assert "animations:enabled" not in src, f"{name}: game mode is not read off animations:enabled"
    assert "hyprctl" not in src and "HyprlandSettings" not in src, f"{name}: Hyprland is the service's business"
assert "toggleModel: GameModeToggle {}" in waffle, "the Waffle action center must share the one model"

hypr = block(persistent, persistent.index("property JsonObject hyprland:"))
assert "property bool gameMode: false" in hypr, "game mode's on/off must outlive a restart"
assert "property list<var> gameModeSaved: []" in hypr, \
    "the saved overrides must outlive a restart (a list<var>: a nested `var` crashes JsonAdapter)"

set_active = function(service, "setActive")
assert set_active.count("HyprlandSettings.updateKeys(") == 1 and "setKeys" not in set_active \
    and "resetKeys" not in set_active, "one hyprset chain per change: two at once race on main.lua"
assert re.search(r"interval: \d+\s*\n\s*onTriggered: root\.pending = null", service), \
    "a write that never lands must not lock the toggle"
assert "`${FileUtils.trimFileProtocol(Directories.home)}/.config/hypr/hyprland/shellOverrides/main.lua`" in settings \
    and 'HOME .. "/.config/hypr/hyprland/shellOverrides"' in (REPO / "sdata/cli/lib/hyprset.lua").read_text(), \
    "the shell must read the main.lua hyprset.lua writes"

# --- the real thing, under node against the real hyprset.lua ---------------------------
values = block(service, service.index("readonly property var values:"))
on_overrides = block(service, service.index("onOverridesChanged:"))
ORIGINAL = """-- MANAGED BY HYPRSET.LUA — DO NOT EDIT
hl.config({decoration={rounding=18}})
hl.config({general={layout="dwindle"}})
hl.animation({leaf="workspaces", enabled=true, speed=7, spring="m3DefaultSpatial", style="slide"})
hl.layer_rule({match={namespace="quickshell:dock"}, animation="slide bottom"})
hl.config({decoration={blur={enabled=false}}})
hl.config({general={gaps_out="5 10 5 10"}})
"""

js = """
const assert = require("assert");
const cp = require("child_process");
const fs = require("fs");
const O = require(%(overrides_js)s);
const HOME = %(home)s, CLI = %(cli)s;
const MAIN = HOME + "/.config/hypr/hyprland/shellOverrides/main.lua";
const env = Object.assign({}, process.env, { HOME, HYPRSET: %(hyprset)s });
const Directories = { cliPath: CLI };
// Synchronous, so the file is whole by the time anything reads it.
const Quickshell = { execDetached: argv => cp.execFileSync(argv[0], argv.slice(1), { env, stdio: "pipe" }) };
const hyprset = (...args) => Quickshell.execDetached([CLI, "hyprset", ...args]);
const read = () => fs.readFileSync(MAIN, "utf8");

// HyprlandSettings with its own updateKeys(); `overrides` is the FileView's parse, re-read
// on demand to stand for the watcher.
function makeSettings() {
    const root = { overridesLoaded: true, overrides: {}, _queueReload() {} };
    %(unsafe)s
    %(update_keys)s
    root._hasUnsafeChars = _hasUnsafeChars;
    root.updateKeys = updateKeys;
    root.reload = () => { root.overrides = O.parse(read()); };
    root.reload();
    return root;
}

// HyprlandGameMode with its own setActive(); a new one per shell start.
function makeGameMode(Persistent, HyprlandSettings) {
    const Overrides = O;
    const pendingTimeout = { restart() {} };
    const root = { pending: null, values: %(values)s };
    Object.defineProperty(root, "active", { get: () => Persistent.ready && Persistent.states.hyprland.gameMode });
    %(toggle)s
    %(set_active)s
    root.toggle = toggle;
    root.setActive = setActive;
    // onOverridesChanged, as the FileView's next read sets HyprlandSettings.overrides.
    root.see = overrides => {
        root.overrides = overrides;
        (function () %(on_overrides)s)();
    };
    root.sync = () => {
        HyprlandSettings.reload();
        root.see(HyprlandSettings.overrides);
    };
    return root;
}

function boot(states) {
    const Persistent = { ready: true, states: JSON.parse(JSON.stringify(states)) };
    const HyprlandSettings = makeSettings();
    return { Persistent, HyprlandSettings, gm: makeGameMode(Persistent, HyprlandSettings) };
}
const fresh = { hyprland: { gameMode: false, gameModeSaved: [] } };

// main.lua as hyprset writes it reads back as the values hyprset takes.
assert.deepStrictEqual(O.parse(%(original)s), {
    "decoration:rounding": "18", "general:layout": "dwindle",
    "decoration:blur:enabled": "false", "general:gaps_out": "5 10 5 10" });
assert.deepStrictEqual(O.parse("hl.config({a={b=1}})\\nhl.config({a={b=2}})"), { "a:b": "2" }, "Hyprland runs the last one");
assert(O.same("1", "1.0") && !O.same("0", "false") && !O.same(undefined, "0"));

// 1. The owner's case: rounding 18 is theirs, and comes back.
let s = boot(fresh);
s.gm.toggle();
s.gm.sync();
assert.strictEqual(s.gm.pending, null, "the file reached game mode");
assert(s.gm.active);
for (const [k, v] of Object.entries(s.gm.values))
    assert(O.same(s.HyprlandSettings.overrides[k], v), k + " is game mode's while it is on");
const saved = s.Persistent.states.hyprland.gameModeSaved;
assert.deepStrictEqual(saved.find(e => e.key === "decoration:rounding"), { key: "decoration:rounding", had: true, value: "18" });
assert.deepStrictEqual(saved.find(e => e.key === "animations:enabled"), { key: "animations:enabled", had: false, value: "" });

// 2. It survives a restart: the state and the saved overrides are read back from disk.
s = boot(s.Persistent.states);
assert(s.gm.active, "game mode must still read as on after a restart");
s.gm.toggle();
s.gm.sync();
assert.strictEqual(s.gm.pending, null);
assert(!s.gm.active);
assert.strictEqual(s.HyprlandSettings.overrides["decoration:rounding"], "18", "the user's rounding 18 must come back");
assert.strictEqual(s.HyprlandSettings.overrides["general:gaps_out"], "5 10 5 10", "a value with spaces comes back whole");
assert.strictEqual(s.HyprlandSettings.overrides["decoration:blur:enabled"], "false");
for (const k of ["animations:enabled", "decoration:shadow:enabled", "general:gaps_in", "general:border_size", "general:allow_tearing"])
    assert(!(k in s.HyprlandSettings.overrides), k + " had no override before, and must have none after");
assert.strictEqual(read(), %(original)s, "off must leave main.lua exactly as it was");
assert.deepStrictEqual(s.Persistent.states.hyprland.gameModeSaved, []);

// 3. Animations turned off by the user is not game mode, and stays theirs.
hyprset("key", "animations:enabled", "false");
s = boot(s.Persistent.states);
assert(!s.gm.active, "animations off must not read as game mode on");
s.gm.toggle(); s.gm.sync();
s.gm.toggle(); s.gm.sync();
assert.strictEqual(s.HyprlandSettings.overrides["animations:enabled"], "false", "the user's own animations off comes back");
hyprset("reset", "animations:enabled");
s.gm.sync();

// 4. A change made while game mode is on is the newer choice, and is kept.
s.gm.toggle(); s.gm.sync();
hyprset("key", "decoration:rounding", "10");
hyprset("key", "general:border_size", "3");
s = boot(s.Persistent.states);
s.gm.toggle(); s.gm.sync();
assert.strictEqual(s.HyprlandSettings.overrides["decoration:rounding"], "10", "rounding set during game mode must not be clobbered");
assert.strictEqual(s.HyprlandSettings.overrides["general:border_size"], "3");
assert.strictEqual(s.HyprlandSettings.overrides["general:gaps_out"], "5 10 5 10", "the rest still comes back");
assert(!("general:gaps_in" in s.HyprlandSettings.overrides));
hyprset("key", "decoration:rounding", "18");
hyprset("reset", "general:border_size");
assert.strictEqual(read(), %(original)s, "nothing else was left behind");

// 5. A click while main.lua is half written waits: it would save game mode's own
//    values as the user's.
s = boot(s.Persistent.states);
s.gm.toggle();
s.HyprlandSettings.overrides = Object.assign({}, s.HyprlandSettings.overrides, { "animations:enabled": "0" });
s.gm.see(s.HyprlandSettings.overrides);
assert.notStrictEqual(s.gm.pending, null, "one key in is not the change done");
s.gm.toggle();
assert(s.gm.active, "a click before the file shows the last change must not act on it");
s.gm.sync();
s.gm.toggle(); s.gm.sync();
assert.strictEqual(read(), %(original)s, "and on, off still leaves main.lua as it was");
console.log("ok");
"""

with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp) / "home"
    main = home / ".config/hypr/hyprland/shellOverrides/main.lua"
    main.parent.mkdir(parents=True)
    main.write_text(ORIGINAL)
    cli = Path(tmp) / "iiren"
    cli.write_text('#!/usr/bin/env bash\n[ "$1" = hyprset ] || exit 64\nshift\nexec bash "$HYPRSET" "$@"\n')
    cli.chmod(0o755)
    script = js % {
        "overrides_js": json.dumps(str(OVERRIDES_JS)),
        "home": json.dumps(str(home)),
        "cli": json.dumps(str(cli)),
        "hyprset": json.dumps(str(HYPRSET)),
        "unsafe": function(settings, "_hasUnsafeChars"),
        "update_keys": function(settings, "updateKeys"),
        "values": values,
        "toggle": function(service, "toggle"),
        "set_active": set_active,
        "on_overrides": on_overrides,
        "original": json.dumps(ORIGINAL),
    }
    run = subprocess.run(["node", "-"], input=script, capture_output=True, text=True, env={**os.environ, "HOME": str(home)})
    assert run.returncode == 0 and run.stdout.strip() == "ok", run.stdout + run.stderr

print("ok: game mode keeps its own state, gives back the user's overrides (rounding 18 stays 18), "
      "removes only the ones it added, keeps changes made while it was on, survives a restart")
