#!/usr/bin/env python3
"""Assert the media keys act on the player the shell shows, not on playerctld's pick.

The binds in keybinds.lua ran `playerctl`, which drives whichever player playerctld
last saw, while the bar and the media popup drive
MprisController.activePlayer. The two disagree whenever more than one player is open:
the key skipped a track in one player while the bar showed the other one. Nothing
looks wrong until the wrong player moves, so it is checked here.

- Every media bind calls the shell's `mpris` IpcHandler, with playerctl after `||`
  for when no shell is running (`qs ipc call` exits non-zero only then: a missing
  target or function still exits 0). keybinds.lua runs under plain Lua against a
  mock `hl`, so the commands are the concatenated strings Hyprland gets.
- Every function a bind calls exists in the IpcHandler.
- MprisController is loaded by shell.qml, not left to whatever panel first reads it:
  waffle reads it only once its action center opens, and until then the target does
  not exist and the keys did nothing, silently.
- The IPC next still runs a track that cannot skip (a lone browser video) to its end,
  as the playerctl fallback does; it runs here under node.

    python3 tools/check-media-keys.py
"""
import json
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
HYPR = ROOT / "dots/.config/hypr"
SHELL = ROOT / "dots/.config/quickshell/ii"
MPRIS = (SHELL / "services/MprisController.qml").read_text()

IPC = "qs -c $qsConfig ipc call mpris "
MEDIA = {
    # combo: (IPC function, locked)
    "XF86AudioNext": ("next", True),
    "XF86AudioPrev": ("previous", True),
    "XF86AudioPlay": ("playPause", True),
    "XF86AudioPause": ("playPause", True),
    "SUPER + SHIFT + N": ("next", True),
    "SUPER + SHIFT + B": ("previous", True),
    "SUPER + SHIFT + P": ("playPause", True),
    "SUPER + SHIFT + ALT + mouse:275": ("previous", False),
    "SUPER + SHIFT + ALT + mouse:276": ("next", False),
}

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
hl.dsp = setmetatable({ exec_cmd = function(cmd) return { cmd = cmd } end }, { __index = function() return stub() end })
hl.define_submap = function(_, body) body() end
hl.bind = function(combo, dispatcher, opts)
    if type(dispatcher) == "table" and type(rawget(dispatcher, "cmd")) == "string" then
        io.write(combo, "\31", dispatcher.cmd, "\31", tostring(opts and opts.locked or false), "\30")
    end
end
dofile(arg[1] .. "/hyprland/keybinds.lua")
"""


def block(src, start):
    """The brace-balanced `{...}` that opens at or after `start`, as (open, close+1)."""
    i = src.index("{", start)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return i, j + 1
    raise AssertionError("unbalanced braces in MprisController.qml")


with tempfile.NamedTemporaryFile("w", suffix=".lua") as mock:
    mock.write(MOCK)
    mock.flush()
    out = subprocess.run(["lua", mock.name, str(HYPR)], capture_output=True, text=True, check=True).stdout
binds = {}
for record in filter(None, out.split("\x1e")):
    combo, cmd, locked = record.split("\x1f")
    binds.setdefault(combo, []).append((cmd, locked == "true"))

handler = re.search(r'IpcHandler\s*\{\s*target:\s*"mpris"', MPRIS)
assert handler, 'MprisController no longer has the IpcHandler { target: "mpris" } the media keys call'
h_open, h_close = block(MPRIS, handler.start())
ipc_body = MPRIS[h_open:h_close]
ipc_functions = set(re.findall(r"\bfunction (\w+)\(", ipc_body))

for combo, (fn, locked) in MEDIA.items():
    assert combo in binds, f'"{combo}" is no longer bound to a command'
    for cmd, is_locked in binds[combo]:
        call = re.fullmatch(re.escape(IPC) + r"(\w+) \|\| (playerctl .+)", cmd, re.S)
        assert call, f'"{combo}" does not go through the shell first, with playerctl as the fallback: {cmd}'
        assert call.group(1) == fn, f'"{combo}" calls mpris {call.group(1)}, not {fn}'
        assert fn in ipc_functions, f'"{combo}" calls mpris {fn}, which the IpcHandler does not have'
        assert is_locked == locked, f'"{combo}" locked = {is_locked}; the media keys must work on the lock screen'
        if fn == "next":
            assert "playerctl position" in call.group(2), f'"{combo}" fallback no longer runs an unskippable track to its end'

for combo, entries in binds.items():
    for cmd, _ in entries:
        if "playerctl" in cmd:
            assert cmd.startswith(IPC), f'"{combo}" drives playerctl directly, past the shell\'s player: {cmd}'

assert re.search(r"\bfunction load\(\)", MPRIS), "MprisController has no load() to instantiate it at shell start"
assert re.search(r"^\s*onActiveFamilyChanged:.*\bMprisController\.load\(\)", (SHELL / "shell.qml").read_text(), re.M), \
    "shell.qml no longer loads MprisController, so in waffle the mpris target exists only after the action center opens"

# The IPC next under node: skip when the player can; otherwise seek to the end, in whole seconds.
n_start = re.search(r"\bfunction next\(\)\s*:\s*void\s*", ipc_body)
assert n_start, "the mpris IpcHandler has no next(): void"
n_open, n_close = block(ipc_body, n_start.end())
CASES = [
    # (canGoNext, player, want skipped, want position, why)
    (True, {"canSeek": True, "lengthSupported": True, "length": 200.5, "position": 10}, True, 10, "a player that can skip was seeked"),
    (False, {"canSeek": True, "lengthSupported": True, "length": 213.7, "position": 10}, False, 213, "an unskippable track was not run to its end"),
    (False, {"canSeek": False, "lengthSupported": True, "length": 213.7, "position": 10}, False, 10, "a player that cannot seek was seeked"),
    (False, {"canSeek": True, "lengthSupported": True, "length": 0, "position": 10}, False, 10, "a track of no length was sent back to 0"),
    (False, {"canSeek": True, "lengthSupported": False, "length": 10, "position": 10}, False, 10, "a player with no length was seeked"),
    (False, None, False, None, "no player at all"),
]
script = f"""
const cases = {json.dumps([[can, player] for can, player, *_ in CASES])};
console.log(JSON.stringify(cases.map(([canGoNext, player]) => {{
    let skipped = false;
    const root = {{ canGoNext, activePlayer: player, next: () => {{ skipped = true; }} }};
    (function () {ipc_body[n_open:n_close]})();
    return [skipped, player ? player.position : null];
}})));
"""
results = json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)
for (_, _, skipped, position, why), got in zip(CASES, results):
    assert got == [skipped, position], f"mpris next: {why} (skipped, position = {got})"

print(f"ok: {len(MEDIA)} media binds go through the shell's mpris IPC ({', '.join(sorted(ipc_functions))}), playerctl only as the fallback")
