#!/usr/bin/env python3
"""
MCP server: full desktop control for the agent running inside Conduit.

Speed is the whole point, so the design is about round trips, not about the
speed of any one action:

  - Three tools, not thirty. Every extra tool is schema the model re-reads on
    every turn.
  - `desktop_do` takes a LIST of actions. Focus a window, type, hit enter is one
    call, not three - and a round trip to a big model costs seconds while the
    action itself costs milliseconds.
  - `desktop_state` answers "what is on screen" in one shot, from Hyprland's IPC
    socket directly. No hyprctl process per question.
  - `desktop_look` hands the image back inline, so seeing the screen is one call
    instead of grim-to-a-file plus a Read.

Stdlib only, on purpose: no venv to resolve, no package to import, the process
is alive in about 20 ms. Talks JSON-RPC over stdio, the MCP stdio transport.
"""

import base64
import glob
import json
import os
import socket
import subprocess
import sys

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")


def hypr_socket_path():
    """The signature is normally inherited; when it is not, there is usually
    exactly one instance running and guessing it beats failing."""
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if his:
        return f"{RUNTIME}/hypr/{his}/.socket.sock"
    found = sorted(glob.glob(f"{RUNTIME}/hypr/*/.socket.sock"))
    return found[-1] if found else None


def hypr(cmd: str) -> str:
    """One request on Hyprland's control socket - the wire protocol hyprctl uses."""
    path = hypr_socket_path()
    if not path:
        raise RuntimeError("Hyprland socket not found")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(path)
        s.sendall(cmd.encode())
        chunks = []
        while True:
            b = s.recv(65536)
            if not b:
                break
            chunks.append(b)
    return b"".join(chunks).decode(errors="replace")


def hypr_json(what: str):
    return json.loads(hypr("j/" + what) or "null")


def run(argv, inp=None, timeout=30):
    p = subprocess.run(argv, input=inp, capture_output=True, text=True, timeout=timeout)
    return (p.stdout + p.stderr).strip()


# ---------------------------------------------------------------- tools


def desktop_state(clients=True):
    aw = hypr_json("activewindow") or {}
    keys = ("address", "class", "title", "workspace", "at", "size", "pid", "floating")
    out = {
        "focused": {k: aw.get(k) for k in keys} if aw else None,
        "cursor": hypr_json("cursorpos"),
        "monitors": [
            {"name": m["name"], "res": f'{m["width"]}x{m["height"]}', "scale": m["scale"],
             "at": [m["x"], m["y"]], "workspace": m["activeWorkspace"]["name"], "focused": m["focused"]}
            for m in (hypr_json("monitors") or [])
        ],
        "workspaces": [
            {"id": w["id"], "name": w["name"], "monitor": w["monitor"], "windows": w["windows"]}
            for w in (hypr_json("workspaces") or [])
        ],
    }
    if clients:
        out["clients"] = [
            {"address": c["address"], "class": c["class"], "title": c["title"],
             "workspace": c["workspace"]["name"], "at": c["at"], "size": c["size"],
             "floating": c["floating"], "pid": c["pid"]}
            for c in (hypr_json("clients") or []) if c.get("mapped") and not c.get("hidden")
        ]
    return out


def geometry_for(target):
    """A grim -g string for a window address, or an output name for grim -o."""
    if target in (None, "", "screen"):
        return None, None
    if target == "active":
        c = hypr_json("activewindow") or None
    elif target.startswith("0x"):
        c = next((c for c in hypr_json("clients") or [] if c["address"] == target), None)
        if not c:
            raise RuntimeError(f"No window with address {target}")
    else:
        return None, target  # a monitor name
    if not c:
        raise RuntimeError("No focused window")
    x, y = c["at"]
    w, h = c["size"]
    return f"{x},{y} {w}x{h}", None


def desktop_look(target="screen", scale=0.5):
    geom, output = geometry_for(target)
    argv = ["grim", "-t", "png", "-s", str(scale)]
    if geom:
        argv += ["-g", geom]
    if output:
        argv += ["-o", output]
    argv.append("-")
    p = subprocess.run(argv, capture_output=True, timeout=20)
    if p.returncode != 0 or not p.stdout:
        raise RuntimeError("grim failed: " + p.stderr.decode(errors="replace").strip())
    return base64.b64encode(p.stdout).decode()


def desktop_entries():
    """Every installed app, parsed once per process: (stem, Name, Exec)."""
    if desktop_entries.cache is not None:
        return desktop_entries.cache
    dirs = [os.path.expanduser("~/.local/share/applications"), "/usr/share/applications",
            "/var/lib/flatpak/exports/share/applications",
            os.path.expanduser("~/.local/share/flatpak/exports/share/applications")]
    apps, seen = [], set()
    for d in dirs:
        for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            stem = os.path.basename(path)[:-8]
            if stem in seen:
                continue
            seen.add(stem)
            name = exec_ = ""
            hidden = False
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    in_entry = False
                    for line in f:
                        line = line.strip()
                        if line.startswith("["):
                            if in_entry:
                                break  # only the first [Desktop Entry] group, not the actions
                            in_entry = line == "[Desktop Entry]"
                        elif in_entry and line.startswith("Name=") and not name:
                            name = line[5:]
                        elif in_entry and line.startswith("Exec=") and not exec_:
                            exec_ = line[5:]
                        elif in_entry and line.startswith(("NoDisplay=true", "Hidden=true")):
                            hidden = True
            except OSError:
                continue
            if exec_ and not hidden:
                # %f %U %i and friends are launcher placeholders, not arguments.
                exec_ = " ".join(w for w in exec_.split() if not (len(w) == 2 and w[0] == "%"))
                apps.append((stem, name, exec_))
    desktop_entries.cache = apps
    return apps


