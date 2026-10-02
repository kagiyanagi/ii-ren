#!/usr/bin/env python3
""""Open in new workspace" (dock menu, launcher) lands the app on an empty workspace.

AppSearch.launchOnNewWorkspace builds a Lua chunk in a JS template string and hands it to
`hyprctl eval`. A broken template fails silently there: the app opens where you are. So the
JS runs here under node, and its Lua under plain Lua against a mock `hl`:

- The command is spawned with the `emptym silent` exec rule, which follows the spawned pid.
  Silent: the view and the focus stay on the workspace the user launched from.
- An app that hands the launch to a running instance (a browser, `kitty -1`) opens its
  window from that instance's pid, which the rule misses. The first window of the app's
  class (case-insensitive) that opens on the launch workspace is moved after it, once,
  also without following it.
- A window the rule already placed, or another app's, is left alone, and the catch stops
  listening after its timer.
"""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
QS = ROOT / "dots/.config/quickshell/ii"

JS = r"""
const src = require('fs').readFileSync(process.argv[1], 'utf8');
const body = src.slice(src.indexOf('function launchOnNewWorkspace'), src.indexOf('    function iconExists'));
const StringUtils = { shellSingleQuoteEscape: s => String(s).replace(/'/g, "'\\''") };
const Config = { options: { apps: { terminal: "kitty -1" } } };
let out; const Quickshell = { execDetached: a => out = a };
eval(body);
launchOnNewWorkspace({ command: ["fire'fox", "--new-window"], runInTerminal: false, startupClass: "", id: "Firefox" });
process.stdout.write(JSON.stringify(out));
"""

argv = json.loads(subprocess.run(["node", "-e", JS, str(QS / "services/AppSearch.qml")],
                                 check=True, capture_output=True, text=True).stdout)
assert argv[:2] == ["hyprctl", "eval"], argv

MOCK = r"""
local log, handler, removed, timer = {}, nil, 0, nil
hl = {
    get_active_workspace = function() return { id = 4 } end,
    dispatch = function(d) log[#log + 1] = d end,
    exec_cmd = nil,
    on = function(ev, fn) assert(ev == "window.open") handler = fn return { remove = function() removed = removed + 1 end } end,
    timer = function(fn, opts) assert(opts.type == "oneshot" and opts.timeout > 0) timer = fn end,
    dsp = {
        exec_cmd = function(cmd, rule) return { "exec", cmd, rule.workspace } end,
        window = { move = function(o) return { "move", o.window.class, o.workspace, o.follow } end },
    },
}
assert(load(io.read("a")))()

assert(#log == 1 and log[1][1] == "exec", "spawned once")
assert(log[1][2] == [['fire'\''fox' '--new-window']], "argv shell-quoted: " .. log[1][2])
assert(log[1][3] == "emptym silent", "exec rule targets an empty workspace, silently")

handler({ class = "firefox", workspace = { id = 5 } })
assert(#log == 1, "a window the rule placed is left alone")
handler({ class = "kitty", workspace = { id = 4 } })
assert(#log == 1, "another app's window is left alone")
handler({ class = nil, workspace = { id = 4 } })
assert(#log == 1, "a window with no class is left alone")
handler({ class = "firefox", workspace = { id = 4 } })
assert(#log == 2 and log[2][1] == "move" and log[2][3] == "emptym" and log[2][4] == false, "a handed-off window is moved, silently")
assert(removed == 1, "the catch stops after one window")
handler({ class = "firefox", workspace = { id = 4 } })
assert(#log == 2, "only the first one")
timer()
assert(removed == 1, "the timer does not remove twice")
print("ok")
"""

lua = subprocess.run(["lua", "-e", MOCK], input=argv[2], capture_output=True, text=True)
assert lua.returncode == 0 and lua.stdout.strip() == "ok", lua.stderr or lua.stdout

# The timer path on its own: no window ever comes, the subscription still goes.
lua = subprocess.run(["lua", "-e", MOCK.split("handler({ class")[0] + 'timer() assert(removed == 1, "timer stops it") print("ok")'],
                     input=argv[2], capture_output=True, text=True)
assert lua.returncode == 0 and lua.stdout.strip() == "ok", lua.stderr or lua.stdout

print("ok: new-workspace launch spawns silently on emptym, catches one handed-off window of its class, then stops")
