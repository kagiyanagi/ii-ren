.pragma library

// Floating mode's shell half: what the compositor reports, where the shell-drawn
// controls sit, and the one-line evals that drive floatingMode.lua, the half that runs
// inside Hyprland. tools/check-floating-mode.py runs this under node.

var EVENT = "iiFloatingMode";
var MINIMIZED = "special:minimized";
// One frame at 60Hz. The watcher only reports when something changed, so an idle
// desktop costs a ~15us Lua walk per tick and no IPC at all. Half a frame was
// measured against this during a drag and bought nothing: both leave the bar at
// most one frame behind, exact on about half the frames.
var TICK_MS = 16;

var ADDRESS = /^0x[0-9a-fA-F]+$/;
// A window class that may go into Lua unquoted-safe: anything else is left out of the
// class cache and gets its bar the slow way, from its address.
var CLASS = /^[A-Za-z0-9_.\-]+$/;
// hyprbars draws the bar of every floating window tagged this.
var BAR_TAG = "iibar";

// "B border rounding power;M monitor x0 y0 x1 y1;W address x y w h z fs floating max monitor pid class"
// M is a monitor's work area: the monitor less the bar and dock reservations. W is every mapped window on a visible
// workspace, bottom to top: Hyprland lists windows in stacking order. z is the
// focus-history index, 0 being the focused window -- which is not the same thing,
// since focus follows the mouse without raising anything. max: maximized by the mode.
function parse(data) {
    var state = { border: 0, rounding: 0, power: 2, areas: {}, windows: [] };
    var records = String(data).split(";");
    for (var i = 0; i < records.length; i++) {
        var f = records[i].split(" ");
        if (f[0] === "B") {
            state.border = +f[1];
            state.rounding = +f[2];
            state.power = +f[3] || 2;
        } else if (f[0] === "M" && f.length >= 6) {
            state.areas[f[1]] = { x0: +f[2], y0: +f[3], x1: +f[4], y1: +f[5] };
        } else if (f[0] === "W" && f.length >= 12 && ADDRESS.test(f[1])) {
            state.windows.push({
                address: f[1], x: +f[2], y: +f[3], w: +f[4], h: +f[5], z: +f[6],
                fullscreen: f[7] !== "0", floating: f[8] === "1", maximized: f[9] === "1", monitor: f[10],
                pid: +f[11], cls: f[12] || ""
            });
        }
    }
    return state;
}

function outer(w, b) {
    return { x0: w.x - b, y0: w.y - b, x1: w.x + w.w + b, y1: w.y + w.h + b };
}

function overlaps(a, c) {
    return a.x0 < c.x1 && c.x0 < a.x1 && a.y0 < c.y1 && c.y0 < a.y1;
}

// The controls sit on one side of the window: "top", a caption bar as Android 16's
// desktop windows have, or "right", a rail down the side. `thickness` is how far
// they reach past the window's border.

// Where a window has to go for its controls to stay on its monitor: slid in if it
// fits, shrunk if it does not. null when it already fits.
function fit(w, area, b, thickness, side) {
    if (!area)
        return null;
    var o = outer(w, b);
    if (side === "top") {
        if (o.y0 - thickness >= area.y0)
            return null;
        var height = o.y1 - o.y0, vroom = area.y1 - area.y0 - thickness;
        if (height <= vroom)
            return { x: w.x, y: area.y0 + thickness + b, w: w.w, h: w.h };
        return { x: w.x, y: area.y0 + thickness + b, w: w.w, h: vroom - 2 * b };
    }
    if (o.x1 + thickness <= area.x1)
        return null;
    var width = o.x1 - o.x0, room = area.x1 - thickness - area.x0;
    if (width <= room)
        return { x: area.x1 - thickness - width + b, y: w.y, w: w.w, h: w.h };
    return { x: area.x0 + b, y: w.y, w: room - 2 * b, h: w.h };
}

// The controls' box. It starts at the window's content edge, not its border: it
// covers the border on that side, so nothing -- not the border line, not the
// border's rounded corner -- shows between the window and its controls.
function railBox(w, b, thickness, side) {
    if (side === "top")
        return { x0: w.x - b, y0: w.y - b - thickness, x1: w.x + w.w + b, y1: w.y };
    return { x0: w.x + w.w, y0: w.y - b, x1: w.x + w.w + b + thickness, y1: w.y + w.h + b };
}