desktop_entries.cache = None


def find_app(query):
    """Best .desktop match, plus the runners-up in case it guessed wrong."""
    q = query.strip().lower()
    scored = []
    for stem, name, exec_ in desktop_entries():
        s, n = stem.lower(), name.lower()
        score = (100 if q in (s, n) else
                 80 if q in s.split(".") else  # "ayugram" in com.ayugram.desktop
                 60 if s.startswith(q) or n.startswith(q) else
                 40 if q in s or q in n else
                 20 if q in exec_.lower() else 0)
        if score:
            scored.append((score, stem, name, exec_))
    scored.sort(key=lambda t: (-t[0], len(t[1])))
    return scored


# wtype drives the keyboard (xkb keysym names, no daemon); ydotool drives the
# pointer, because wtype has none. Both talk Wayland directly.
BUTTONS = {"left": "0xC0", "right": "0xC1", "middle": "0xC2"}


def act(a):
    if not isinstance(a, dict) or not a:
        raise RuntimeError(f"Bad action: {a!r}")
    kind = a.get("do")
    if kind is None:  # {"type": "hi"} shorthand
        kind, val = next(iter(a.items()))
    else:
        val = a.get("value")

    if kind == "hypr":
        return hypr("/" + str(val).lstrip("/"))
    if kind == "type":
        return run(["wtype", "-s", str(a.get("delay", 4)), "--", str(val)])
    if kind == "key":
        # "ctrl+shift+t" -> -M ctrl -M shift -k t -m shift -m ctrl
        parts = [p.strip() for p in str(val).split("+") if p.strip()]
        mods, key = parts[:-1], parts[-1]
        argv = ["wtype"]
        for m in mods:
            argv += ["-M", m]
        argv += ["-k", key]
        for m in reversed(mods):
            argv += ["-m", m]
        return run(argv)
    if kind == "move":
        return run(["ydotool", "mousemove", "--absolute", "-x", str(val[0]), "-y", str(val[1])])
    if kind == "click":
        return run(["ydotool", "click", BUTTONS.get(str(val or "left"), BUTTONS["left"])])
    if kind == "scroll":
        return run(["ydotool", "mousemove", "-w", "-x", "0", "-y", str(val)])
    if kind == "app":
        hits = find_app(str(val))
        if not hits:
            raise RuntimeError(f'No installed app matches {val!r}. Use {{"apps": "part of the name"}} to search.')
        _, stem, name, exec_ = hits[0]
        ws = a.get("workspace")
        rule = f"[workspace {ws} silent] " if ws not in (None, "") else ""
        out = hypr(f"/dispatch exec {rule}{exec_}")
        alts = [s for _, s, _, _ in hits[1:4]]
        return f"Launched {name or stem} ({exec_}){' on workspace ' + str(ws) if rule else ''}: {out}" \
               + (f" | other matches: {', '.join(alts)}" if alts else "")
    if kind == "apps":
        return json.dumps([{"id": s, "name": n} for _, s, n, _ in find_app(str(val))[:20]])
    if kind == "shell":
        # "sidebarLeft.toggle" / "dropShelf.add /path/x.png", and "show" lists them all.
        s = str(val).strip()
        if s in ("show", "list", ""):
            return run(["qs", "-c", "ii", "ipc", "show"])
        head, _, rest = s.partition(" ")
        target, _, fn = head.partition(".")
        return run(["qs", "-c", "ii", "ipc", "call", target, fn] + rest.split())
    if kind == "clip":
        return run(["wl-paste", "-n"]) if val in (None, "", True) else run(["wl-copy"], inp=str(val))
    if kind == "sh":
        return run(["bash", "-lc", str(val)], timeout=a.get("timeout", 60))
    if kind == "sleep":
        import time
        time.sleep(min(float(val), 10000) / 1000.0)
        return ""
    raise RuntimeError(f"Unknown action {kind!r}")


def desktop_do(actions):
    out = []
    for i, a in enumerate(actions):
        try:
            out.append({"i": i, "ok": True, "out": act(a)})
        except Exception as e:
            out.append({"i": i, "ok": False, "error": str(e)})
            break  # after a failed step every later step is acting on a screen it did not expect
    return out


