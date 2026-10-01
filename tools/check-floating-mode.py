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
  - Maximize takes a lone tile's place, inside gaps_out with its border and corners (the
    owner's call over KWin's edge to edge), survives a minimize, and any number of windows can be
    maximized at once. Every path into Hyprland's own maximize (Super+D, the bar, an
    app's button) is turned into it; Hyprland's allows one window per workspace and
    hides the rest.
  - Restore goes back to the size the window had, centred where it was, capped at 80% of
    the area (Mutter): restoring to the tile's size looked like nothing happened.
  - An app restoring itself, fullscreen from maximized and back, and a work area that
    grows are each followed. A drag brings a maximized window out with the grab point at
    the same fraction of it (KWin), and a window moved by anything else leaves maximize.
  - Minimize hands the focus to the next window down (KWin). An activation (urgent, then
    focus) brings a minimized window back once Hyprland's focus is done, not from inside the
    workspace change that focus is making. Hyprland's own refocus does not: a window alone
    on its workspace keeps the focus while minimized, and closing the right panel handed it
    back and brought the window back unasked. The dock and Alt+Tab ask instead of activating, which
    would open the hidden workspace over the screen first. Both look like a close and an
    open (hyprbars.patch): Hyprland only fades a window moving between workspaces.
  - An app's own maximize button is a toggle of the one record, since Hyprland tells every
    app it is maximized. Two copies of the state (Hyprland's and a table's), each flipped
    on its own, left windows that would not maximize until Super+D.
  - The mock is Hyprland as its source reads, not as it would be convenient: the window
    put back after the fullscreen hook, the silent move that leaves the focus, the
    fullscreen_state that clears modes it is asked to set again, the activation skipped on
    a focused window. Thousands of random presses from every source, on five seeds, are
    checked after each against the record: the owner's bugs were all of the "sometimes" kind.

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
import os
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
# A maximized window's rail says so, for the restore icon.
mx = rails_for(EVENT.replace("W 0xcc 1200 600 300 200 2 0 1 0", "W 0xcc 7 47 1906 1026 2 0 1 1"), OWN, "top")["0xcc"]
assert (mx["x"], mx["y"], mx["w"], mx["h"]) == (6, 6, 1908, 1 + RAIL) and mx["maximized"], mx
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
binds = {}
cursor = { x = 0, y = 0 }
local cfg = { ["general.border_size"] = 1, ["decoration.rounding"] = 18, ["decoration.rounding_power"] = 2.5,
              ["general.gaps_out"] = { top = 6, right = 6, bottom = 6, left = 6 } }
mon = { name = "eDP-1", x = 0, y = 0, width = 1920, height = 1080, scale = 1, transform = 0,
        reserved = { left = 0, top = 40, right = 0, bottom = 57 } }
ws = { id = 1, name = "1", visible = true }
ws2 = { id = 2, name = "2", visible = false }
minws = { id = -99, name = "special:minimized", visible = false }
local spaces = { [1] = ws, [2] = ws2 }
mon.active_workspace = ws
function mon.set_special_workspace(self, o) self.active_special_workspace, minws.visible = nil, false end
active = nil -- Hyprland's focused window
anims = {}
local function find(sel)
    if type(sel) == "table" then return sel end
    for _, w in ipairs(wins) do if sel == "address:" .. w.address then return w end end
end
-- FocusState: a window on the hidden special workspace opens that workspace over the one in
-- front; one on a workspace out of sight switches to it. The hook fires on a change only.
local function focus(w)
    if w.workspace == minws then
        minws.visible, mon.active_special_workspace = true, minws
    elseif not w.workspace.visible then
        for _, v in pairs(spaces) do v.visible = false end
        w.workspace.visible, mon.active_workspace = true, w.workspace
    end
    if active ~= w then
        active = w
        handlers["window.active"](w)
    end
