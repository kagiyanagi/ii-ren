#!/usr/bin/env python3
"""Floating mode manages windows the way KWin and Mutter do, and its rails land where the windows are.

Nothing about this shows in a still frame of the shell, because all of it is relative to
windows the shell does not draw:

- floatingMode.lua, the half inside Hyprland, runs here under plain Lua against a mock
  `hl` that records dispatches and applies them to plain window tables. It is asserted
  against the sources' own numbers, because each is a complaint the owner made:
  - A new window is centred below its bar and cascaded by a 48th of the area off one it
    would cover completely (KWin cascadeIfCovering). One over 80% of the area opens
    maximized (Mutter auto-maximize); an Electron app remembering its tile size used to
    open looking maximized without being so.
  - Maximize fills the work area edge to edge, and any number of windows can be
    maximized at once. Every path into Hyprland's own maximize (Super+D, the bar, an
    app's button) is turned into it; Hyprland's allows one window per workspace and
    hides the rest.
  - Restore goes back to the size the window had, centred where it was, capped at 80% of
    the area (Mutter): restoring to the tile's size looked like nothing happened.
  - An app restoring itself, fullscreen from maximized and back, and a work area that
    grows are each followed. A drag brings a maximized window out with the grab point at
    the same fraction of it (KWin), and a window moved by anything else leaves maximize.

- The rail is a layer surface above every window, so a rail drawn for a window that
  another window covers would sit on top of the window really in front. `rails()`
  marks those `covered`, by stacking order: the order Hyprland lists windows in.
  Not focus history -- focus follows the mouse without raising anything, and a rail
  keyed on focus faded out under the pointer mid-drag while its window stayed in
  front. A window that draws its own controls gets no rail but still covers; a tiled
  window neither gets one nor covers anything.
- The controls sit on the window's content edge, over its border: started at the
  border's outer edge, the border line and its rounded corner showed as a gap.
- The outline has to fill exactly the notch the content's rounded corner leaves:
  a circle on a rounding_power 2.5 window paints over the app, or leaves a sliver.
  Checked for the top bar (the default) and the side rail.
- A new window as wide as the screen would put its rail off it, so `fit()` slides it
  left or narrows it, once.
- The top bar is hyprbars, drawn inside Hyprland in the same frame as its window: the
  config it gets, its buttons, the rules that start every window bar-less, the build
  keyed on the running Hyprland. The layer above stays for the side rail and fallback.
- Every Lua chunk parses (`luac -p`), and an address that is not hex never reaches one.
- KWin's focus and stacking while the mode is on: click to focus, the active window on
  top whatever activated it (Hyprland's focus raises nothing), pinned windows kept above,
  focus to the next in stacking order on close, 10px snap zones -- and the user's own
  focus settings back when it goes.
- Alt+Tab hands a maximize over only to a tiled window: a floating one is raised over
  it, and handing it the state filled the screen with it.
- hyprbars is built with its patch, installed by rename (the compositor has the old one
  mapped), and the title drag and the Super+drag bind both call before_drag.
- The wiring that makes a toggle work: catalog, chooser, loader, the HyprlandData
  event filter (the watcher sends up to 60 events a second; each used to cost four
  hyprctl processes), the keybind and the layer rule.

    python3 tools/check-floating-mode.py
"""
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"
HYPR = ROOT / "dots/.config/hypr/hyprland"
LIB = (SHELL / "services/floatingMode.js").read_text().replace(".pragma library", "")


