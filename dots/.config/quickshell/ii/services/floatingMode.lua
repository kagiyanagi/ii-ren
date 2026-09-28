-- Floating mode, Hyprland's half. services/FloatingMode.qml loads it into the compositor's
-- own Lua with dofile and calls install(), again after every config reload (a reload
-- starts a fresh Lua state). tools/check-floating-mode.py runs it under plain Lua against
-- a mock `hl`.
--
-- It is a desktop window manager's floating behaviour, read out of KWin's and Mutter's
-- sources rather than remembered:
--
--   focus      Click to focus. The active window is raised whatever activated it, and
--              keep-above (pinned) windows go back over it. Closing a window focuses the
--              next one down (kwin.kcfg: FocusPolicy ClickToFocus, NextFocusPrefersMouse
--              false).
--   placement  A new window is centred in the work area, cascaded by a 48th of the area
--              off any window it would cover completely, and kept inside the area (KWin
--              placement.cpp: placeCentered, cascadeIfCovering, Workspace::cascadeOffset,
--              keepInArea). Over 80% of the area, it opens maximized instead (Mutter
--              place.c, maybe_automaximize).
--   maximize   Fills the work area edge to edge, with no border and square corners (KWin
--              MaximizeArea; Breeze drops its outline and radius when maximized). Any number
--              of windows can be maximized, stacked like any other, and the app is told.
--              Restore returns to the size the window had, centred where it was (KWin
--              XdgToplevelWindow::maximize), capped at 80% of the area with its aspect kept
--              (Mutter meta_window_unmaximize, MAX_UNMAXIMIZED_WINDOW_AREA).
--   drag       A maximized window dragged by its title comes out at its restored size, with
--              the grab point at the same fraction of the window (KWin
--              setInteractiveMoveOffset, nextInteractiveMoveGeometry).
--
-- Hyprland's own maximize allows one window per workspace and hides the rest, so it goes
-- unused. Every path into it lands in the window.fullscreen hook below and becomes this
-- maximize: Super+D, the bar's button, an app's own button, an app that opens maximized.
-- Hyprland then sees a plain floating window, and the app sees itself maximized
-- (fullscreen_state internal 0, client 1).

local M = {}

M.MAX_AREA = 0.8 -- Mutter src/core/window-private.h, MAX_UNMAXIMIZED_WINDOW_AREA
M.INITIAL_SCALE = 0.75 -- AOSP DesktopModeUtils.kt, DESKTOP_MODE_INITIAL_BOUNDS_SCALE
M.CASCADE = 48 -- KWin Workspace::cascadeOffset: a 48th of the area
M.TAG, M.BAR_TAG, M.MINIMIZED = "iifloat", "iibar", "special:minimized"
M.cfg = M.cfg or { bar_classes = {}, side = "top", size = 40, event = "iiFloatingMode", tick = 16 }

-- address -> the box restore goes back to (false: none known), for every window the mode
-- has maximized. Survives a reinstall, not a reload: the watcher adopts what a reload left.
ii_fm_max = ii_fm_max or {}
-- address -> the box a window last had while neither maximized nor fullscreen.
ii_fm_normal = ii_fm_normal or {}
-- address -> the maximized box last given: a maximized window found elsewhere was moved
-- by someone else, but one still there with a new box wanted saw its work area change.
ii_fm_placed = ii_fm_placed or {}
-- address -> true while a window out of fullscreen waits to be maximized again.
ii_fm_back = ii_fm_back or {}

local function n(v) return math.floor(v + 0.5) end
local function near(a, b, d) return math.abs(a - b) <= (d or 2) end
local function clamp(v, lo, hi)
    if hi < lo then return lo end
    return math.max(lo, math.min(hi, v))
end
local function contains(a, b) return a.x0 <= b.x0 and a.y0 <= b.y0 and a.x1 >= b.x1 and a.y1 >= b.y1 end
local function intersects(a, b) return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1 end
local function same(a, b)
    return a ~= nil and b ~= nil and near(a.x, b.x) and near(a.y, b.y) and near(a.w, b.w) and near(a.h, b.h)
end

-- Boxes are a window's content, { x, y, w, h }, as Hyprland reports it: its border and its
-- controls are outside. `e` says how far those reach: { b = border, top, right }.