// The longest stretch of the strip, [s0, s1] along it from its start, that no
// covering box overlaps. A box that dips into the strip at all takes its whole
// stretch: the strip is drawn above it, so any overlap would paint over it.
function freeSpan(box, covers, side) {
    var top = side === "top";
    var start = top ? box.x0 : box.y0, end = top ? box.x1 : box.y1;
    var cuts = [];
    for (var i = 0; i < covers.length; i++) {
        var c = covers[i];
        cuts.push([Math.max(start, top ? c.x0 : c.y0) - start, Math.min(end, top ? c.x1 : c.y1) - start]);
    }
    cuts.sort(function (p, q) { return p[0] - q[0]; });
    var best = { s0: 0, s1: 0 }, at = 0;
    for (var k = 0; k <= cuts.length; k++) {
        var next = k < cuts.length ? cuts[k][0] : end - start;
        if (next - at > best.s1 - best.s0)
            best = { s0: at, s1: next };
        if (k < cuts.length)
            at = Math.max(at, cuts[k][1]);
    }
    return best;
}

// One entry per window that gets controls. They live on a layer above every
// window, so where a window in front overlaps them they must not be drawn: they
// would sit on top of the window that is really in front. In front means later in
// the watcher's list and floating (tiled windows are always below the floating
// ones), or fullscreen, which covers its whole monitor. What stays is the longest
// uncovered stretch (`span`); shorter than the strip is thick, and there is nothing
// worth showing, so it is `covered`.
function rails(state, hasRail, thickness, side) {
    var out = [];
    var ws = state.windows, b = state.border;
    for (var i = 0; i < ws.length; i++) {
        var w = ws[i];
        if (!w.floating || w.fullscreen || !hasRail(w))
            continue;
        var box = railBox(w, b, thickness, side);
        var covers = [];
        for (var j = 0; j < ws.length; j++) {
            var v = ws[j], o = outer(v, b);
            if (j !== i && v.monitor === w.monitor && (v.fullscreen || (v.floating && j > i)) && overlaps(o, box))
                covers.push(o);
        }
        var length = side === "top" ? box.x1 - box.x0 : box.y1 - box.y0;
        var span = covers.length ? freeSpan(box, covers, side) : { s0: 0, s1: length };
        out.push({
            address: w.address, monitor: w.monitor, cls: w.cls,
            x: box.x0, y: box.y0, w: box.x1 - box.x0, h: box.y1 - box.y0,
            span: span, clipped: span.s1 - span.s0 < length,
            focused: w.z === 0, covered: span.s1 - span.s0 < b + thickness,
            maximized: w.maximized
        });
    }
    return out;
}

// The controls' outline in their box's own coordinates. Hyprland rounds a window
// as the superellipse |x|^p + |y|^p = r^p (decoration:rounding_power), its content
// on `rounding` and its border on rounding + border. The outer corners take the
// border's curve, as the window's far corners do; the two notches follow the
// content's corner exactly, filling the gap it leaves against the controls, so the
// window and its controls read as one shape.
//
// Worked in "rail" terms -- `a` across, out from the content edge; `s` along -- and
// turned for the top bar at the end.
// Hyprland antialiases the content's corner and the fill antialiases its own edge;
// meeting on the same curve, the two half-covered pixels let the wallpaper through
// as a hairline. So the fill runs this far under the content instead, on the
// straight edge too.
var UNDERLAP = 1;

function railOutline(boxW, boxH, rounding, b, p, steps, side) {
    var top = side === "top";
    var T = top ? boxH : boxW, L = top ? boxW : boxH;
    var R = Math.max(0, Math.min(rounding + b, T, L / 2));
    var rc = Math.max(0, R - b); // the content's corner radius
    var r = Math.max(0, rc - UNDERLAP); // the notch's, on the same centre
    var pts = [];
    function put(a, s) {
        pts.push(top ? { x: s, y: T - a } : { x: a, y: s });
    }
    function arc(ca, cs, radius, ss, from, to) {
        for (var i = 0; i <= steps; i++) {
            var t = (from + (to - from) * i / steps) * Math.PI / 2;
            put(ca + radius * Math.pow(Math.cos(t), 2 / p), cs + ss * radius * Math.pow(Math.sin(t), 2 / p));
        }
    }
    put(-rc, 0);
    arc(T - R, R, R, -1, 1, 0); // outer corner, start end
    arc(T - R, L - R, R, 1, 0, 1); // outer corner, far end
    put(-rc, L);
    arc(-rc, L - b - rc, r, 1, 1, 0); // the content's corner, far end
    arc(-rc, b + rc, r, -1, 0, 1); // the content's corner, start end
    return pts;
}

function sel(address) {
    return 'window = "address:' + address + '"';
}

