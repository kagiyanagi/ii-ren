-- Shake to find the pointer, the half inside Hyprland. Hyprland emits nothing when the
-- pointer moves, so a timer samples it every frame and tells the shell (modules/ii/
-- cursorRadar) only while a shake is live: "x y" each tick the pointer moves, then
-- "off". An idle pointer costs a short Lua loop per tick and no IPC at all.
local M = {}

-- A shake is a lot of travel that goes nowhere: over the last `samples` ticks the path
-- is more than `ratio` times the diagonal of the box it stayed in, and that box is at
-- least `diagonal` across. KWin's Shake Cursor numbers (shakedetector.h,
-- shakecursorconfig.kcfg: a 1000ms window, sensitivity 4, the 100px floor), the tuning
-- Plasma ships. Each back-and-forth stroke adds ~1, each lap of a circle ~2.2, a fling stays at ~1.
-- Calibration knobs, in logical px and 16ms ticks.
M.cfg = { tick = 16, samples = 62, ratio = 4, diagonal = 100, hold = 60, event = "iiCursorShake" }

-- Fed one position per tick; true while the window of samples reads as a shake.
function M.detector(cfg)
    local xs, ys = {}, {}
    return function(x, y)
        xs[#xs + 1], ys[#ys + 1] = x, y
        if #xs > cfg.samples then
            table.remove(xs, 1)
            table.remove(ys, 1)
        end
        -- The window remembers a shake for its whole length after the hand stops, and
        -- that is not shaking: only a pointer still moving (in the last 4 ticks) is.
        local n, still = #xs, true
        for i = math.max(2, n - 3), n do still = still and xs[i] == xs[i - 1] and ys[i] == ys[i - 1] end
        if still then return false end
        local path, x0, x1, y0, y1 = 0, x, x, y, y
        for i = 2, #xs do
            path = path + math.sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2)
            x0, x1, y0, y1 = math.min(x0, xs[i]), math.max(x1, xs[i]), math.min(y0, ys[i]), math.max(y1, ys[i])
        end
        local diagonal = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        return diagonal >= cfg.diagonal and path > cfg.ratio * diagonal
    end
end

-- Lit by a shake and held `hold` ticks past its end, so the ring outlasts the wiggle
-- long enough for the eye to land on it.
function M.step(state, shaking, x, y)
    if shaking then state.left = M.cfg.hold end
    if state.left <= 0 then return nil end
    state.left = state.left - 1
    if state.left == 0 then
        state.last = nil
        return "off"
    end
    local s = string.format("%d %d", math.floor(x + 0.5), math.floor(y + 0.5))
    if s == state.last then return nil end
    state.last = s
    return s
end

function M.stop()
    if ii_cs_timer then ii_cs_timer:set_enabled(false) end
    ii_cs_timer = nil
end

function M.install()
    M.stop()
    local shake, state = M.detector(M.cfg), { left = 0 }
    ii_cs_timer = hl.timer(function()
        local p = hl.get_cursor_pos()
        local out = M.step(state, shake(p.x, p.y), p.x, p.y)
        if out then hl.dispatch(hl.dsp.event(M.cfg.event .. ">>" .. out)) end
    end, { timeout = M.cfg.tick, type = "repeat" })
end

return M
