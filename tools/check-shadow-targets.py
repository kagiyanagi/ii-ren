#!/usr/bin/env python3
"""A shadow sits next to the item it shadows.

StyledDropShadow and StyledRectangularShadow `anchors.fill` their `target`, and
QML anchors only reach a parent or a sibling. Six background clocks declared
the shadow beside their container while the target was inside it (in one, two
levels down a Column): Qt printed "Cannot anchor to an item that isn't a
parent or sibling" once, the shadow stayed 0x0 and those clocks had no shadow
at all. Nothing else shows it - the clock still looks fine, only flatter.

Parse every shell QML file's object nesting and require each shadow's target
id to be declared as its sibling or its parent. A target that is not a plain
id (a property, an expression) cannot be checked here and is skipped, as is a
shadow that sets its own anchors.fill (Toolbar's, inside an anchored Loader).

Run: python3 tools/check-shadow-targets.py
"""

import re
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
SHADOWS = ("StyledDropShadow", "StyledRectangularShadow")
OPEN = re.compile(r"^\s*(?:[\w.]+\s*:\s*)?([A-Z][\w.]*)\s*\{")


def objects(text):
    """(type, parent index, ids, targets) per object, from the brace nesting."""
    found = []
    stack = []  # index into found, or None for a non-object brace
    for number, raw in enumerate(text.splitlines(), 1):
        line = re.sub(r"//.*$", "", raw)
        line = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '""', line)
        opener = OPEN.match(line)
        if opener and not line.strip().startswith(("function", "if", "for", "else", "return")):
            parent = next((i for i in reversed(stack) if i is not None), None)
            found.append({"type": opener.group(1), "parent": parent, "line": number, "id": None, "target": None, "anchors": False})
            stack.append(len(found) - 1)
            rest = line[opener.end():]
        else:
            rest = line
        current = stack[-1] if stack else None
        if current is not None:
            if m := re.match(r"^\s*id:\s*(\w+)\s*;?\s*$", line):
                found[current]["id"] = m.group(1)
            if m := re.match(r"^\s*target:\s*(\w+)\s*;?\s*$", line):
                found[current]["target"] = m.group(1)
            if re.match(r"^\s*anchors\.fill:", line):
                found[current]["anchors"] = True
        for ch in rest:
            if ch == "{":
                stack.append(None)
            elif ch == "}" and stack:
                stack.pop()
    return found


problems = []
checked = 0
for path in sorted(II.rglob("*.qml")):
    text = path.read_text(errors="replace")
    if not any(s in text for s in SHADOWS):
        continue
    found = objects(text)
    by_id = {o["id"]: i for i, o in enumerate(found) if o["id"]}
    for i, shadow in enumerate(found):
        if shadow["type"] not in SHADOWS or shadow["target"] not in by_id or shadow["anchors"]:
            continue
        checked += 1
        target = by_id[shadow["target"]]
        if found[target]["parent"] != shadow["parent"] and target != shadow["parent"]:
            problems.append(f"{path.relative_to(II)}:{shadow['line']}: {shadow['type']} targets "
                            f"{shadow['target']} (line {found[target]['line']}), neither its sibling nor its parent")

assert checked > 10, f"only {checked} shadows found; the parser no longer sees them"
assert not problems, "a shadow cannot anchor to its target, so it is 0x0:\n  " + "\n  ".join(problems)
print(f"ok: all {checked} shadows sit next to their targets")
