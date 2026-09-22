#!/usr/bin/env python3
"""A tooltip is only on screen while its owner is hovered.

`StyledToolTip` decides that from its parent, and its fallback used to be
`parent.hovered === undefined || parent.hovered` -- "a parent that reports no
hover state is always hovered". That is fine for a `Control`, which has
`hovered`. A `MouseArea` does not: it reports hover as `containsMouse`, so every
tooltip parented to one satisfied the `undefined` arm on the first frame and sat
open for as long as its owner existed. The volume mixer stacked five of them over
the app rows, in the sidebar dialog and in the overlay widget, with nothing
hovered.

Most callers had already worked around it by hand -- `extraVisibleCondition:
false` plus `alternativeVisibleCondition: mouseArea.containsMouse`, and
`FingerprintHandPicker` and `GeneralConfig` both carry a comment explaining the
fallback -- which is what made this a shared-widget bug rather than one surface's.

The gate evaluates the real expression lifted out of `StyledToolTip.qml` against
each shape of parent, and then checks the one thing the fix can break: a
`MouseArea` with `hoverEnabled` off never sets `containsMouse`, so its tooltip
would now be unreachable instead of permanent.

    python3 tools/check-tooltip-hover.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"
TOOLTIP = SHELL / "modules/common/widgets/StyledToolTip.qml"


# --- the expression, evaluated rather than mirrored ---------------------------

UNDEF = object()


class Parent:
    """A QML object: reading a property it does not declare gives `undefined`."""

    def __init__(self, **props):
        self.__dict__.update(props)

    def __getattr__(self, _name):
        return UNDEF


def coalesce(a, b):
    return b if a is UNDEF or a is None else a


def to_python(js):
    """`a ?? b ?? c` -> `coalesce(a, coalesce(b, c))`, then JS operators."""
    group = re.compile(r"\(([^()]*\?\?[^()]*)\)")
    while "??" in js:
        m = group.search(js)
        assert m, f"unparseable ?? chain: {js}"
        parts = [p.strip() for p in m.group(1).split("??")]
        folded = parts[-1]
        for part in reversed(parts[:-1]):
            folded = f"coalesce({part}, {folded})"
        js = js[:m.start()] + f"({folded})" + js[m.end():]
    for src, dst in (("!==", " is not "), ("===", " == "), ("&&", " and "),
                     ("||", " or "), ("true", "True"), ("false", "False"),
                     ("null", "None"), ("undefined", "UNDEF")):
        js = js.replace(src, dst)
    return js


condition = re.search(
    r"readonly property bool internalVisibleCondition:(.*)", TOOLTIP.read_text()).group(1).strip()
assert "parent !== null" in condition, "the null-parent guard is gone"
EXPR = compile(to_python(condition), "<internalVisibleCondition>", "eval")


def shown(parent, extra=True, alternative=False):
    return bool(eval(EXPR, {"coalesce": coalesce, "UNDEF": UNDEF}, {
        "parent": parent,
        "extraVisibleCondition": extra,
        "alternativeVisibleCondition": alternative,
    }))


# A Control exposes `hovered`; this arm always worked.
assert not shown(Parent(hovered=False)), "a Control's tooltip shows unhovered"
assert shown(Parent(hovered=True))

# A MouseArea exposes `containsMouse` -- the bug.
assert not shown(Parent(containsMouse=False)), "a MouseArea's tooltip shows unhovered"
assert shown(Parent(containsMouse=True))

# A parent with neither (Rectangle, Item, MaterialSymbol) still shows: a dozen
# callers gate those with extraVisibleCondition and nothing else.
assert shown(Parent())
assert not shown(Parent(), extra=False)

# The two escape hatches the workarounds are built on keep working.
assert not shown(None)
assert shown(Parent(containsMouse=False), extra=False, alternative=True)


# --- who is parented to what -------------------------------------------------

def strip_noise(src):
    """Drop comments and string bodies, keeping every newline for line numbers.

    Template literals carry `${...}` braces and paths carry `//`, so counting
    braces over the raw text mis-nests.
    """
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in "\"'`":
            start, quote = i, c
            i += 1
            while i < n and src[i] != quote:
                i += 2 if src[i] == "\\" else 1
            i += 1
            out.append("\n" * src.count("\n", start, i))
        elif src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
        elif src.startswith("/*", i):
            start = i
            i = src.find("*/", i)
            i = n if i < 0 else i + 2
            out.append("\n" * src.count("\n", start, i))
        else:
            out.append(c)
            i += 1
    return "".join(out)


TOKEN = re.compile(r"[A-Za-z_][\w.]*|[{}\n]")


def tooltip_sites(path):
    """Every `StyledToolTip {` in a file, as (line, parent type, parent block)."""
    src = strip_noise(path.read_text())
    stack, line, last, sites = [], 1, "", []
    for m in TOKEN.finditer(src):
        tok = m.group()
        if tok == "\n":
            line += 1
        elif tok == "{":
            if last == "StyledToolTip":
                enclosing = next((e for e in reversed(stack) if e[0]), None)
                if enclosing:
                    sites.append([line, enclosing[0], enclosing[1], None])
            stack.append((last if last[:1].isupper() else "", m.end(), list(sites)))
            last = ""
        elif tok == "}":
            if stack:
                _, start, before = stack.pop()
                for site in sites[len(before):]:
                    if site[3] is None:
                        site[3] = src[start:m.start()]
        else:
            last = tok
    return [(line, kind, block) for line, kind, _, block in sites]


offenders = []
for path in sorted(SHELL.rglob("*.qml")):
    for line, kind, block in tooltip_sites(path):
        if kind != "MouseArea":
            continue
        # `hoverEnabled` defaults to false, and a MouseArea that never tracks the
        # pointer now never shows its tooltip at all.
        if not re.search(r"hoverEnabled\s*:\s*(?!false\b)\S", block):
            offenders.append(f"{path.relative_to(ROOT)}:{line}")

if offenders:
    print("StyledToolTip parented to a MouseArea that does not track hover:")
    print("\n".join("  " + o for o in offenders))
    sys.exit(1)

print("tooltip hover: ok")
