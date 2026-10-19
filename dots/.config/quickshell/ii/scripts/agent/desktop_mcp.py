#!/usr/bin/env python3
"""The sidebar agent's hands on the desktop, as an MCP stdio server.

Claude Code and Codex both start this themselves (bridge.py hands it to each as
an MCP server), so one set of tools works for either. It is a thin layer over
desktop.py -- window geometry, OCR word boxes and clicking, already measured
and guarded there -- plus a screenshot and the shell's own IPC.

  screenshot  the screen or one window, as an image the model can look at
  windows     every mapped window: class, title, workspace, geometry
  see         OCR'd words of one window with absolute screen coordinates
  click       press a labelled control (or x y) in a window, via ydotool
  ipc_show    every IPC target and function the running shell exposes
  ipc_call    call one of them (open a panel, change volume, switch theme...)

The first four that only look are pre-approved by the bridge; clicking and IPC
calls go through the agent's approval like any other action.

Standard library only. MCP over stdio: JSON-RPC 2.0, one message per line;
stdout carries protocol and nothing else.
"""
import base64
import contextlib
import io
import json
import os
import shlex
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import desktop  # noqa: E402

PROTOCOLS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
# The longest side a screenshot is sent at. Models see detail well below a 4K
# frame, and every pixel above this costs context for nothing.
MAX_SIDE = 1600

TARGET = {
    "class": {"type": "string", "description": "Window class to target (substring match)"},
    "title": {"type": "string", "description": "Window title to target (substring match)"},
    "focus": {"type": "boolean", "description": "Switch to the window's workspace first if it is not on screen"},
}

TOOLS = [
    {"name": "screenshot", "title": "Screenshot",
     "description": "Look at the screen. Without a target it captures the whole desktop; with class or title, one window.",
     "inputSchema": {"type": "object", "properties": TARGET},
     "annotations": {"readOnlyHint": True}},
    {"name": "windows", "title": "List windows",
     "description": "Every mapped window with its class, title, workspace, position and size, and which one is focused.",
     "inputSchema": {"type": "object", "properties": {}},
     "annotations": {"readOnlyHint": True}},
    {"name": "see", "title": "Read a window",
     "description": "OCR the words in one window, each with its absolute screen position. Cheaper and more exact than a screenshot when you need to find a label.",
     "inputSchema": {"type": "object", "properties": dict(TARGET, grep={"type": "string", "description": "Only words containing this text"})},
     "annotations": {"readOnlyHint": True}},
    {"name": "click", "title": "Click",
     "description": "Click the on-screen text `label` inside a window, or the absolute point x,y. Refuses an ambiguous label rather than guessing.",
     "inputSchema": {"type": "object", "properties": dict(TARGET, label={"type": "string"}, x={"type": "integer"}, y={"type": "integer"})}},
    {"name": "ipc_show", "title": "Shell IPC functions",
     "description": "List every IPC target and function the running desktop shell (Quickshell ii) exposes. Read this before ipc_call.",
     "inputSchema": {"type": "object", "properties": {}},
     "annotations": {"readOnlyHint": True}},
    {"name": "ipc_call", "title": "Call shell IPC",
     "description": "Call a desktop-shell IPC function, e.g. target=sidebarRight function=toggle, or target=audio function=setVolume args=[\"0.4\"].",
     "inputSchema": {"type": "object", "properties": {"target": {"type": "string"}, "function": {"type": "string"},
                                                      "args": {"type": "array", "items": {"type": "string"}}},
                     "required": ["target", "function"]}},
]


def _desktop(argv: list[str]) -> str:
    """desktop.py's CLI, in-process. Its refusals arrive as SystemExit(json)."""
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            desktop.main(["desktop.py", *argv])
    except SystemExit as e:
        if isinstance(e.code, str):
            return e.code
    return out.getvalue().strip()


def _target_args(args: dict) -> list[str]:
    out = []
    for key in ("class", "title"):
        if args.get(key):
            out += [f"--{key}", str(args[key])]
    if args.get("focus"):
        out.append("--focus")
    return out