TOOLS = [
    {
        "name": "desktop_state",
        "description": "Everything on the Hyprland desktop right now: focused window, every window with its address, position and size, workspaces, monitors, cursor. Call this first - the window addresses it returns are what desktop_do and desktop_look take.",
        "inputSchema": {"type": "object", "properties": {
            "clients": {"type": "boolean", "description": "Include the full window list (default true)"}}},
    },
    {
        "name": "desktop_look",
        "description": "Screenshot, returned inline as an image. target: 'screen' (all outputs), 'active' (focused window), a window address like 0x55f..., or a monitor name like DP-1. scale shrinks it - 0.5 default, lower for a glance, 1.0 to read small text.",
        "inputSchema": {"type": "object", "properties": {
            "target": {"type": "string"},
            "scale": {"type": "number"}}},
    },
    {
        "name": "desktop_do",
        "description": (
            "Run a SEQUENCE of desktop actions in one call. Batch aggressively - focus, type "
            "and press enter belong in one call, not three. Stops at the first failure. Actions:\n"
            '  {"app": "ayugram", "workspace": 8}  launch an app by name on an optional workspace. '
            'Resolves .desktop entries itself - never go hunting with which/flatpak/ls, this is the one call.\n'
            '  {"apps": "gram"}        search installed apps when a name does not resolve\n'
            '  {"hypr": "dispatch focuswindow address:0x55f.."}  any Hyprland command, hyprctl syntax\n'
            '  {"type": "hello"}       type text into the focused window\n'
            '  {"key": "ctrl+shift+t"} keysym with optional modifiers (Return, Escape, super, alt, Tab...)\n'
            '  {"move": [960, 540]}    move the pointer, absolute pixels\n'
            '  {"click": "left"}       left|right|middle\n'
            '  {"scroll": -5}          wheel, negative is up\n'
            '  {"clip": true}          read the clipboard;  {"clip": "text"} writes it\n'
            '  {"shell": "sidebarLeft.toggle"}  drive the ii shell itself - bar, sidebars, lock, '
            'osd, media controls, cheatsheet, dropShelf, search. {"shell": "show"} lists every target.\n'
            '  {"sh": "cmd"}           shell command, output returned\n'
            '  {"sleep": 200}          milliseconds, to let a window appear\n'
            "You have full control of this machine. Anything above is direct; anything else is a "
            "{\"sh\"} away - wpctl (audio), brightnessctl, playerctl, notify-send, cliphist, "
            "hyprpicker, nmcli, bluetoothctl, systemctl --user."
        ),
        "inputSchema": {"type": "object", "properties": {
            "actions": {"type": "array", "items": {"type": "object"}}}, "required": ["actions"]},
    },
]


def call(name, args):
    if name == "desktop_state":
        return [{"type": "text", "text": json.dumps(desktop_state(args.get("clients", True)))}]
    if name == "desktop_look":
        data = desktop_look(args.get("target", "screen"), args.get("scale", 0.5))
        return [{"type": "image", "data": data, "mimeType": "image/png"}]
    if name == "desktop_do":
        return [{"type": "text", "text": json.dumps(desktop_do(args.get("actions") or []))}]
    raise RuntimeError(f"Unknown tool {name!r}")


def handle(req):
    """One JSON-RPC request -> one response dict, or None for a notification."""
    method, rid = req.get("method"), req.get("id")
    if rid is None:
        return None
    try:
        if method == "initialize":
            result = {
                "protocolVersion": req.get("params", {}).get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "desktop", "version": "1.0.0"},
            }
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            p = req.get("params", {})
            result = {"content": call(p.get("name"), p.get("arguments") or {})}
        elif method == "ping":
            result = {}
        elif method == "resources/list":
            result = {"resources": []}
        elif method == "prompts/list":
            result = {"prompts": []}
        else:
            return {"jsonrpc": "2.0", "id": rid,
                    "error": {"code": -32601, "message": f"Unknown method {method}"}}
        return {"jsonrpc": "2.0", "id": rid, "result": result}
    except Exception as e:
        # An error the model can read and retry from, not a dead transport.
        return {"jsonrpc": "2.0", "id": rid,
                "result": {"content": [{"type": "text", "text": f"Error: {e}"}], "isError": True}}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            continue
        resp = handle(req)
        if resp is not None:
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()


def selftest():
    assert handle({"jsonrpc": "2.0", "method": "notifications/initialized"}) is None
    assert handle({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})["result"]["serverInfo"]["name"] == "desktop"
    assert len(handle({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})["result"]["tools"]) == 3
    assert handle({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                   "params": {"name": "nope", "arguments": {}}})["result"]["isError"]
    # A failed step stops the batch instead of typing into whatever came next.
    r = desktop_do([{"bogus": 1}, {"type": "SHOULD NOT BE TYPED"}])
    assert len(r) == 1 and not r[0]["ok"], r
    assert desktop_entries(), "no .desktop files found"
    assert find_app("firefox") or find_app("kitty"), "app lookup found nothing to launch"
    state = json.loads(handle({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
                               "params": {"name": "desktop_state", "arguments": {}}})["result"]["content"][0]["text"])
    assert state["monitors"], "no monitors - is Hyprland reachable?"
    print(f"ok - {len(state.get('clients', []))} windows, focused:", (state["focused"] or {}).get("class"))


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else main()