def js(expr):
    """Evaluate `expr` against floatingMode.js under node and return it as JSON."""
    out = subprocess.run(["node", "-e", LIB + "\nprocess.stdout.write(JSON.stringify(" + expr + "));"],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


RAIL = 40
# One 1920x1080 monitor whose work area stops 6px short of each edge, border 1: a tiled
# window sits at 7,7 1906x1066.
EVENT = ";".join([
    "B 1 18 2.5",
    "M eDP-1 6 6 1914 1074",
    "W 0xaa 100 100 600 400 1 0 1 0 eDP-1 11 kitty",      # A: behind B
    "W 0xbb 650 150 500 300 0 0 1 0 eDP-1 22 zen",        # B: focused, draws its own controls
    "W 0xcc 1200 600 300 200 2 0 1 0 eDP-1 33 kitty",     # C: clear of everything
    "W 0xdd 7 7 1906 1066 3 0 0 0 eDP-1 44 kitty",        # D: tiled, behind all of them
    "W bad 0 0 10 10 4 0 1 0 eDP-1 55 kitty",             # not an address: dropped
])

state = js(f"parse({json.dumps(EVENT)})")
assert state["border"] == 1 and state["rounding"] == 18 and state["power"] == 2.5, state
assert state["areas"]["eDP-1"] == {"x0": 6, "y0": 6, "x1": 1914, "y1": 1074}, state["areas"]
assert [w["address"] for w in state["windows"]] == ["0xaa", "0xbb", "0xcc", "0xdd"], "a non-hex address got through parse()"
assert state["windows"][0]["cls"] == "kitty" and state["windows"][3]["floating"] is False
assert state["windows"][0]["maximized"] is False and state["windows"][0]["monitor"] == "eDP-1"
print("ok  parse: the watcher's report, and nothing that is not an address")

OWN = "function (w) { return w.cls !== 'zen'; }"
ALL = "function () { return true; }"


def rails_for(event, has, side):
    return {r["address"]: r for r in js(f"rails(parse({json.dumps(event)}), {has}, {RAIL}, '{side}')")}


# The controls start at the content edge and cover the border on that side: a strip
# that starts at the border's outer edge leaves the border line and its rounded
# corner showing between window and controls, which is the gap the owner saw.
side = rails_for(EVENT, OWN, "right")
assert set(side) == {"0xaa", "0xcc"}, f"only floating windows without their own controls get one: {sorted(side)}"
assert (side["0xaa"]["x"], side["0xaa"]["y"], side["0xaa"]["w"], side["0xaa"]["h"]) == (700, 99, 1 + RAIL, 402), side["0xaa"]
bar = rails_for(EVENT, OWN, "top")
assert (bar["0xaa"]["x"], bar["0xaa"]["y"], bar["0xaa"]["w"], bar["0xaa"]["h"]) == (99, 100 - 1 - RAIL, 602, 1 + RAIL), bar["0xaa"]
# B (in front) crosses A's rail from y 149 to 451: the rail is cut back to the longest
# stretch in the open, not hidden whole -- hiding it whole made every floating
# overlap take a window's controls away.
assert not side["0xaa"]["covered"] and side["0xaa"]["clipped"], side["0xaa"]
assert side["0xaa"]["span"] == {"s0": 0, "s1": 50}, f"the rail keeps y 99..149, above B: {side['0xaa']['span']}"
assert not side["0xcc"]["clipped"] and side["0xcc"]["span"] == {"s0": 0, "s1": 202}
buried = EVENT.replace("W 0xbb 650 150 500 300", "W 0xbb 650 90 500 500")
assert rails_for(buried, OWN, "right")["0xaa"]["covered"], "a rail with no stretch as long as it is thick left in the open hides"
assert not bar["0xaa"]["covered"], "A's bar (y 59..100) clears B, whose top border is at 149"
assert not side["0xcc"]["covered"], "the tiled window D is behind every floating one and covers nothing"
assert not side["0xaa"]["focused"] and not side["0xcc"]["focused"]
# Focus is not stacking: B hovered into focus (z 0) while A stayed on top of it.
raised = EVENT.replace("W 0xaa 100 100 600 400 1", "W 0xaa 100 100 600 400 9")
raised = ";".join([r for r in raised.split(";") if not r.startswith("W 0xaa")] + [r for r in raised.split(";") if r.startswith("W 0xaa")])
assert not rails_for(raised, OWN, "right")["0xaa"]["covered"], "A is last in the stacking order, so nothing is in front of it, whatever has focus"
fs = EVENT.replace("W 0xdd 7 7 1906 1066 3 0 0", "W 0xdd 7 7 1906 1066 3 2 0")
assert all(r["covered"] for side_ in ("top", "right") for r in rails_for(fs, ALL, side_).values()), \
    "a fullscreen window covers every rail on its monitor"
# A maximized window has no border (the mode's rule takes it off), so its bar starts at the
# content's edge exactly, and its rail says it is maximized for the restore icon.
mx = rails_for(EVENT.replace("W 0xcc 1200 600 300 200 2 0 1 0", "W 0xcc 6 46 1908 1028 2 0 1 1"), OWN, "top")["0xcc"]
assert (mx["x"], mx["y"], mx["w"], mx["h"]) == (6, 6, 1908, RAIL) and mx["maximized"], mx
print("ok  rails: on the content edge over the border, cut back behind whatever is in front")

area = state["areas"]["eDP-1"]

full = {"x": 7, "y": 7, "w": 1906, "h": 1066}
assert js(f"fit({json.dumps(full)}, {json.dumps(area)}, 1, {RAIL}, 'right')") == {"x": 7, "y": 7, "w": 1906 - RAIL, "h": 1066}
assert js(f"fit({json.dumps(full)}, {json.dumps(area)}, 1, {RAIL}, 'top')") == {"x": 7, "y": 7 + RAIL, "w": 1906, "h": 1066 - RAIL}
edge = {"x": 1500, "y": 100, "w": 400, "h": 300}
f = js(f"fit({json.dumps(edge)}, {json.dumps(area)}, 1, {RAIL}, 'right')")
assert f["w"] == 400 and f["x"] + 400 + 1 + RAIL == area["x1"], f"a window at the edge slides left, unresized: {f}"
high = {"x": 300, "y": 10, "w": 400, "h": 300}
f = js(f"fit({json.dumps(high)}, {json.dumps(area)}, 1, {RAIL}, 'top')")
assert f["h"] == 300 and f["y"] - 1 - RAIL == area["y0"], f"a window at the top slides down, unresized: {f}"
for side_ in ("top", "right"):
    assert js(f"fit({{x: 100, y: 100, w: 400, h: 300}}, {json.dumps(area)}, 1, {RAIL}, '{side_}')") is None
print("ok  fit: a new window never pushes its controls off the monitor")

P, B, ROUND = 2.5, 1, 18
r = ROUND  # the content's corner: the notch follows it, not the border's
U = js("UNDERLAP")  # ...running just under it, so the two antialiased edges overlap
for side_, bw, bh in [("right", B + RAIL, 402), ("top", 602, B + RAIL)]:
    pts = js(f"railOutline({bw}, {bh}, {ROUND}, {B}, {P}, 10, '{side_}')")
    # Back to rail terms: `a` out from the content edge, `s` along it.
    T, L = (bw, bh) if side_ == "right" else (bh, bw)
    AS = [(p["x"], p["y"]) if side_ == "right" else (T - p["y"], p["x"]) for p in pts]
    assert all(-r - 1e-9 <= a <= T + 1e-9 and -1e-9 <= s <= L + 1e-9 for a, s in AS), side_
    assert U >= 1, "meeting the content's edge exactly leaves a wallpaper-coloured hairline at the corners"
    notch = [(a, s) for a, s in AS if a < -1e-9 and B + U - 1e-9 < s < L - B - U + 1e-9]
    assert len(notch) >= 18, f"both notches are drawn ({side_})"
    for a, s in notch:
        cs = B + r if s < L / 2 else L - B - r
        on = abs(a + r) ** P + abs(s - cs) ** P
        assert abs(on - (r - U) ** P) < 1e-6 * r ** P, f"{side_} notch point {(a, s)} is off the content's superellipse"
    twice = sum(pts[k]["x"] * pts[k + 1]["y"] - pts[k + 1]["x"] * pts[k]["y"] for k in range(len(pts) - 1))
    twice += pts[-1]["x"] * pts[0]["y"] - pts[0]["x"] * pts[-1]["y"]
    assert abs(twice) > 2 * T * L * 0.9, f"the {side_} outline encloses the whole strip without folding back"
print("ok  outline: the notches follow the content's rounding_power corner, 1px under it, both sides")

# floatingMode.lua under plain Lua. The mock applies what is dispatched to plain window
# tables, and fires window.fullscreen when a window's internal mode changes, as Hyprland does.
LUA_FILE = SHELL / "services/floatingMode.lua"
MOCK = r"""
local wins, handlers, timers = {}, {}, {}
cursor = { x = 0, y = 0 }
local cfg = { ["general.border_size"] = 1, ["decoration.rounding"] = 18, ["decoration.rounding_power"] = 2.5 }
mon = { name = "eDP-1", x = 0, y = 0, width = 1920, height = 1080, scale = 1, transform = 0,
        reserved = { left = 0, top = 40, right = 0, bottom = 57 } }
local ws = { id = 1, name = "1", visible = true }
local function find(sel)
    if type(sel) == "table" then return sel end
    for _, w in ipairs(wins) do if sel == "address:" .. w.address then return w end end
end
local function d(name) return function(a) return { name = name, a = a } end end
hl = {
    dsp = { window = { resize = d("resize"), move = d("move"), fullscreen_state = d("fullscreen_state"), set_prop = d("set_prop"),
                       tag = d("tag"), float = d("float"), alter_zorder = d("alter_zorder") }, event = d("event") },
    dispatch = function(x)
        local w = x.a and x.a.window and find(x.a.window)
        if x.name == "resize" then w.size = { x = x.a.x, y = x.a.y }
        elseif x.name == "move" and x.a.x then w.at = { x = x.a.x, y = x.a.y }
        elseif x.name == "tag" and x.a.tag:sub(1, 1) == "+" then table.insert(w.tags, x.a.tag:sub(2))
        elseif x.name == "fullscreen_state" then
            local was = w.fullscreen
            w.fullscreen, w.fullscreen_client = x.a.internal, x.a.client
            if was ~= w.fullscreen then handlers["window.fullscreen"](w) end
        end
    end,
    get_config = function(k) return cfg[k] end, config = function() end,
    get_monitors = function() return { mon } end, get_windows = function() return wins end,
    get_cursor_pos = function() return cursor end, get_active_workspace = function() return ws end,
    window_rule = function() return { set_enabled = function() end } end,
    on = function(ev, fn) handlers[ev] = fn return { remove = function() end } end,
    timer = function(fn, o)
        if o.type == "repeat" then tick = fn else timers[#timers + 1] = fn end
        return { set_enabled = function() end }
    end,
}
H = handlers
function flush() while #timers > 0 do table.remove(timers, 1)() end end
function open(a, x, y, w, h, class)
    local win = { address = a, at = { x = x, y = y }, size = { x = w, y = h }, floating = true, fullscreen = 0, fullscreen_client = 0,
        mapped = true, hidden = false, pinned = false, workspace = ws, monitor = mon, tags = {}, class = class or "kitty", pid = 1,
        focus_history_id = 0 }
    wins[#wins + 1] = win
    H["window.open"](win)
    return win
end
-- What Hyprland does to a floating window it maximizes itself, sync on: both modes to 1,
-- the box to its own maximized one, then the event.
function hypr_maximize(w)
    w.fullscreen, w.fullscreen_client, w.at, w.size = 1, 1, { x = 5, y = 45 }, { x = 1910, y = 973 }
    H["window.fullscreen"](w)
end
function fullscreen(w, on)
    w.fullscreen, w.fullscreen_client = on and 2 or 0, on and 2 or 0
    if not on then w.at, w.size = { x = 1, y = 1 }, { x = 10, y = 10 } end -- Hyprland recentres after the hook
    H["window.fullscreen"](w)
end
function eq(w, x, y, ww, hh, msg)
    assert(w.at.x == x and w.at.y == y and w.size.x == ww and w.size.y == hh,
        string.format("%s: got %d,%d %dx%d, want %d,%d %dx%d", msg, w.at.x, w.at.y, w.size.x, w.size.y, x, y, ww, hh))
end
"""
BEHAVIOUR = r"""
local M = dofile(LUA_FILE)
M.install({ bar_classes = { "kitty" }, side = "top", size = 40, event = "iiFloatingMode", tick = 16 })
-- The work area is 0,40 .. 1920,1023 (bar and dock reserved). A kitty has a 40px bar and a
-- 1px border, so its content may go 1,81 .. 1919,1022 unmaximized: 1918x941.
local a = open("0xa", 560, 281, 800, 500)
eq(a, 560, 302, 800, 500, "Hyprland centred it on the work area; it goes centred below its bar")
local b = open("0xb", 560, 281, 800, 500)
eq(b, 600, 322, 800, 500, "same place as a, which it would cover completely: cascaded by 1920/48, 983/48 (KWin)")
-- Opened on a workspace out of sight (a rule's "9 silent"), it still cascades off that
-- workspace's own windows, not the ones on screen.
local hidden = { id = 9, name = "9", visible = false }
local function on_hidden(a)
    local w = { address = a, at = { x = 560, y = 281 }, size = { x = 800, y = 500 }, floating = true, fullscreen = 0,
        fullscreen_client = 0, mapped = true, hidden = false, pinned = false, workspace = hidden, monitor = mon, tags = {}, class = "plain" }
    table.insert(hl.get_windows(), w)
    H["window.open"](w)
    return w
end
local h1, h2 = on_hidden("0xh1"), on_hidden("0xh2")
eq(h1, 560, 281, 800, 500, "first on its workspace: centred (a pixel off is left be)")
eq(h2, 600, 301, 800, 500, "second on the same hidden workspace: cascaded off the first")
h1.mapped, h2.mapped = false, false
local c = open("0xc", 7, 47, 1906, 969)
assert(c.fullscreen == 0 and c.fullscreen_client == 1, "over 80% of the area it opens maximized (Mutter), and the app is told")
eq(c, 0, 80, 1920, 943, "maximized: the work area edge to edge, below the bar, no border")
local huge = open("0xd", 100, 100, 3000, 400, "plain")
eq(huge, 1, 100, 1918, 400, "wider than the area but under 80% of it: shrunk to fit and slid inside (KWin keepInArea)")
local placed = open("0xe", 50, 60, 300, 200, "plain")
eq(placed, 50, 60, 300, 200, "placed by a rule or its parent, not centred: left where it was put")

hypr_maximize(c)
assert(c.fullscreen_client == 0, "Super+D on a maximized window restores it")
eq(c, 102, 95, 1716, 872, "restore caps at 80% of the area, aspect kept, centred where it was (Mutter, KWin)")

hypr_maximize(a)
hypr_maximize(b)
assert(a.fullscreen == 0 and a.fullscreen_client == 1 and b.fullscreen_client == 1,
    "two windows maximized at once, each a plain floating window to Hyprland (internal 0)")
eq(a, 0, 80, 1920, 943, "a stays maximized with b maximized too")

a.fullscreen_client = 0 -- its own restore button: the client alone, no event
tick()
eq(a, 560, 302, 800, 500, "an app restoring itself goes back to its own box")

hypr_maximize(a)
cursor.x, cursor.y = 1500, 60
M.before_drag("0xa")
assert(a.fullscreen_client == 0, "a drag takes a window out of maximize")
eq(a, 874, 90, 800, 500, "grab point at x 1500 of 1920 stays at that fraction of the restored frame (KWin)")

fullscreen(b, true)
fullscreen(b, false)
tick()
flush()
assert(b.fullscreen == 0 and b.fullscreen_client == 1, "out of fullscreen, back to the maximize it left")
eq(b, 0, 80, 1920, 943, "and at its maximized box, once Hyprland is done recentring it")

mon.reserved.bottom = 0
tick()
eq(b, 0, 80, 1920, 1000, "the dock hidden: a maximized window follows its work area")

b.at = { x = 300, y = 80 }
cursor.x, cursor.y = 400, 100
tick()
assert(b.fullscreen_client == 0, "moved by something else (a gesture): out of maximize")
assert(b.size.x == 800 and b.size.y == 500, "at its restored size")

M.before_drag("0xe")
eq(placed, 50, 60, 300, 200, "before_drag leaves a window that is not maximized alone")
print("lua ok")
"""
with tempfile.TemporaryDirectory() as tmp:
    test = pathlib.Path(tmp) / "t.lua"
    test.write_text(MOCK + f"\nLUA_FILE = [[{LUA_FILE}]]\n" + BEHAVIOUR)
    run = subprocess.run(["lua", str(test)], capture_output=True, text=True)
    assert run.returncode == 0 and "lua ok" in run.stdout, run.stderr or run.stdout
print("ok  window management: KWin's placement and cascade, Mutter's auto-maximize and restore cap, many maximized at once")

lua_src = LUA_FILE.read_text()
subprocess.run(["luac", "-p", str(LUA_FILE)], check=True)
inst = js(f"installExpr({json.dumps(str(LUA_FILE))}, {{barClasses: ['kitty', 'x\"] = os.exit() --'], side: 'top', size: 40}})")
with tempfile.TemporaryDirectory() as tmp:
    for name, lua in [("install", inst), ("float-all", js("floatAllExpr(['0x1a2b', 'x\"] = os.exit() --'])")), ("disable", js("disableExpr()")),
                      ("drag", js("beforeDragExpr('0x1a2b')")), ("bars-off", js("BARS_OFF_LUA"))]:
        path = pathlib.Path(tmp) / f"{name}.lua"
        path.write_text(lua)
        subprocess.run(["luac", "-p", str(path)], check=True)
        assert "os.exit" not in lua, f"a non-hex address or an odd class reached the Lua ({name})"
assert '"kitty"' in inst and js("beforeDragExpr('x\"y')") is None
# hyprbars: the compositor draws the top bar, so it cannot trail its window.
bars = js("barsLua({height: 40, color: 'rgba(1c1b1fff)', text: 'rgba(e6e1e5ff)', font: 'Google Sans Flex', textSize: 13, padding: 12, gap: 12, button: 32})")
with tempfile.NamedTemporaryFile("w", suffix=".lua") as t:
    t.write(bars)
    t.flush()
    subprocess.run(["luac", "-p", t.name], check=True)
# KWin's focus and stacking, from kwin.kcfg's defaults, only while the mode is on.
active = lua_src.split('on("window.active"')[1].split("\n    end)")[0]
assert 'alter_zorder({ mode = "top", window = w })' in active and "p.pinned" in active, \
    "whatever activates a window raises it, and keep-above (pinned) windows go back over it: Hyprland's focus raises nothing"
assert "follow_mouse = 2" in lua_src and "focus_on_close = 2" in lua_src and "window_gap = 10, monitor_gap = 10" in lua_src, \
    "click to focus with the pointer's window taking scroll; focus goes to the next in stacking order on close; 10px snap zones"
assert lua_src.index("if not ii_fm_saved") < lua_src.index("follow_mouse = 2"), "the user's values are saved before they are overridden"
assert "hl.config(ii_fm_saved)" in lua_src.split("function M.disable")[1], "turning the mode off gives tiling its own focus back"
assert "fullscreen_state_client = 1" in lua_src and "rounding = 0, border_size = 0" in lua_src, \
    "a maximized window has square corners and no border, as Breeze draws one"
assert "ii_fm_bar_classes[w.class]" in lua_src, "a known class is tagged as its window opens, so its bar is there on the first frame"
assert "delete root.barred[address]" in (SHELL / "services/FloatingMode.qml").read_text(), \
    "Hyprland reuses a closed window's address; a stale 'already tagged' kept the next window bar-less"
assert 'on("window.close"' in lua_src and "function M.forget" in lua_src, "the Lua forgets a closed window's boxes too"
assert js("barClassExpr('a\"b')") is None
assert "bar_precedence_over_border = true" in bars, "the border has to wrap bar and window as one shape"
assert 'tag = "negative:iibar"' in bars and "no_bar\"] = false" not in bars, \
    "rules only ever say 'no bar': an 'on' rule against an 'off' one left windows tagged as they opened bar-less"
assert bars.count("add_button") == 3 and "if not ii_fm_buttons" in bars, "buttons are added once per Lua state; a reload clears them"
assert bars.count("fg_color") == 3, "in Lua a button with no fg_color fails to add at all"
assert bars.index("ii_fm_buttons = true") > bars.rindex("add_button"), "the buttons-added flag goes up only once they are"
assert all(0xE000 > ord(c) or ord(c) > 0xF8FF for c in bars), \
    "hyprbars sets icons in 'sans': a private-use (Material Symbols) codepoint renders as some other font's glyph"
assert js("BARS_OFF_LUA") in js("disableExpr()") and '"-" .. M.BAR_TAG' in lua_src
alt = (SHELL / "modules/ii/altTab/AltTab.qml").read_text()
assert "if (target.floating) return;" in alt.split("function confirm()")[1].split("fullscreen({ mode")[0], \
    "Alt+Tab hands a maximize to a tiled window only: a floating one is raised over it, and handed the state it fills the screen"
script = SHELL / "scripts/hyprland/hyprbars.sh"
assert script.stat().st_mode & 0o111, "hyprbars.sh has to be executable"
sh = script.read_text()
assert '"$commit' in sh and "built-for" in sh and "sha1sum" in sh, "the build is keyed on the running Hyprland's commit and the patch"
assert 'git -C "$src" apply "$patch"' in sh, "hyprbars is built with its patch"
assert 'mv -f "$out/hyprbars.so.new" "$out/hyprbars.so"' in sh and 'cp "$src/hyprbars/hyprbars.so" "$out/hyprbars.so"' not in sh, \
    "the new build goes in by rename: writing over the library the compositor has mapped crashes it"
assert "ii_fm_buttons, ii_fm_bars_untagged, ii_fm_bars_tiled = nil" in sh, "a swapped plugin gets its buttons and rules declared again"
subprocess.run(["bash", "-n", str(script)], check=True)
patch = (SHELL / "scripts/hyprland/hyprbars.patch").read_text()
assert "ii_fm_lib.before_drag" in patch and "handleMovement();" in patch, "hyprbars' title drag calls before_drag before it starts"
keys = (HYPR / "keybinds.lua").read_text()
assert "ii_fm_lib.before_drag()" in keys and 'hl.bind("SUPER + mouse:272", dragWindow' in keys, "so does Super+drag"
assert 'if hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { enabled = false } } }) end' in (HYPR / "rules.lua").read_text(), \
    "a reload resets hyprbars to a bar on every window until the shell is back; the config starts it off"

for expr in ["focusExpr('0xab')", "moveExpr('0xab', 1.4, 2.6)", "resizeExpr('0xab', 10, 20)", "minimizeExpr('0xab')", "noAnimExpr('0xab', true)", "raiseExpr('0xab')"]:
    e = js(expr)
    with tempfile.NamedTemporaryFile("w", suffix=".lua") as t:
        t.write("return hl.dispatch(" + e + ")")
        t.flush()
        subprocess.run(["luac", "-p", t.name], check=True)
focus = js("focusExpr('0xab')")
assert "no_warps = true" in focus and "no_warps = o" in focus, \
    "a focus that warps the pointer turns a press on the bar into a drag that throws the window"
assert js("moveExpr('0xab', 1.4, 2.6)") == 'hl.dsp.window.move({ x = 1, y = 3, window = "address:0xab" })'
probe = js("OWN_CONTROLS_PATTERN")
for line, own in [("7f0 r--p 0 fe:01 1 /opt/Obsidian/resources.pak", True),
                  ("7f0 r-xp 0 fe:01 1 /usr/lib/zen-browser/libxul.so", True),
                  ("7f0 r-xp 0 fe:01 1 /usr/lib/libadwaita-1.so.0", True),
                  ("7f0 r-xp 0 fe:01 1 /usr/lib/libQt6Widgets.so.6.11.2", False),
                  ("7f0 r-xp 0 fe:01 1 /usr/lib/libgtk-3.so.0.2420.32", False)]:
    hit = subprocess.run(["grep", "-qE", probe], input=line, text=True).returncode == 0
    assert hit == own, f"own-controls probe got {line!r} wrong"
out = subprocess.run(["sh", "-c", js("OWN_CONTROLS_PROBE"), "sh", "1"], capture_output=True, text=True).stdout
assert out.strip() == "1 0", f"an unreadable /proc/<pid>/maps must read as 'no controls', not break: {out!r}"
print("ok  Lua: every chunk parses; the probe tells Chromium, Firefox and libadwaita from Qt and GTK3")

qt = SHELL / "modules/ii/sidebarDashboard/quickToggles/androidStyle"
assert "floatingMode:" in (qt / "QuickToggleCatalog.js").read_text()
assert 'roleValue: "floatingMode"' in (qt / "AndroidToggleDelegateChooser.qml").read_text()
family = (SHELL / "panelFamilies/IllogicalImpulseFamily.qml").read_text()
assert "extraCondition: (FloatingMode.enabled && !FloatingMode.pluginBars) || FloatingMode.rails.length > 0; component: FloatingRails" in family, \
    "the shell's own bars load when hyprbars is not drawing them, and outlive the mode until the last has faded"
assert '"custom"].includes(event.name)) return;' in (SHELL / "services/HyprlandData.qml").read_text(), \
    "HyprlandData must ignore the watcher's custom events"
assert 'hl.dsp.global("quickshell:floatingModeToggle")' in (HYPR / "keybinds.lua").read_text()
assert 'namespace = "quickshell:floatingRails" }, blur = false' in (HYPR / "rules.lua").read_text()
assert 'Config.options.windows.floatingControls = newValue' in (SHELL / "modules/settings/HyprlandConfig.qml").read_text(), \
    "the controls' side is a setting"
assert 'property string floatingControls: "top"' in (SHELL / "modules/common/Config.qml").read_text(), "the top bar is the default"
rails_qml = (SHELL / "modules/ii/floatingRails/FloatingRails.qml").read_text()
assert "item: rail.shown ? hit : null" in rails_qml and "scale:" not in rails_qml, \
    "the masked item is the plain hit box; fades live on a child (tools/check-mask-regions.py)"
print("ok  wiring: toggle, loader, event filter, keybind, layer rule")