def _screenshot(args: dict) -> list[dict]:
    geometry = ""
    if args.get("class") or args.get("title"):
        # desktop.py's own targeting, so an off-screen window is refused (or
        # focused) here exactly as it is for see and click.
        try:
            win = desktop._target_window({k: args.get(k) for k in ("class", "title", "focus")})
        except SystemExit as e:
            return [{"type": "text", "text": str(e.code)}]
        x, y, width, height = desktop._rect_of(win)
        geometry = f"{x},{y} {width}x{height}"
    else:
        rc, out, _ = desktop.sh(["hyprctl", "monitors", "-j"])
        monitors = json.loads(out) if rc == 0 else []
        width = max((m["x"] + m["width"] for m in monitors), default=MAX_SIDE)
        height = max((m["y"] + m["height"] for m in monitors), default=MAX_SIDE)
    scale = min(1.0, MAX_SIDE / max(width, height, 1))
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        path = f.name
    try:
        argv = ["grim", "-t", "png", "-s", f"{scale:.3f}"]
        if geometry:
            argv += ["-g", geometry]
        rc, _, err = desktop.sh([*argv, path])
        if rc != 0:
            return [{"type": "text", "text": f"grim failed: {err}"}]
        with open(path, "rb") as f:
            data = base64.b64encode(f.read()).decode()
    finally:
        with contextlib.suppress(OSError):
            os.unlink(path)
    note = f"Scaled to {scale:.2f}x: multiply image coordinates by {1 / scale:.2f} for screen positions." if scale < 1 else "Full resolution."
    return [{"type": "image", "data": data, "mimeType": "image/png"}, {"type": "text", "text": note}]


def call(name: str, args: dict) -> tuple[list[dict], bool]:
    if name == "screenshot":
        content = _screenshot(args)
        return content, not any(c["type"] == "image" for c in content)
    if name == "windows":
        return [{"type": "text", "text": _desktop(["windows"])}], False
    if name == "see":
        argv = ["see", *_target_args(args)]
        if args.get("grep"):
            argv += ["--grep", str(args["grep"])]
        text = _desktop(argv)
        return [{"type": "text", "text": text}], '"error"' in text[:40]
    if name == "click":
        argv = ["click", *_target_args(args)]
        if args.get("label"):
            argv.append(str(args["label"]))
        elif args.get("x") is not None and args.get("y") is not None:
            argv += [str(int(args["x"])), str(int(args["y"]))]
        else:
            return [{"type": "text", "text": "click needs a label, or x and y"}], True
        text = _desktop(argv)
        return [{"type": "text", "text": text}], '"error"' in text[:40]
    if name == "ipc_show":
        rc, out, err = desktop.sh(["qs", "-p", desktop.SHELL, "ipc", "show"])
        return [{"type": "text", "text": out if rc == 0 else err}], rc != 0
    if name == "ipc_call":
        argv = desktop.qs(str(args.get("target") or ""), str(args.get("function") or ""), *[str(a) for a in args.get("args") or []])
        rc, out, err = desktop.sh(argv)
        return [{"type": "text", "text": (out or err or "ok") + ("" if rc == 0 else f"\n(exit {rc}: {shlex.join(argv)})")}], rc != 0
    raise KeyError(name)


def handle(msg: dict) -> dict | None:
    method = msg.get("method")
    rid = msg.get("id")
    if rid is None:
        return None  # a notification (initialized, cancelled): nothing to answer
    if method == "initialize":
        asked = (msg.get("params") or {}).get("protocolVersion")
        return {"jsonrpc": "2.0", "id": rid, "result": {
            "protocolVersion": asked if asked in PROTOCOLS else PROTOCOLS[0],
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "ii-desktop", "version": "1.0.0"},
            "instructions": "Tools to look at and control the user's Hyprland desktop and its Quickshell shell."}}
    if method == "ping":
        return {"jsonrpc": "2.0", "id": rid, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": rid, "result": {"tools": TOOLS}}
    if method == "tools/call":
        params = msg.get("params") or {}
        try:
            content, failed = call(params.get("name") or "", params.get("arguments") or {})
        except KeyError:
            return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32602, "message": f"unknown tool {params.get('name')}"}}
        except (subprocess.SubprocessError, OSError, RuntimeError, ValueError) as e:
            content, failed = [{"type": "text", "text": f"{type(e).__name__}: {e}"}], True
        return {"jsonrpc": "2.0", "id": rid, "result": {"content": content, "isError": failed}}
    return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": f"{method} is not supported"}}


def main() -> int:
    for line in sys.stdin:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if not isinstance(msg, dict):
            continue
        reply = handle(msg)
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
