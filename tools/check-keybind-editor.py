#!/usr/bin/env python3
"""Assert the keybind editor cannot damage the user's Hyprland config.

This gate exists because it already happened. The first version of
`UserKeybinds.add()` read `custom/keybinds.lua` into a string, appended the new
line and wrote the whole thing back -- and during testing that lost three of the
user's binds. A whole-file rewrite can only ever be as correct as the copy it
started from, and that file is hand-edited underneath the shell.

So the first thing checked here is structural, not behavioural: **adding a bind
appends, and the service never calls `setText`**. `>>` cannot delete a line that
is already in the file, so the failure mode stops existing rather than being
guarded against. Removal has to rewrite, so it is held to a different rule: one
pass over the file on disk, the first exact match only, through a temporary file.

The rest mirrors the two pieces of logic that decide what actually gets written:
the lua string escaping, and the Qt-key-to-Hyprland-name mapping the capture
field uses. Neither is visible in a screenshot, and both fail silently -- a
mis-escaped command writes a line that parses and never fires.

Run: python3 tools/check-keybind-editor.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
service = (ROOT / "services/UserKeybinds.qml").read_text()
keys_js = (ROOT / "modules/ii/cheatsheet/keybind_keys.js").read_text()

fail = []


def check(ok, msg):
    if not ok:
        fail.append(msg)


# --- 1. the write path cannot lose a line ------------------------------------

check("setText" not in service,
      "UserKeybinds calls setText again -- that rewrites the whole file from a cached "
      "copy, which is exactly what deleted three of the user's binds")
check(">>" in service,
      "adding a bind no longer appends; a rewrite cannot be safe here")
check(re.search(r'command\s*=\s*\["sh",\s*"-c",', service),
      "the append is no longer a shell append")
# The line has to travel as an argv element. Interpolated into the script it
# would be re-parsed by the shell, and a command with a backtick or a $ in it
# would execute on the way to being written down.
check(re.search(r'"sh",\s*line,\s*root\.filePath', service),
      "the bind line is not passed as an argv element any more -- interpolating it into "
      "the shell script would execute it instead of writing it")
check("os.replace(tmp, path)" in service,
      "removal no longer writes through a temporary file, so a failure mid-write "
      "truncates the config")
check("lines.remove(target)" in service,
      "removal no longer takes the first exact match only")


# --- 2. lua escaping ----------------------------------------------------------

def lua_string(value):
    """`luaString` from UserKeybinds.qml, as Python."""
    if re.search(r"[\x00-\x1f]", value):
        return None
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


for raw, expected in [
    ("kitty", '"kitty"'),
    ('notify-send "hi"', '"notify-send \\"hi\\""'),
    (r"C:\path\thing", '"C:\\\\path\\\\thing"'),
    ("say \\\"nested\\\"", '"say \\\\\\"nested\\\\\\""'),
    ("", '""'),
]:
    check(lua_string(raw) == expected,
          f"lua escaping of {raw!r} is {lua_string(raw)!r}, expected {expected!r}")

# A newline would end the statement and turn the rest of the argument into lua.
for hostile in ["a\nhl.bind(\"X\")", "a\rb", "a\tb", "\x00"]:
    check(lua_string(hostile) is None,
          f"{hostile!r} is escaped rather than refused -- it can break the line in two")

# And the generated line has to survive the service's own parser.
BIND = re.compile(
    r'^\s*hl\.bind\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*hl\.dsp\.([a-z_]+)\(\s*"((?:[^"\\]|\\.)*)"\s*\)'
    r'\s*(?:,\s*\{([^}]*)\})?\s*\)\s*$')


def bind_line(combo, dispatcher, argument, description):
    parts = [lua_string(combo), lua_string(argument), lua_string(description)]
    if any(p is None for p in parts) or not re.fullmatch(r"[a-z_]+", dispatcher):
        return None
    tail = f", {{description = {parts[2]}}}" if description else ""
    return f"hl.bind({parts[0]}, hl.dsp.{dispatcher}({parts[1]}){tail})"


for combo, dispatcher, argument, description in [
    ("SUPER + K", "exec_cmd", "kitty", "Custom: Terminal"),
    ("SUPER + SHIFT + Y", "exec_cmd", 'notify-send "hi"', "Custom: Say hi"),
    ("CTRL + ALT + Delete", "global", "quickshell:sessionToggle", ""),
    ("SUPER + Slash", "exec_cmd", r"sh -c 'echo \ok'", "Custom: odd \"one\""),
]:
    line = bind_line(combo, dispatcher, argument, description)
    check(line is not None, f"{combo} / {argument!r} produced no line")
    if line is None:
        continue
    match = BIND.match(line)
    check(match is not None, f"the service cannot parse the line it generated: {line}")
    if match is None:
        continue
    unescape = lambda v: v.replace('\\"', '"').replace("\\\\", "\\")  # noqa: E731
    check(unescape(match.group(1)) == combo, f"combo did not round-trip in {line}")
    check(unescape(match.group(3)) == argument, f"argument did not round-trip in {line}")
    if description:
        found = re.search(r'description\s*=\s*"((?:[^"\\]|\\.)*)"', match.group(4) or "")
        check(found is not None and unescape(found.group(1)) == description,
              f"description did not round-trip in {line}")

# A dispatcher is never user text, but it is interpolated unquoted, so it is the
# one field that must be refused rather than escaped.
for bad in ["exec_cmd; os.execute", "exec-cmd", "Exec", "exec_cmd()"]:
    check(bind_line("SUPER + K", bad, "kitty", "") is None,
          f"dispatcher {bad!r} was accepted into an unquoted position")


# --- 3. the combo <-> modmask round trip --------------------------------------

MOD_BITS = {"SHIFT": 1, "CAPS": 2, "CAPSLOCK": 2, "CTRL": 4, "CONTROL": 4,
            "ALT": 8, "MOD1": 8, "MOD2": 16, "MOD3": 32,
            "SUPER": 64, "WIN": 64, "LOGO": 64, "MOD4": 64, "MOD5": 128}


def parse_combo(combo):
    parts = [p.strip() for p in combo.split("+") if p.strip()]
    if not parts:
        return None
    modmask, key = 0, ""
    for part in parts:
        bit = MOD_BITS.get(part.upper())
        if bit is not None:
            modmask |= bit
        else:
            key = part
    return None if not key else (modmask, key)


# The left column is what `hyprctl binds -j` reports for these, read off the live
# list rather than worked out from the xkb tables.
for combo, expected in [
    ("SUPER + SHIFT + W", (65, "W")),
    ("CTRL+SUPER+ALT+Slash", (76, "Slash")),
    ("SUPER + escape", (64, "escape")),
    ("Print", (0, "Print")),
    ("SUPER + SHIFT + Page_Up", (65, "Page_Up")),
]:
    check(parse_combo(combo) == expected,
          f"{combo!r} parses to {parse_combo(combo)}, expected {expected}")

for empty in ["", "   ", "SUPER", "SUPER + SHIFT", "+++"]:
    check(parse_combo(empty) is None,
          f"{empty!r} parsed as a bind, but it names no key")


# --- 4. the key capture -------------------------------------------------------

names = dict(re.findall(r"^\s*(0x[0-9a-f]+):\s*\"([^\"]+)\",", keys_js, re.M))
# Spot-check the ones whose spelling is easy to get wrong and impossible to see:
# a wrong name writes a line that parses and never fires.
for code, expected in [("0x01000004", "Return"), ("0x01000003", "BackSpace"),
                       ("0x2f", "Slash"), ("0x2e", "Period"), ("0x01000016", "Page_Up"),
                       ("0x01000017", "Page_Down"), ("0x01000009", "Print"),
                       ("0x20", "Space"), ("0x0100003b", "F12")]:
    check(names.get(code) == expected,
          f"Qt key {code} maps to {names.get(code)!r}, expected {expected!r}")

# Every mapped name has to be one Hyprland would accept: xkb keysym names are
# alphanumerics and underscores, nothing else.
for code, name in names.items():
    check(re.fullmatch(r"[A-Za-z0-9_]+", name) is not None,
          f"Qt key {code} maps to {name!r}, which is not a keysym name")

modifier_codes = re.search(r"const modifierKeys = \[(.*?)\];", keys_js, re.S).group(1)
for code in ["0x01000020", "0x01000021", "0x01000022", "0x01000023"]:
    check(code in modifier_codes,
          f"{code} is not treated as a modifier, so holding it alone would be captured as a bind")

# Modifier order has to match the order the list prints, or a combo reads one way
# in the editor and another in the sheet behind it.
order = re.findall(r"\[0x[0-9a-f]+,\s*\"([A-Z]+)\"\]", keys_js)
check(order == ["CTRL", "SUPER", "SHIFT", "ALT"],
      f"the editor writes modifiers in the order {order}, not the order the sheet prints")


if fail:
    print(f"check-keybind-editor.py: {len(fail)} finding(s)\n")
    for f in fail[:30]:
        print(f"  FAIL  {f}")
    sys.exit(1)
print("check-keybind-editor.py: ok")