-- The work area: the monitor less what panels reserve. No gaps: a maximized window meets
-- the panels, as a desktop's does.
function M.work_area(m)
    local r, mw, mh = m.reserved, m.width / m.scale, m.height / m.scale
    if m.transform % 2 == 1 then mw, mh = mh, mw end
    return { x0 = m.x + r.left, y0 = m.y + r.top, x1 = m.x + mw - r.right, y1 = m.y + mh - r.bottom }
end

-- Where the content of a window that is not maximized may go: its border and its controls
-- stay inside the work area.
function M.room(area, e)
    return { x0 = area.x0 + e.b, y0 = area.y0 + e.top + e.b, x1 = area.x1 - e.right - e.b, y1 = area.y1 - e.b }
end

-- Maximized: the work area less the controls, and no border.
function M.max_box(area, e)
    return { x = area.x0, y = area.y0 + e.top, w = area.x1 - area.x0 - e.right, h = area.y1 - area.y0 - e.top }
end

function M.frame(box, e)
    return { x0 = box.x - e.b, y0 = box.y - e.b - e.top, x1 = box.x + box.w + e.b + e.right, y1 = box.y + box.h + e.b }
end

-- KWin's keepInArea: shrunk to the room if bigger than it, then slid inside.
function M.keep_in(box, room)
    local w, h = math.min(box.w, room.x1 - room.x0), math.min(box.h, room.y1 - room.y0)
    return { x = clamp(box.x, room.x0, room.x1 - w), y = clamp(box.y, room.y0, room.y1 - h), w = w, h = h }
end

-- Where restore puts a window. A window that was never anything but maximized gets AOSP's
-- default bounds, 75% of the room, centred.
function M.restore_box(saved, room)
    local rw, rh = room.x1 - room.x0, room.y1 - room.y0
    local w, h, cx, cy
    if saved then
        w, h, cx, cy = saved.w, saved.h, saved.x + saved.w / 2, saved.y + saved.h / 2
        if w * h > rw * rh * M.MAX_AREA then
            local s = math.sqrt(M.MAX_AREA)
            if w > h then
                w, h = rw * s, rw * s * h / w
            else
                w, h = rh * s * w / h, rh * s
            end
        end
    else
        w, h = rw * M.INITIAL_SCALE, rh * M.INITIAL_SCALE
        cx, cy = (room.x0 + room.x1) / 2, (room.y0 + room.y1) / 2
    end
    return M.keep_in({ x = n(cx - w / 2), y = n(cy - h / 2), w = n(w), h = n(h) }, room)
end

-- KWin's cascadeIfCovering, on frames. `others` runs from the top of the stack down. A
-- window already hidden under the ones above it does not count as covered.
function M.cascade(f, others, area)
    local dx, dy = (area.x1 - area.x0) / M.CASCADE, (area.y1 - area.y0) / M.CASCADE
    local p = f
    for _ = 1, #others + 1 do
        local moved, covered = false, nil
        for _, o in ipairs(others) do
            if intersects(o, p) then
                if contains(p, o) and not (covered and contains(covered, o)) then
                    -- On whole pixels, where the windows it placed before sit.
                    local w, h = p.x1 - p.x0, p.y1 - p.y0
                    p = { x0 = n(o.x0 + dx), y0 = n(o.y0 + dy), x1 = n(o.x0 + dx) + w, y1 = n(o.y0 + dy) + h }
                    if p.x1 > area.x1 or p.y1 > area.y1 then return f end
                    moved = true
                    break
                end
                covered = covered and { x0 = math.min(covered.x0, o.x0), y0 = math.min(covered.y0, o.y0),
                    x1 = math.max(covered.x1, o.x1), y1 = math.max(covered.y1, o.y1) } or o
                if contains(covered, area) then break end
            end
        end
        if not moved then return p end
    end
    return p
end

-- A window of `size` whose frame keeps the point `c` at the fraction of it that `c` had of
-- the frame `from`.
function M.grab_box(from, size, e, c)
    local fx, fy = (c.x - from.x0) / (from.x1 - from.x0), (c.y - from.y0) / (from.y1 - from.y0)
    local fw, fh = size.w + 2 * e.b + e.right, size.h + 2 * e.b + e.top
    return { x = n(c.x - fx * fw + e.b), y = n(c.y - fy * fh + e.b + e.top), w = size.w, h = size.h }