// Single dispatcher expressions, for Hyprland.dispatch (which wraps its argument
// in `return hl.dispatch(...)`, so a statement cannot go through it).
function moveExpr(address, x, y) {
    return "hl.dsp.window.move({ x = " + Math.round(x) + ", y = " + Math.round(y) + ", " + sel(address) + " })";
}
function resizeExpr(address, w, h) {
    return "hl.dsp.window.resize({ x = " + Math.round(w) + ", y = " + Math.round(h) + ", " + sel(address) + " })";
}
// hl.dsp.focus warps the pointer to the window's centre, and a press on the bar
// then read the warp as a drag and threw the window. no_warps for this one
// dispatch, put back straight after; an expression, so it can go through dispatch.
function focusExpr(address) {
    return '(function() local o = hl.get_config("cursor.no_warps"); hl.config({ cursor = { no_warps = true } }); '
        + "hl.dispatch(hl.dsp.focus({ " + sel(address) + " })); "
        + "hl.config({ cursor = { no_warps = o } }); return hl.dsp.no_op() end)()";
}
function raiseExpr(address) {
    return 'hl.dsp.window.alter_zorder({ mode = "top", ' + sel(address) + " })";
}
function closeExpr(address) {
    return "hl.dsp.window.close({ " + sel(address) + " })";
}
function minimizeExpr(address) {
    return 'hl.dsp.window.move({ workspace = "' + MINIMIZED + '", follow = false, ' + sel(address) + " })";
}
function barTagExpr(address) {
    return 'hl.dsp.window.tag({ tag = "+' + BAR_TAG + '", ' + sel(address) + " })";
}
// Remembers inside Hyprland that windows of this class get a bar, so the next one is
// tagged as it opens -- its bar is there on its first frame, not a probe later.
function barClassExpr(cls) {
    if (!CLASS.test(cls))
        return null;
    return '(function() ii_fm_bar_classes = ii_fm_bar_classes or {}; ii_fm_bar_classes["' + cls + '"] = true; return hl.dsp.no_op() end)()';
}
function noAnimExpr(address, on) {
    return 'hl.dsp.window.set_prop({ prop = "no_anim", value = "' + (on ? 1 : 0) + '", ' + sel(address) + " })";
}

// The evals that drive floatingMode.lua, the half inside Hyprland. `path` is that
// file; it is loaded afresh by each install, so an edit to it lands with the next toggle.
function luaString(str) {
    return "[==[" + String(str).replace(/\]==\]/g, "") + "]==]";
}

// Starts the mode in Hyprland: hooks, rules, KWin's focus, the watcher. Again after a
// reload, whose fresh Lua state has none of it.
function installExpr(path, o) {
    var classes = (o.barClasses || []).filter(function (c) { return CLASS.test(c); }).map(function (c) { return '"' + c + '"'; });
    return "ii_fm_lib = dofile(" + luaString(path) + "); ii_fm_lib.install({ bar_classes = { " + classes.join(", ")
        + ' }, side = "' + (o.side === "right" ? "right" : "top") + '", size = ' + Math.round(o.size) + ', event = "' + EVENT
        + '", tick = ' + TICK_MS + " })";
}

// Floats every tiled window; `railed` are the ones that get controls.
function floatAllExpr(railed) {
    var keys = railed.filter(function (a) { return ADDRESS.test(a); }).map(function (a) { return '["' + a + '"] = true'; });
    return "if ii_fm_lib then ii_fm_lib.float_all({ " + keys.join(", ") + " }) end";
}

function disableExpr() {
    return BARS_OFF_LUA + "; if ii_fm_lib then ii_fm_lib.disable() end";
}

// A drag on the shell's own rail, before it moves the window: a maximized window comes out
// of it under the pointer first, as KWin's do.
function beforeDragExpr(address) {
    if (!ADDRESS.test(address))
        return null;
    return 'if ii_fm_lib then ii_fm_lib.before_drag("' + address + '") end';
}

// A minimized window picked in the dock or Alt+Tab. Asked of the Lua rather than left to
// an activation, which opens the hidden workspace, every minimized window on it, first.
function activateExpr(address) {
    if (!ADDRESS.test(address))
        return null;
    return 'if ii_fm_lib then ii_fm_lib.activate("' + address + '") end';
}

// Hyprland's maximize toggle, which floatingMode.lua turns into its own.
function maximizeExpr(address) {
    return 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", ' + sel(address) + " })";
}

