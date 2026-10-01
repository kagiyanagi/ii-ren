#!/usr/bin/env python3
"""Shake to find the pointer fires on a shake and on nothing else.

cursorShake.lua runs inside Hyprland, sampling the pointer every 16ms tick, and a wrong
threshold only shows as a ring that never comes or one that pops up while dragging a
window. So the detector is fed synthetic paths under plain Lua: a back-and-forth shake
and a circle wiggle light it; a fast fling across the screen, a slow drag and a still
pointer do not, and a shake that has stopped stops reading as one. Then the ring is held `hold` ticks past
the shake, reports only ticks the pointer moved, and ends with exactly one "off".
"""
import pathlib
import subprocess

LUA_FILE = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/services/cursorShake.lua"

TEST = f"""
local M = dofile([[{LUA_FILE}]])
local function fires(path)
    local d, hit = M.detector(M.cfg), false
    for _, p in ipairs(path) do hit = d(p[1], p[2]) or hit end
    return hit
end
local function gen(n, f) local t = {{}} for i = 1, n do t[i] = {{ f(i) }} end return t end

-- 120px strokes every 3 ticks: a ~6Hz wiggle, about what a hand does.
assert(fires(gen(25, function(i) return 500 + (math.floor(i / 3) % 2 == 0 and 1 or -1) * ((i % 3) * 40), 400 end)), "back and forth")
assert(fires(gen(25, function(i) return 500 + 80 * math.cos(i * 0.9), 400 + 80 * math.sin(i * 0.9) end)), "circles")
assert(not fires(gen(25, function(i) return i * 70, i * 30 end)), "a fling across the screen")
assert(not fires(gen(25, function(i) return 500 + 4 * (i % 2), 400 end)), "a jittery still hand")
assert(not fires(gen(60, function(i) return 300 + i * 5, 300 end)), "a slow drag")
assert(not fires(gen(25, function() return 10, 10 end)), "still")
local shook = gen(25, function(i) return 500 + 80 * math.cos(i * 0.9), 400 + 80 * math.sin(i * 0.9) end)
for _ = 1, 5 do shook[#shook + 1] = {{ 500, 400 }} end
local d = M.detector(M.cfg)
local last
for _, p in ipairs(shook) do last = d(p[1], p[2]) end
assert(not last, "a shake that has stopped is not still shaking")

local s, out = {{ left = 0 }}, {{}}
out[#out + 1] = M.step(s, true, 1, 1)
out[#out + 1] = M.step(s, false, 1, 1) or "same"
out[#out + 1] = M.step(s, false, 2.6, 1)
for _ = 1, M.cfg.hold - 4 do assert(M.step(s, false, 2.6, 1) == nil) end
assert(out[1] == "1 1" and out[2] == "same" and out[3] == "3 1", table.concat(out, ","))
assert(M.step(s, false, 2.6, 1) == "off", "off once the hold runs out")
assert(M.step(s, false, 9, 9) == nil, "silent after off")
assert(M.step(s, true, 2.6, 1) == "3 1", "a new shake reports again, even at the old spot")
print("cursor shake ok")
"""

subprocess.run(["luac", "-p", str(LUA_FILE)], check=True)
subprocess.run(["lua", "-"], input=TEST, text=True, check=True)