end

-- Everything below talks to Hyprland.

local function tagged(w, tag)
    local t = w.tags
    if type(t) == "string" then t = { t } end
    for _, x in ipairs(t or {}) do
        if x == tag or x == tag .. "*" then return true end
    end
    return false
end

local function box_of(w) return { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y } end
local function maximized(w) return w.fullscreen == 0 and w.fullscreen_client == 1 end

-- What a window's frame adds to its content. `bar` overrides the tag, which a window has
-- not got yet as it opens.
function M.edges(w, bar)
    local e = { b = maximized(w) and 0 or hl.get_config("general.border_size"), top = 0, right = 0 }
    if bar == nil then bar = tagged(w, M.BAR_TAG) end
    if bar then
        if M.cfg.side == "top" then e.top = M.cfg.size else e.right = M.cfg.size end
    end
    return e
end

function M.place(w, box)
    hl.dispatch(hl.dsp.window.resize({ x = n(box.w), y = n(box.h), window = w }))
    hl.dispatch(hl.dsp.window.move({ x = n(box.x), y = n(box.y), window = w }))
end

function M.maximize(w)
    local a = w.address
    if ii_fm_max[a] == nil then ii_fm_max[a] = ii_fm_normal[a] or false end
    hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 1, window = w }))
    -- fullscreen_state leaves a window whose two modes differ unsynced, and an unsynced
    -- window's own fullscreen request (F11, a video) would never reach Hyprland.
    hl.dispatch(hl.dsp.window.set_prop({ prop = "sync_fullscreen", value = "1", window = w }))
    local e = M.edges(w)
    e.b = 0
    local box = M.max_box(M.work_area(w.monitor), e)
    ii_fm_placed[a] = box
    M.place(w, box)
end

-- `box`: where it goes instead of its restore box (a drag's grab, a resize's new size).
function M.restore(w, box)
    local a = w.address
    local saved = ii_fm_max[a]
    ii_fm_max[a], ii_fm_placed[a] = nil, nil
    hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = w }))
    local e = M.edges(w)
    e.b = hl.get_config("general.border_size")
    M.place(w, box or M.restore_box(saved or nil, M.room(M.work_area(w.monitor), e)))
end

local function frame_of(w)
    return M.frame(box_of(w), M.edges(w))
end

local function visible(w)
    return w.mapped and not w.hidden and w.workspace ~= nil and w.workspace.visible and w.monitor ~= nil
end

-- Called before a drag reads the window's geometry: by the Super+drag bind, and by
-- hyprbars (scripts/hyprland/hyprbars.patch) as its title drag starts. `address` is the
-- dragged window, or nil for whichever is under the pointer.
function M.before_drag(address)
    local c = hl.get_cursor_pos()
    if not c then return end
    local ws, target = hl.get_windows({ mapped = true }), nil
    for i = #ws, 1, -1 do
        local w = ws[i]
        if visible(w) then
            if address then
                if w.address == address then target = w break end
            else
                local f = frame_of(w)
                if c.x >= f.x0 and c.x < f.x1 and c.y >= f.y0 and c.y < f.y1 then target = w break end
            end
        end
    end
    if not target or not target.floating or not maximized(target) then return end
    local e = M.edges(target)
    e.b = hl.get_config("general.border_size")
    local size = M.restore_box(ii_fm_max[target.address] or nil, M.room(M.work_area(target.monitor), e))
    M.restore(target, M.grab_box(frame_of(target), size, e, c))
end