// hyprbars' side, for `hyprctl eval` once the plugin is loaded, and again after every
// reload (which clears its buttons and resets its options). The bar is Android 16's
// desktop caption, sized by FloatingMode.qml (railWidth, buttonSize, buttonGap):
// minimize, maximize, close. `bar_precedence_over_border` puts the border around bar and window
// together, so the two are one shape. A window has no bar unless the shell tags it
// (no controls of its own) and it floats. Both rules only ever say "no bar": an "off
// for all" rule and an "on for tagged" one settled differently when a window opened
// than when its tag changed later, and a window tagged as it opened never got a bar. In Lua a button's fg_color is
// required -- without it add_button fails and adds nothing -- and it is fixed once
// added: a theme change reaches the buttons with the reload that rewriting
// hyprland/colors.lua sets off, which clears them for this to add again.
function barsLua(o) {
    function q(str) {
        return "[[" + str.replace(/\]\]/g, "") + "]]";
    }
    var close = "hyprctl dispatch 'hl.dsp.window.close()'";
    var maximize = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })'";
    var minimize = "hyprctl dispatch 'hl.dsp.window.move({ workspace = \"" + MINIMIZED + "\", follow = false })'";
    return [
        "hl.config({ plugin = { hyprbars = { enabled = true, bar_height = " + o.height + ", bar_color = " + q(o.color) + ', ["col.text"] = ' + q(o.text)
            + ", bar_text_font = " + q(o.font) + ", bar_text_size = " + o.textSize + ', bar_text_align = "left", bar_padding = ' + o.padding
            + ", bar_button_padding = " + o.gap + ", bar_part_of_window = true, bar_precedence_over_border = true, on_double_click = " + q(maximize) + " } } })",
        "if not ii_fm_buttons then",
        // Right to left: close, maximize, minimize, each on a chip a layer up from the bar.
        // The patched plugin (scripts/hyprland/hyprbars.patch, known by its
        // close_hover_color) strokes the ii: icons itself, centred in the chip, as the apps
        // with their own buttons draw theirs, and fills close's hover with the error
        // container. Without it, plain Unicode: hyprbars sets text in "sans", so a Material
        // Symbols codepoint would come out as some other font's glyph.
        '    local ok, has = pcall(hl.get_config, "plugin.hyprbars.close_hover_color")',
        "    local icons = { \"\u{2715}\", \"\u{25A2}\", \"\u{2212}\" }",
        "    if ok and has ~= nil then",
        "        hl.config({ plugin = { hyprbars = { close_hover_color = " + q(o.closeHover) + " } } })",
        '        icons = { "ii:close", "ii:maximize", "ii:minimize" }',
        "    end",
        '    hl.plugin.hyprbars.add_button({ bg_color = ' + q(o.chip) + ', fg_color = ' + q(o.text) + ', size = ' + o.button + ', icon = icons[1], action = ' + q(close) + " })",
        '    hl.plugin.hyprbars.add_button({ bg_color = ' + q(o.chip) + ', fg_color = ' + q(o.text) + ', size = ' + o.button + ', icon = icons[2], action = ' + q(maximize) + " })",
        '    hl.plugin.hyprbars.add_button({ bg_color = ' + q(o.chip) + ', fg_color = ' + q(o.text) + ', size = ' + o.button + ', icon = icons[3], action = ' + q(minimize) + " })",
        "    ii_fm_buttons = true", // only once all three are in: a failed add retries next time
        "end",
        'if not ii_fm_bars_untagged then ii_fm_bars_untagged = hl.window_rule({ name = "ii-bars-untagged", match = { tag = "negative:' + BAR_TAG + '" }, ["hyprbars:no_bar"] = true }) end',
        'if not ii_fm_bars_tiled then ii_fm_bars_tiled = hl.window_rule({ name = "ii-bars-tiled", match = { float = false }, ["hyprbars:no_bar"] = true }) end'
    ].join("\n");
}

var BARS_OFF_LUA = "if hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { enabled = false } } }) end";

// Chromium and Electron map their .pak resources, Firefox and its forks libxul,
// and libadwaita apps always draw a header bar: all three put their own close,
// maximize and minimize in the window. Prints "pid 1" or "pid 0" per argument.
var OWN_CONTROLS_PATTERN = "(\\.pak|/libxul\\.so|/libadwaita-1\\.so[.0-9]*)$";
var OWN_CONTROLS_PROBE = 'for p in "$@"; do if grep -qE \'' + OWN_CONTROLS_PATTERN + '\' "/proc/$p/maps" 2>/dev/null; then echo "$p 1"; else echo "$p 0"; fi; done';