end
local function d(name) return function(a) return { name = name, a = a } end end
hl = {
    dsp = { window = { resize = d("resize"), move = d("move"), fullscreen_state = d("fullscreen_state"), set_prop = d("set_prop"),
                       tag = d("tag"), float = d("float"), alter_zorder = d("alter_zorder"), drag = d("drag") }, event = d("event"), focus = d("focus") },
    dispatch = function(x)
        local w = x.a and x.a.window and find(x.a.window)
        if x.name == "resize" then w.size = { x = x.a.x, y = x.a.y }
        elseif x.name == "move" and x.a.x then w.at = { x = x.a.x, y = x.a.y }
        elseif x.name == "move" and x.a.workspace then
            local was = active == w
            local mid = { x = w.at.x + w.size.x / 2, y = w.at.y + w.size.y / 2 }
            w.workspace = x.a.workspace == "special:minimized" and minws or spaces[x.a.workspace]
            if x.a.follow == false and was then
                -- Actions::moveToWorkspace, silent: the window under where it was takes the
                -- focus. Over bare desktop, nothing does, and it stays on the window moved away.
                for i = #wins, 1, -1 do
                    local o = wins[i]
                    if o ~= w and o.mapped and o.workspace.visible and mid.x >= o.at.x and mid.x < o.at.x + o.size.x
                        and mid.y >= o.at.y and mid.y < o.at.y + o.size.y then focus(o) break end
                end
            end
        elseif x.name == "focus" then focus(w)
        elseif x.name == "alter_zorder" then
            for i, o in ipairs(wins) do if o == w then table.remove(wins, i) break end end
            wins[#wins + 1] = w
        elseif x.name == "tag" and x.a.tag:sub(1, 1) == "+" then table.insert(w.tags, x.a.tag:sub(2))
        elseif x.name == "fullscreen_state" then
            -- Actions::fullscreenWindow: asked for the modes it has already, it clears both.
            local was, i, c = w.fullscreen, x.a.internal, x.a.client
            if w.fullscreen == i and w.fullscreen_client == c then i, c = 0, 0 end
            w.fullscreen, w.fullscreen_client = i, c
            if was ~= w.fullscreen then handlers["window.fullscreen"](w) end
        end
    end,
    get_config = function(k) return cfg[k] end, config = function() end,
    get_monitors = function() return { mon } end,
    get_windows = function(f)
        local out = {}
        for _, w in ipairs(wins) do if not (f and f.mapped) or w.mapped then out[#out + 1] = w end end
        return out
    end,
    get_active_window = function() return active end,
    get_cursor_pos = function() return cursor end,
    get_active_workspace = function() return mon.active_special_workspace or mon.active_workspace end,
    window_rule = function() return { set_enabled = function() end } end,
    -- hyprbars.patch: hide snapshots the window, runs fn (the move away), and closes the
    -- snapshot; show pops it in from wherever it is.
    plugin = { hyprbars = {
        hide = function(a, fn)
            local w = find("address:" .. a)
            assert(w.workspace ~= minws, "hide on a window already hidden")
            fn()
            assert(w.workspace == minws, "hide's fn hides it")
            anims[#anims + 1] = "hide " .. a
        end,
        show = function(a)
            local w = find("address:" .. a)
            anims[#anims + 1] = string.format("show %s %d,%d %dx%d", a, w.at.x, w.at.y, w.size.x, w.size.y)
        end,
    } },
    bind = function(key, fn) binds[key] = fn end, unbind = function(key) binds[key] = nil end,
    on = function(ev, fn) handlers[ev] = fn return { remove = function() end } end,
    timer = function(fn, o)
        if o.type == "repeat" then tick = fn else timers[#timers + 1] = fn end
        return { set_enabled = function() end }
    end,
}
H = handlers
function flush() while #timers > 0 do table.remove(timers, 1)() end end
function open(a, x, y, w, h, class, space)
    local win = { address = a, at = { x = x, y = y }, size = { x = w, y = h }, floating = true, fullscreen = 0, fullscreen_client = 0,
        mapped = true, hidden = false, pinned = false, workspace = space or ws, monitor = mon, tags = {}, class = class or "kitty", pid = 1,
        focus_history_id = 0 }
    wins[#wins + 1] = win
    H["window.open"](win)
    if win.workspace.visible then focus(win) end
    return win
end
-- CWindow::activate, as the dock's foreign-toplevel activate and an app's xdg activation
-- reach it: a window that has the focus already is skipped, any other marked urgent and focused.
function activate(w)
    if active == w then return end
    H["window.urgent"](w)
    focus(w)
end
-- What Hyprland does to a floating window it maximizes itself, sync on: both modes to 1,
-- the box to its own maximized one, then the event.
function hypr_maximize(w)
    w.fullscreen, w.fullscreen_client, w.at, w.size = 1, 1, { x = 5, y = 45 }, { x = 1910, y = 973 }
    H["window.fullscreen"](w)
end
function fullscreen(w, on)
    w.fullscreen, w.fullscreen_client = on and 2 or 0, on and 2 or 0
    H["window.fullscreen"](w)
    if not on then w.at, w.size = { x = 1, y = 1 }, { x = 10, y = 10 } end -- Hyprland puts it back after the hook
end
-- An app's own button. Its idea of its state is always "maximized" (Hyprland tells every
-- app so), and CWindow::onUpdateState takes any maximize request for a toggle of the client
-- mode: to none with no event (internal stays 0), or Hyprland's maximize. A minimize comes
-- through hyprbars.patch.
function app(w, what)
    if what == "minimize" then M.minimize(w.address)
    elseif w.fullscreen_client == 1 then w.fullscreen_client = 0
    elseif w.fullscreen_client == 0 then hypr_maximize(w) end
    flush()
end
function eq(w, x, y, ww, hh, msg)
    assert(w.at.x == x and w.at.y == y and w.size.x == ww and w.size.y == hh,
        string.format("%s: got %d,%d %dx%d, want %d,%d %dx%d", msg, w.at.x, w.at.y, w.size.x, w.size.y, x, y, ww, hh))
end
M = dofile(LUA_FILE)
M.install({ bar_classes = { "kitty" }, side = "top", size = 40, event = "iiFloatingMode", tick = 16 })
"""
BEHAVIOUR = r"""
-- The work area is 0,40 .. 1920,1023 (bar and dock reserved). A kitty has a 40px bar and a
-- 1px border, so its content may go 1,81 .. 1919,1022 unmaximized: 1918x941.
local a = open("0xa", 560, 281, 800, 500)
eq(a, 560, 302, 800, 500, "Hyprland centred it on the work area; it goes centred below its bar")
local b = open("0xb", 560, 281, 800, 500)
eq(b, 600, 322, 800, 500, "same place as a, which it would cover completely: cascaded by 1920/48, 983/48 (KWin)")
-- Opened on a workspace out of sight (a rule's "9 silent"), it still cascades off that
-- workspace's own windows, not the ones on screen.
local hidden = { id = 9, name = "9", visible = false }
local h1, h2 = open("0xh1", 560, 281, 800, 500, "plain", hidden), open("0xh2", 560, 281, 800, 500, "plain", hidden)
eq(h1, 560, 281, 800, 500, "first on its workspace: centred (a pixel off is left be)")
eq(h2, 600, 301, 800, 500, "second on the same hidden workspace: cascaded off the first")
h1.mapped, h2.mapped = false, false
local c = open("0xc", 7, 47, 1906, 969)
assert(c.fullscreen == 0 and c.fullscreen_client == 1, "over 80% of the area it opens maximized (Mutter), and the app is told")
eq(c, 7, 87, 1906, 929, "maximized: where a lone tile sits, inside gaps_out, border and bar kept (the owner's call)")
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
eq(a, 7, 87, 1906, 929, "a stays maximized with b maximized too")

a.fullscreen_client = 0 -- an XWayland app's own restore, through Hyprland: the client alone, no event
tick()
eq(a, 560, 302, 800, 500, "an app restoring itself goes back to its own box")

hypr_maximize(a)
cursor.x, cursor.y = 1500, 60
M.before_drag("0xa")
assert(a.fullscreen_client == 0, "a drag takes a window out of maximize")
eq(a, 873, 93, 800, 500, "grab point at x 1500 of the frame stays at that fraction of the restored frame (KWin)")

fullscreen(b, true)
fullscreen(b, false)
tick()
flush()
assert(b.fullscreen == 0 and b.fullscreen_client == 1, "out of fullscreen, back to the maximize it left")
eq(b, 7, 87, 1906, 929, "and at its maximized box, once Hyprland is done recentring it")

-- The bars' minimize button moves it to the hidden workspace itself, and Hyprland drops the
-- maximize on the way. It keeps its box while there and is maximized again as it comes
-- back (KWin); the watcher used to take the drop for the app restoring itself.
b.workspace, b.fullscreen_client = minws, 0
tick()
eq(b, 7, 87, 1906, 929, "minimized: left alone")
M.activate("0xb") -- the dock, or Alt+Tab
assert(b.fullscreen_client == 1 and b.workspace == ws, "back from minimize: maximized again, on its own workspace")
assert(active == b, "and focused")
eq(b, 7, 87, 1906, 929, "at its maximized box")

-- Minimized from its own button, it gives the focus to the next window down, as KWin does.
-- Left on it, Hyprland skips activating it (it has focus already) and the dock could never
-- bring it back.
app(b, "minimize")
assert(b.workspace == minws and active ~= b, "minimized, and the focus went on to another window")
activate(b) -- an app's xdg activation, the dock's own activate
flush()
assert(b.workspace == ws and b.fullscreen_client == 1, "activated, it comes back as it was")
assert(active == b and not minws.visible and mon.active_special_workspace == nil,
    "with the focus, and the hidden workspace the activation opened closed again")

-- Minimize and restore look like a close and an open (hyprbars.patch, hide and show): the
-- move is made inside hide, and show runs once the window is where it goes.
anims = {}
app(b, "minimize")
M.activate("0xb")
assert(#anims == 2 and anims[1] == "hide 0xb" and anims[2] == "show 0xb 7,87 1906x929",
    "hide around the move, show at the maximized box: " .. table.concat(anims, "; "))

-- Over bare desktop, Hyprland's own refocus finds nothing to give the focus to.
ws.visible, ws2.visible, mon.active_workspace = false, true, ws2
local other = open("0xo", 100, 100, 300, 200, "other", ws2)
local lone = open("0xl", 1500, 700, 300, 200, "lone", ws2)
app(lone, "minimize")
assert(active == other, "the next window down takes the focus, not just a window under it")
activate(lone)
flush()
assert(lone.workspace == ws2, "so an activation brings it back")
-- Alone on its workspace, nothing can take the focus from it: the dock and Alt+Tab bring it
-- back by asking, not by activating. Hyprland's own refocus lands on it (a panel closing hands
-- the focus back to the last window), and that is no one asking for it: it brought the window
-- back each time the owner closed the right panel.
other.mapped = false
H["window.close"](other)
focus(lone)
app(lone, "minimize")
assert(active == lone, "Hyprland leaves the focus on it")
activate(lone)
assert(lone.workspace == minws, "and so skips activating it, which is why the shell does not rely on that")
active = nil
focus(lone) -- refocusLastWindow, as the right panel closes
flush()
assert(lone.workspace == minws, "Hyprland's own refocus does not bring it back")
assert(not minws.visible and mon.active_special_workspace == nil, "and the hidden workspace it opened goes again")
M.activate("0xl")
assert(lone.workspace == ws2 and active == lone, "the dock's path brings it back")
lone.mapped = false
H["window.close"](lone)
ws.visible, ws2.visible, mon.active_workspace = true, false, ws
focus(b)

-- An app's own maximize button is a toggle of the record, whatever the app says: its idea
-- of its state is Hyprland's "maximized" from the first frame on.
app(b, "unmaximize")
tick()
assert(b.fullscreen_client == 0 and b.size.x == 800, "on a maximized window it restores")
app(b, "unmaximize")
assert(b.fullscreen_client == 1, "and again maximizes")
eq(b, 7, 87, 1906, 929, "where a maximized window goes")
-- Asked for the modes a window has, Hyprland's fullscreen_state clears them: a maximize
-- sent again used to leave the window at its maximized box with the app told it was not.
M.set(b, "maximized")
assert(b.fullscreen_client == 1, "maximizing a maximized window leaves it maximized")

mon.reserved.bottom = 0
tick()
eq(b, 7, 87, 1906, 986, "the dock hidden: a maximized window follows its work area")

b.at = { x = 300, y = 80 }
cursor.x, cursor.y = 400, 100
tick()
assert(b.fullscreen_client == 0, "moved by something else (a gesture): out of maximize")
assert(b.size.x == 800 and b.size.y == 500, "at its restored size")

M.before_drag("0xe")
eq(placed, 50, 60, 300, 200, "before_drag leaves a window that is not maximized alone")
-- Super+drag is the mode's own bind, so a maximized window is restored under the pointer
-- before Hyprland's drag reads its box, whatever the config in ~/.config/hypr says.
app(b, "unmaximize")
assert(b.fullscreen_client == 1, "b maximized again")
local drags = 0
local drag = hl.dsp.window.drag
hl.dsp.window.drag = function() return { name = "drag" } end
local dispatch = hl.dispatch
hl.dispatch = function(x) if x.name == "drag" then drags = drags + 1; assert(b.fullscreen_client == 0, "restored before the drag begins") end return dispatch(x) end
cursor.x, cursor.y = 1500, 60
assert(type(binds["SUPER + mouse:272"]) == "function", "the mode binds Super+drag itself")
binds["SUPER + mouse:272"]()
hl.dispatch, hl.dsp.window.drag = dispatch, drag
assert(drags == 1 and b.size.x == 800, "and then drags it, at its restored size under the pointer")

-- An app's last window closing leaves its size (on disk); its next main window opens at it.
mon.reserved.bottom = 57
local m1 = open("0xm1", 560, 281, 800, 500, "memo")
m1.size = { x = 600, y = 400 }
tick()
H["window.close"](m1)
m1.mapped = false
local m2 = open("0xm2", 560, 281, 800, 500, "memo")
assert(m2.size.x == 600 and m2.size.y == 400, "reopened at the size it closed at")
local d = open("0xd2", 810, 431, 300, 200, "memo") -- centred over its centred parent
assert(d.size.x == 300, "a second window of the app (a dialog) keeps its own size")
d.mapped = false
H["window.close"](d)
hypr_maximize(m2)
H["window.close"](m2)
m2.mapped = false
local m3 = open("0xm3", 560, 281, 800, 500, "memo")
assert(m3.fullscreen_client == 1, "closed maximized, it opens maximized")
hypr_maximize(m3)
assert(m3.size.x == 600 and m3.size.y == 400, "and restores to the size it had before")
local f = io.open(os.getenv("XDG_STATE_HOME") .. "/ii-ren/floating-sizes")
assert(f and f:read("a"):find("memo 600 400 1", 1, true), "kept on disk, so it outlives a Hyprland restart")
app(placed, "minimize")
assert(placed.workspace == minws, "an app's own minimize button minimizes it")
print("lua ok")
"""
# Random presses on everything that changes a window's state, from every source at once,
# checked after each against what the record says. The bugs this replaced were all of the
# "sometimes" kind: a sequence the fixed tests above never walk.
FUZZ = r"""
math.randomseed(tonumber(SEED))
local wins3 = { open("0xf1", 560, 281, 800, 500), open("0xf2", 300, 200, 600, 400, "plain"), open("0xf3", 7, 47, 1906, 969) }
local function shown(w) return w.workspace ~= minws end
local names = {}
local ops = {
    function(w) if shown(w) then app(w, "unmaximize") end end, -- its maximize button
    function(w) app(w, "minimize") end,
    function(w) M.set(w, "maximized") end, -- asked again for what it may already be
    function(w) if shown(w) and w.fullscreen ~= 2 then hypr_maximize(w) end end, -- Super+D, the bars' maximize
    function(w) if shown(w) then hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = w })) end end,
    function(w) if w.workspace == minws then M.activate(w.address) else activate(w) end end, -- the dock, Alt+Tab
    function(w) activate(w) end, -- an app's activation
    function(w) if w.workspace == minws then active = nil; focus(w) end end, -- Hyprland's refocus, a panel closing
    function(w)
        if not shown(w) then return end
        cursor.x, cursor.y = w.at.x + 10, w.at.y - 20
        M.before_drag(w.address)
        w.at = { x = w.at.x + 30, y = w.at.y + 20 }
    end,
    function(w) if shown(w) then fullscreen(w, w.fullscreen ~= 2) end end,
    function(w) if w.fullscreen == 0 and w.fullscreen_client == 1 then w.fullscreen_client = 0 end end, -- XWayland's own restore
    function() mon.reserved.bottom = mon.reserved.bottom == 0 and 57 or 0 end,
    function(w) if active == w then hl.dispatch(hl.dsp.window.move({ workspace = 1, window = w })) end end, -- Super+Shift+1
}
local labels = { "app button", "app min", "set max", "Super+D", "bar min", "dock", "activate", "refocus", "drag", "F11", "xwayland restore", "work area", "keybind move" }
local trail = {}
for step = 1, 4000 do
    local k, w = math.random(#ops), wins3[math.random(#wins3)]
    local was_min, had_focus = w.workspace == minws, active == w
    ops[k](w)
    trail[#trail + 1] = labels[k] .. " " .. w.address
    if #trail > 12 then table.remove(trail, 1) end
    tick(); flush(); tick()
    local why = "after " .. table.concat(trail, ", ") .. " (seed " .. SEED .. ", step " .. step .. ")"
    if k == 6 then assert(w.workspace ~= minws, "the dock brings back a minimized window, " .. why) end
    if k == 7 and was_min and not had_focus then assert(w.workspace ~= minws, "an activation brings one back, " .. why) end
    if k == 8 and was_min then assert(w.workspace == minws and not minws.visible, "Hyprland's own refocus leaves it minimized, " .. why) end
    for _, v in ipairs(wins3) do
        local s = ii_fm_win[v.address]
        assert(s, "every window has a record, " .. why)
        assert((s.mode == "minimized") == (v.workspace == minws), v.address .. " is " .. s.mode .. " on " .. v.workspace.name .. ", " .. why)
        if s.mode == "maximized" then
            assert(v.fullscreen == 0 and v.fullscreen_client == 1, v.address .. " maximized, but the app is not told so, " .. why)
            local want = M.max_box(M.work_area(mon), M.edges(v), hl.get_config("general.gaps_out"))
            eq(v, want.x, want.y, want.w, want.h, v.address .. " maximized, off its box, " .. why)
        elseif s.mode == "normal" then
            assert(v.fullscreen == 0 and v.fullscreen_client == 0, v.address .. " normal, but the app thinks otherwise, " .. why)
            assert(v.size.x >= 100 and v.size.y >= 100, v.address .. " lost its size, " .. why)
        elseif s.mode == "fullscreen" then
            assert(v.fullscreen == 2, v.address .. " fullscreen in the record only, " .. why)
        end
    end
end
print("fuzz ok")
"""
with tempfile.TemporaryDirectory() as tmp:
    for name, body, extra in [("t", BEHAVIOUR, ""), *[(f"fuzz{seed}", FUZZ, f"SEED = {seed}\n") for seed in (1, 2, 3, 4, 5)]]:
        test = pathlib.Path(tmp) / f"{name}.lua"
        test.write_text(f"LUA_FILE = [[{LUA_FILE}]]\n" + extra + MOCK + body)
        run = subprocess.run(["lua", str(test)], capture_output=True, text=True, env={**os.environ, "XDG_STATE_HOME": tmp})
        assert run.returncode == 0 and " ok" in run.stdout, run.stderr or run.stdout
print("ok  window management: KWin's placement and cascade, Mutter's auto-maximize and restore cap, many maximized at once")

lua_src = LUA_FILE.read_text()
subprocess.run(["luac", "-p", str(LUA_FILE)], check=True)
inst = js(f"installExpr({json.dumps(str(LUA_FILE))}, {{barClasses: ['kitty', 'x\"] = os.exit() --'], side: 'top', size: 40}})")
with tempfile.TemporaryDirectory() as tmp:
    for name, lua in [("install", inst), ("float-all", js("floatAllExpr(['0x1a2b', 'x\"] = os.exit() --'])")), ("disable", js("disableExpr()")),
                      ("drag", js("beforeDragExpr('0x1a2b')")), ("bars-off", js("BARS_OFF_LUA")), ("activate", js("activateExpr('0x1a2b')"))]:
        path = pathlib.Path(tmp) / f"{name}.lua"
        path.write_text(lua)
        subprocess.run(["luac", "-p", str(path)], check=True)
        assert "os.exit" not in lua, f"a non-hex address or an odd class reached the Lua ({name})"
assert '"kitty"' in inst and js("beforeDragExpr('x\"y')") is None and js("activateExpr('x\"y')") is None
# hyprbars: the compositor draws the top bar, so it cannot trail its window.
bars = js("barsLua({height: 40, color: 'rgba(1c1b1fff)', text: 'rgba(e6e1e5ff)', font: 'Google Sans Flex', chip: 'rgba(2b2930ff)', closeHover: 'rgba(8c1d18ff)', textSize: 13, padding: 12, gap: 12, button: 32})")
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
assert "rounding = 0" not in lua_src and "border_size = 0" not in lua_src, \
    "a maximized window keeps a tile's border and corners (the owner's call); a rule squaring them outlived the maximize"
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
fmq = (SHELL / "services/FloatingMode.qml").read_text()
assert '"configreloaded")' in fmq and "FM.BARS_OFF_LUA" in fmq.split("function startOrOff")[1].split("GlobalShortcut")[0], \
    "a reload resets a loaded hyprbars to enabled: with the mode off it barred every window, so the off path re-applies too"
alt = (SHELL / "modules/ii/altTab/AltTab.qml").read_text()
assert "if (target.floating) return;" in alt.split("function confirm()")[1].split("fullscreen({ mode")[0], \
    "Alt+Tab hands a maximize to a tiled window only: a floating one is raised over it, and handed the state it fills the screen"
confirm = alt.split("function confirm()")[1]
assert confirm.index("FloatingMode.restoreMinimized(target.address)") < confirm.index("hl.dsp.focus"), \
    "Alt+Tab brings a minimized window back by asking: Hyprland skips activating one that kept the focus"
for dock in ("modules/ii/dock/DockAppButton.qml", "modules/ii/dock/widgets/DockPreviewPopup.qml"):
    assert "FloatingMode.restoreMinimized(HyprlandData.clientForToplevel(" in (SHELL / dock).read_text(), f"{dock} too"
script = SHELL / "scripts/hyprland/hyprbars.sh"
assert script.stat().st_mode & 0o111, "hyprbars.sh has to be executable"
sh = script.read_text()
assert '"$commit' in sh and "built-for" in sh and "sha1sum" in sh, "the build is keyed on the running Hyprland's commit and the patch"
assert 'patch -s -p1 -d "$work" < "$patch"' in sh, "hyprbars is built with its patch"
assert "flock -w" in sh and 'git -C "$src" archive' in sh and "checkout" not in sh, \
    "one build at a time, from a clean export in its own directory: two builds in one tree tore a build and crashed the compositor"
assert "hyprlandCrashReport" in sh and 'touch "$out/DISABLED"' in sh and sh.index("DISABLED ]] && exit 1") < sh.index("plugin load"), \
    "a build the compositor crashed with is never loaded again"
assert 'mv -f "$out/hyprbars.so.new" "$out/hyprbars.so"' in sh and 'cp "$src/hyprbars/hyprbars.so" "$out/hyprbars.so"' not in sh, \
    "the new build goes in by rename: writing over the library the compositor has mapped crashes it"
assert "ii_fm_buttons, ii_fm_bars_untagged, ii_fm_bars_tiled = nil" in sh, "a swapped plugin gets its buttons and rules declared again"
subprocess.run(["bash", "-n", str(script)], check=True)
patch = (SHELL / "scripts/hyprland/hyprbars.patch").read_text()
assert "ii_fm_lib.before_drag" in patch and "handleMovement();" in patch, "hyprbars' title drag calls before_drag before it starts"
assert "strokeIcon" in patch and "hover.a               = 0.08;" in patch and "mask != m_iButtonHoverState" in patch, \
    "icons stroked centred in their chip, and M3's 8% hover layer, cleared when the pointer leaves (one flag for all missed that)"
assert "plugin:hyprbars:close_hover_color" in patch and 'button.icon == "ii:close"' in patch, "close hovers in its own colour"
assert 'pcall(hl.get_config, "plugin.hyprbars.close_hover_color")' in bars and '"ii:close", "ii:maximize", "ii:minimize"' in bars, \
    "the ii: icons only when the plugin can draw them: an unpatched one would print them as words"
assert "close_hover_color = [[rgba(8c1d18ff)]]" in bars and bars.count("bg_color = [[rgba(2b2930ff)]]") == 3, \
    "chips a layer up from the bar, close's hover the error container: both from the shell's colours"
assert "requestsMinimize" in patch and "ii_fm_lib.minimize" in patch, \
    "an app's own minimize (xdg set_minimized) reaches the mode: Hyprland drops it, and Chromium froze waiting"
keys = (HYPR / "keybinds.lua").read_text()
drag_keys = lua_src.split("M.DRAG_KEYS = ")[1].split("\n")[0]
assert all(f'hl.bind("{k}", hl.dsp.window.drag()' in keys and f'"{k}"' in drag_keys for k in ("SUPER + mouse:272", "SUPER + mouse:274")), \
    "the mode binds Super+drag over the config's own drag keys, and gives them back the plain drag when it goes"
assert "hl.unbind(key)" in lua_src.split("function fm.stop()")[1][:300], "and when it stops, the plain drag is back"
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