-- A new window: auto-maximized, or kept inside the work area and, where Hyprland only
-- centred it, re-centred below the controls and cascaded. A window a rule or its parent
-- placed stays where it was put.
function M.place_new(w, bar)
    if not w.floating or w.fullscreen ~= 0 or not w.monitor or w.pinned then return end
    local area, e = M.work_area(w.monitor), M.edges(w, bar)
    local room, box = M.room(area, e), box_of(w)
    ii_fm_normal[w.address] = box
    if box.w * box.h > (room.x1 - room.x0) * (room.y1 - room.y0) * M.MAX_AREA then
        M.maximize(w)
        return
    end
    local slack = 2 + (e.top + e.right) / 2
    local centred = near(box.x + box.w / 2, (area.x0 + area.x1) / 2, slack) and near(box.y + box.h / 2, (area.y0 + area.y1) / 2, slack)
    local fit = M.keep_in(box, room)
    if centred then
        fit.x, fit.y = n(room.x0 + (room.x1 - room.x0 - fit.w) / 2), n(room.y0 + (room.y1 - room.y0 - fit.h) / 2)
        -- A pixel off Hyprland's own centring stays on it, so that windows opened the same
        -- way sit exactly on each other, which is what the cascade looks for.
        if same(fit, box) then fit = { x = box.x, y = box.y, w = box.w, h = box.h } end
        local others, ws = {}, hl.get_windows({ mapped = true })
        for i = #ws, 1, -1 do
            local o = ws[i]
            -- Its own workspace's windows, shown or not: it may open on one out of sight.
            if o.address ~= w.address and o.mapped and not o.hidden and o.workspace and w.workspace and o.workspace.id == w.workspace.id then
                others[#others + 1] = frame_of(o)
            end
        end
        local f = M.cascade(M.frame(fit, e), others, area)
        fit.x, fit.y = n(f.x0 + e.b), n(f.y0 + e.b + e.top)
    end
    if not same(fit, box) then
        M.place(w, fit)
        ii_fm_normal[w.address] = fit
    end
end

-- Once a tick, per floating window: what the app did to its own maximize, and whether a
-- maximized window still has its work area.
function M.reconcile(w)
    local a = w.address
    if ii_fm_back[a] then return end
    if w.fullscreen == 0 and w.fullscreen_client == 0 then
        if ii_fm_max[a] ~= nil then
            M.restore(w) -- its own restore button
        else
            ii_fm_normal[a] = box_of(w)
        end
        return
    end
    if not maximized(w) then return end
    if ii_fm_max[a] == nil then ii_fm_max[a] = false end
    local e = M.edges(w)
    local want, cur, last = M.max_box(M.work_area(w.monitor), e), box_of(w), ii_fm_placed[a]
    if same(cur, want) then
        ii_fm_placed[a] = want
    elseif last and not same(cur, last) then
        -- Moved or resized by something else, which takes it out of maximize (KWin). A move
        -- (a gesture, a drag that started elsewhere) brings it out at its restored size
        -- under the pointer, or under the middle of its top edge if the pointer is not on it.
        if near(cur.w, last.w) and near(cur.h, last.h) then
            local c, f = hl.get_cursor_pos(), frame_of(w)
            if not c or c.x < f.x0 or c.x >= f.x1 or c.y < f.y0 or c.y >= f.y1 then c = { x = (f.x0 + f.x1) / 2, y = f.y0 } end
            local r = M.edges(w)
            r.b = hl.get_config("general.border_size")
            local size = M.restore_box(ii_fm_max[a] or nil, M.room(M.work_area(w.monitor), r))
            M.restore(w, M.grab_box(f, size, r, c))
        else
            M.restore(w, cur)
        end
    else
        ii_fm_placed[a] = want
        M.place(w, want)
    end
end

function M.forget(a)
    ii_fm_max[a], ii_fm_normal[a], ii_fm_placed[a], ii_fm_back[a] = nil, nil, nil, nil
end

function M.install(cfg)
    M.cfg = cfg
    if ii_fm then ii_fm.stop() end
    local fm = { subs = {} }
    ii_fm = fm
    ii_fm_bar_classes = {}
    for _, c in ipairs(cfg.bar_classes or {}) do ii_fm_bar_classes[c] = true end

    -- One of each, kept across toggles.
    if not ii_fm_rule then ii_fm_rule = hl.window_rule({ name = "ii-floating-mode", match = { class = ".*" }, float = true }) end
    if not ii_fm_max_rule then
        ii_fm_max_rule = hl.window_rule({ name = "ii-floating-maximized",
            match = { float = true, fullscreen_state_internal = 0, fullscreen_state_client = 1 }, rounding = 0, border_size = 0 })
    end
    ii_fm_rule:set_enabled(true)
    ii_fm_max_rule:set_enabled(true)

    local function on(event, fn) fm.subs[#fm.subs + 1] = hl.on(event, fn) end

    -- What opens now floats because of the mode, so turning it off tiles it again.
    on("window.open", function(w)
        hl.dispatch(hl.dsp.window.tag({ tag = "+" .. M.TAG, window = w }))
        local bar = ii_fm_bar_classes[w.class] == true
        if bar then hl.dispatch(hl.dsp.window.tag({ tag = "+" .. M.BAR_TAG, window = w })) end
        M.place_new(w, bar)
    end)
    on("window.close", function(w) if w then M.forget(w.address) end end)

    -- A minimized window is parked on a hidden special workspace; focusing it from the dock
    -- or Alt+Tab brings it back to the workspace in front. KWin's stacking: the active
    -- window is on top, whatever activated it. Hyprland's own focus raises nothing.
    on("window.active", function(w)
        if not w then return end
        if w.workspace and w.workspace.name == M.MINIMIZED then
            hl.dispatch(hl.dsp.window.move({ workspace = hl.get_active_workspace().id, window = w }))
        end
        if not w.floating then return end
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = w }))
        for _, p in ipairs(hl.get_windows({ mapped = true })) do
            if p.pinned and p.address ~= w.address then hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = p })) end
        end
    end)

    on("window.fullscreen", function(w)
        if not w or not w.floating or w.pinned then return end
        if w.fullscreen == 1 then
            -- Hyprland maximized it. Again on a window already maximized: a toggle, so restore.
            if ii_fm_max[w.address] ~= nil then M.restore(w) else M.maximize(w) end
        elseif w.fullscreen == 0 and w.fullscreen_client == 0 and ii_fm_max[w.address] ~= nil and not ii_fm_back[w.address] then
            -- Out of fullscreen, back to the maximize it went fullscreen from: once Hyprland
            -- is done leaving fullscreen, which recentres the window after this hook runs.
            local a = w.address
            ii_fm_back[a] = true
            hl.timer(function()
                ii_fm_back[a] = nil
                for _, v in ipairs(hl.get_windows({ mapped = true })) do
                    if v.address == a and v.fullscreen == 0 and ii_fm_max[a] ~= nil then M.maximize(v) end
                end
            end, { timeout = 1, type = "oneshot" })
        end
    end)

    -- KWin's focus, from kwin.kcfg's defaults. Click to focus (FocusPolicy ClickToFocus, no
    -- AutoRaise), though the window under the pointer still takes the scroll, as in KWin.
    -- A closed window hands focus to the one below it (NextFocusPrefersMouse false:
    -- stacking order, not the pointer). Focus stealing prevention is low, so a window that
    -- asks to be activated is. Edges snap within 10px of the screen and of other windows
    -- (BorderSnapZone, WindowSnapZone). Tiling keeps its own: the user's values come back
    -- when the mode goes, and a reload restores them before this runs again.
    if not ii_fm_saved then
        ii_fm_saved = {
            input = { follow_mouse = hl.get_config("input.follow_mouse"), focus_on_close = hl.get_config("input.focus_on_close"),
                float_switch_override_focus = hl.get_config("input.float_switch_override_focus") },
            misc = { focus_on_activate = hl.get_config("misc.focus_on_activate") },
            general = { snap = { enabled = hl.get_config("general.snap.enabled"), window_gap = hl.get_config("general.snap.window_gap"),
                monitor_gap = hl.get_config("general.snap.monitor_gap") } },
        }
    end
    hl.config({ input = { follow_mouse = 2, focus_on_close = 2, float_switch_override_focus = 0 }, misc = { focus_on_activate = true },
        general = { snap = { enabled = true, window_gap = 10, monitor_gap = 10 } } })

    -- Hyprland emits nothing when a window moves, so a timer walks the windows every frame
    -- and reports to the shell only when something changed: an idle desktop costs a Lua
    -- walk per tick and no IPC.
    -- "B border rounding power;M monitor x0 y0 x1 y1;W address x y w h z fs floating max monitor pid class"
    local last = ""
    fm.timer = hl.timer(function()
        local out = { string.format("B %d %d %s", hl.get_config("general.border_size"), hl.get_config("decoration.rounding"),
            hl.get_config("decoration.rounding_power")) }
        for _, m in ipairs(hl.get_monitors()) do
            local a = M.work_area(m)
            out[#out + 1] = string.format("M %s %d %d %d %d", m.name, n(a.x0), n(a.y0), n(a.x1), n(a.y1))
        end
        for _, w in ipairs(hl.get_windows({ mapped = true })) do
            if w.floating and not w.pinned and w.monitor then M.reconcile(w) end
            if visible(w) then
                out[#out + 1] = string.format("W %s %d %d %d %d %d %d %d %d %s %d %s", w.address, n(w.at.x), n(w.at.y), n(w.size.x),
                    n(w.size.y), w.focus_history_id, w.fullscreen, w.floating and 1 or 0, maximized(w) and 1 or 0, w.monitor.name,
                    w.pid, (w.class:gsub("[;%s]", "")))
            end
        end
        local s = table.concat(out, ";")
        if s ~= last then
            last = s
            hl.dispatch(hl.dsp.event(M.cfg.event .. ">>" .. s))
        end
    end, { timeout = M.cfg.tick, type = "repeat" })

    function fm.stop()
        fm.timer:set_enabled(false)
        ii_fm_rule:set_enabled(false)
        ii_fm_max_rule:set_enabled(false)
        for _, s in ipairs(fm.subs) do s:remove() end
        ii_fm = nil
    end
end

-- Floats every tiled window where it already is, read for all of them before any floats:
-- floating one re-tiles the rest, and reading as it goes would keep the size a neighbour
-- grew into. A window that gets controls gives up that much of its tile to them. One whose
-- tile is most of the screen is maximized instead (Mutter's auto-maximize): floated at
-- its tile's size, it would look no different maximized or not.
function M.float_all(railed)
    local todo = {}
    for _, w in ipairs(hl.get_windows({ floating = false })) do
        if w.mapped and w.fullscreen == 0 and w.monitor then todo[#todo + 1] = { w = w, box = box_of(w) } end
    end
    for _, t in ipairs(todo) do
        local w, box = t.w, t.box
        hl.dispatch(hl.dsp.window.float({ action = "set", window = w }))
        hl.dispatch(hl.dsp.window.tag({ tag = "+" .. M.TAG, window = w }))
        local e = M.edges(w, railed[w.address] == true)
        local room = M.room(M.work_area(w.monitor), e)
        if box.w * box.h > (room.x1 - room.x0) * (room.y1 - room.y0) * M.MAX_AREA then
            ii_fm_normal[w.address] = nil
            M.maximize(w)
        else
            M.place(w, { x = box.x, y = box.y + e.top, w = box.w - e.right, h = box.h - e.top })
        end
    end
end

-- Undoes the mode. Maximized windows are told they are not; the ones that float on their
-- own go back to their size. Minimized windows come back, then everything the mode
-- floated is tiled again.
function M.disable()
    if ii_fm then ii_fm.stop() end
    if ii_fm_saved then
        hl.config(ii_fm_saved)
        ii_fm_saved = nil
    end
    for _, w in ipairs(hl.get_windows()) do
        if ii_fm_max[w.address] ~= nil and maximized(w) then
            if tagged(w, M.TAG) then
                hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = w }))
            else
                M.restore(w)
            end
        end
    end
    ii_fm_max, ii_fm_normal, ii_fm_placed, ii_fm_back = {}, {}, {}, {}
    local active = hl.get_active_workspace()
    for _, w in ipairs(hl.get_windows()) do
        if w.workspace and w.workspace.name == M.MINIMIZED then
            hl.dispatch(hl.dsp.window.move({ workspace = active.id, follow = false, window = w }))
        end
    end
    for _, w in ipairs(hl.get_windows({ tag = M.TAG })) do
        hl.dispatch(hl.dsp.window.tag({ tag = "-" .. M.TAG, window = w }))
        hl.dispatch(hl.dsp.window.float({ action = "unset", window = w }))
    end
    for _, w in ipairs(hl.get_windows({ tag = M.BAR_TAG })) do hl.dispatch(hl.dsp.window.tag({ tag = "-" .. M.BAR_TAG, window = w })) end
end

return M
