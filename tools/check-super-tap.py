#!/usr/bin/env python3
"""Assert Super on its own opens search only when it was tapped, not after Super+key.

Hyprland 0.57 sends a press-bound `global` its release unconditionally, so a
`SUPER + SUPER_L` bind that fired on press made the shell toggle search on every
Super release -- after Super+J, Super+drag and every other combo too. A release bind
(`release = true`) is what Hyprland shadows once anything else is used during the
hold. The interrupt binds that used to paper over this (a `catchall` submap) were
lost moving to Lua, and nothing failed. Every lone-Super bind in the shipped
keybinds must therefore be a release bind; the one exception is the workspace-number
hint, which needs both edges of the hold.
Its release must also be delivered while locked: Super+L locks before Super is
released, and losing that edge leaves superDown true through the next hold.
"""
import pathlib, re

KEYBINDS = (pathlib.Path(__file__).resolve().parent.parent
            / "dots/.config/hypr/hyprland/keybinds.lua").read_text()
SUPER = {"SUPER", "SUPER_L", "SUPER_R"}
HOLD_HINT = "quickshell:workspaceNumber"


def binds(text):
    """Yield (combo, rest-of-call) for each `hl.bind(...)`, however many lines it spans."""
    for start in (m.end() for m in re.finditer(r"\bhl\.bind\(", text)):
        depth, i, quote = 1, start, None
        while depth:
            c = text[i]
            if quote:
                quote = None if c == quote and text[i - 1] != "\\" else quote
            elif c in "\"'":
                quote = c
            else:
                depth += {"(": 1, ")": -1}.get(c, 0)
            i += 1
        call = text[start:i - 1]
        combo = re.match(r'\s*"([^"]*)"', call)
        if combo:
            yield combo.group(1), call[combo.end():]


search_sides = set()
released_hints = set()
for combo, rest in binds(KEYBINDS):
    keys = {k.strip().upper() for k in combo.split("+")}
    if not keys <= SUPER or not keys & {"SUPER_L", "SUPER_R"}:
        continue
    if HOLD_HINT in rest:
        if re.search(r"\brelease\s*=\s*true\b", rest):
            assert re.search(r"\blocked\s*=\s*true\b", rest), \
                f'"{combo}" loses the Super release after Super+L while locked'
            released_hints |= keys & {"SUPER_L", "SUPER_R"}
        continue
    assert re.search(r"\brelease\s*=\s*true\b", rest), f'"{combo}" fires on press, so it also fires after every Super combo: {rest.strip()}'
    if "quickshell:searchToggleRelease" in rest:
        search_sides |= keys & {"SUPER_L", "SUPER_R"}

assert search_sides == {"SUPER_L", "SUPER_R"}, f"search bound on a lone Super tap only for {search_sides}"
assert released_hints == {"SUPER_L", "SUPER_R"}, f"hold hint release missing for {released_hints}"
print("ok: lone Super taps alone open search; both hold-hint releases survive locking")
