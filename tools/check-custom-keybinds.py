#!/usr/bin/env python3
"""Assert Super+Shift+B in custom/keybinds.lua replaces the base bind on its key, not joins it.

Hyprland runs every bind on a key. custom/keybinds.lua bound Super+Shift+B to dictation
while hyprland/keybinds.lua kept it as previous track, so the key did both: dictation
started and the music skipped back. A custom bind on a base key has to `hl.unbind` it
first, which works only because hyprland.lua loads the custom file after the base one.
Nothing shows this but pressing the key with music playing, so it is checked here. Other
custom binds may share a base key on purpose: the keybind editor offers "run both".

Both files run under plain Lua against a stand-in `hl` that keeps the bind list the way
Hyprland does, and the list left at the end is what is asserted on:

- Super+Shift+B is dictation alone;
- previous track is still on XF86AudioPrev and the mouse bind.

    python3 tools/check-custom-keybinds.py
"""
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
HYPR = ROOT / "dots/.config/hypr"
CUSTOM = "custom/keybinds.lua"
FILES = ["hyprland/keybinds.lua", CUSTOM]

MOCK = r"""
package.path = arg[1] .. "/?.lua;" .. package.path
package.preload["hyprland.lib"] = function()
    HOME = "/nonexistent"
    is_file_exists = function() return false end
end
local function stub()
    return setmetatable({}, { __index = function() return stub() end, __call = function() return stub() end })
end
hl = stub()
hl.dsp = setmetatable({
    exec_cmd = function(cmd) return { what = "exec_cmd " .. cmd } end,
    global = function(name) return { what = "global " .. name } end,
}, { __index = function() return stub() end })

local binds, submap, source = {}, "", nil
-- Hyprland matches hl.unbind's key ignoring case and spaces (0.57, under --verify-config).
local function same(a, b) return a:gsub("%s", ""):upper() == b:gsub("%s", ""):upper() end
hl.define_submap = function(name, body) submap = name; body(); submap = "" end
hl.bind = function(key, dispatcher, opts)
    local what = type(dispatcher) == "table" and rawget(dispatcher, "what") or type(dispatcher)
    binds[#binds + 1] = { key = key, submap = submap, source = source, what = what,
        description = opts and opts.description or "" }
end
hl.unbind = function(key)
    for i = #binds, 1, -1 do
        if binds[i].submap == submap and same(binds[i].key, key) then table.remove(binds, i) end
    end
end

for i = 2, #arg do
    source = arg[i]
    dofile(arg[1] .. "/" .. arg[i])
end
for _, b in ipairs(binds) do
    io.write(b.submap, "\31", b.key, "\31", b.source, "\31", b.what, "\31", b.description, "\30")
end
"""

# UserKeybinds.qml's modifier bits, so two spellings of one combo count as one key.
MOD_BITS = {"SHIFT": 1, "CAPS": 2, "CAPSLOCK": 2, "CTRL": 4, "CONTROL": 4,
            "ALT": 8, "MOD1": 8, "MOD2": 16, "MOD3": 32,
            "SUPER": 64, "WIN": 64, "LOGO": 64, "MOD4": 64, "MOD5": 128}


def combo(key):
    modmask, name = 0, ""
    for part in filter(None, (p.strip() for p in key.split("+"))):
        if part.upper() in MOD_BITS:
            modmask |= MOD_BITS[part.upper()]
        else:
            name = part.lower()
    return modmask, name


main = (HYPR / "hyprland.lua").read_text()
base_at, custom_at = main.find('require("hyprland.keybinds")'), main.find('require("custom.keybinds")')
assert 0 <= base_at < custom_at, \
    "hyprland.lua no longer loads custom/keybinds.lua after hyprland/keybinds.lua, so its hl.unbind runs before the bind it removes"

with tempfile.NamedTemporaryFile("w", suffix=".lua") as mock:
    mock.write(MOCK)
    mock.flush()
    out = subprocess.run(["lua", mock.name, str(HYPR), *FILES], capture_output=True, text=True, check=True).stdout

by_key = {}
for record in filter(None, out.split("\x1e")):
    submap, key, source, what, description = record.split("\x1f")
    by_key.setdefault((submap, *combo(key)), []).append((key, source, what, description))

dictate = [(what, source) for _, source, what, _ in by_key.get(("", *combo("SUPER + SHIFT + B")), [])]
assert dictate == [("global quickshell:agentDictate", CUSTOM)], f"Super+Shift+B runs {dictate}, not dictation alone"

previous = {key for entries in by_key.values() for key, _, what, _ in entries if what.endswith("ipc call mpris previous || playerctl previous")}
for key in ["XF86AudioPrev", "SUPER + SHIFT + ALT + mouse:275"]:
    assert key in previous, f'"{key}" no longer plays the previous track; the custom file\'s unbind took more than Super+Shift+B'

print(f"ok: Super+Shift+B is dictation alone; previous track stays on {', '.join(sorted(previous))}")
