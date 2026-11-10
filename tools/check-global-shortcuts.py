#!/usr/bin/env python3
"""Assert every `quickshell:<name>` global the repo dispatches is a GlobalShortcut in the shell.

A bind on `hl.dsp.global("quickshell:<name>")` reaches the shell only if some
`GlobalShortcut { name: "<name>" }` registered that name. If none did, Hyprland
drops the press without a word, in its log or the shell's. Super+Escape in
custom/keybinds.lua called
`settingsToggle`, which nothing declared, and simply never worked.

Every literal `hl.dsp.global("quickshell:...")` under dots/.config/hypr (binds,
gestures, hypridle) and in the shell's own sources is collected, and so is every
GlobalShortcut name under the shell. Each one used must be declared somewhere.
That says nothing of the panel family: a name declared only in one family's
module is unregistered while the other family runs. A global spelled any way
other than a string literal fails here, since it could not be checked.

    python3 tools/check-global-shortcuts.py
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
HYPR = ROOT / "dots/.config/hypr"
SHELL = ROOT / "dots/.config/quickshell/ii"

CALL = re.compile(r"\bdsp\.global\s*\(")
LITERAL = re.compile(r'\bdsp\.global\s*\(\s*"quickshell:([A-Za-z0-9_]+)"\s*\)')


def block(text, start):
    """The body of the `{ ... }` block whose opening brace is at `start`."""
    depth = 0
    for i in range(start, len(text)):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        if depth == 0:
            return text[start + 1:i]
    raise AssertionError("unbalanced braces after GlobalShortcut")


declared = {}
for path in SHELL.rglob("*.qml"):
    text = path.read_text()
    for m in re.finditer(r"\bGlobalShortcut\s*\{", text):
        body = block(text, m.end() - 1)
        name = re.search(r'^\s*name:\s*"([^"]+)"\s*$', body, re.M)
        where = f"{path.relative_to(ROOT)}:{text.count(chr(10), 0, m.start()) + 1}"
        assert name, f"{where}: GlobalShortcut without a literal name: cannot tell which globals it serves"
        declared.setdefault(name.group(1), where)

used = {}
sources = [p for p in HYPR.rglob("*") if p.is_file() and p.suffix in (".lua", ".conf")]
sources += [p for p in SHELL.rglob("*") if p.is_file() and p.suffix in (".qml", ".js")]
for path in sources:
    text = path.read_text()
    for m in CALL.finditer(text):
        line = text.count("\n", 0, m.start()) + 1
        where = f"{path.relative_to(ROOT)}:{line}"
        literal = LITERAL.match(text, m.start())
        assert literal, f"{where}: a global that is not a \"quickshell:<name>\" literal cannot be checked"
        used.setdefault(literal.group(1), where)

assert len(declared) >= 30, f"found only {len(declared)} GlobalShortcuts; the scan no longer reads the shell"
assert len(used) >= 20, f"found only {len(used)} quickshell globals in use; the scan no longer reads the binds"

missing = sorted(f"{where}: quickshell:{name}" for name, where in used.items() if name not in declared)
assert not missing, "dispatched, but no GlobalShortcut declares them, so Hyprland drops them:\n  " + "\n  ".join(missing)

print(f"ok: all {len(used)} quickshell globals the repo dispatches are declared ({len(declared)} GlobalShortcuts)")
