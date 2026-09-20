#!/usr/bin/env python3
"""Assert the shared button roots render all four interaction states.

DESIGN.md 3.1 wants hover, focus, pressed and disabled on every interactive
element. The library shipped three: nothing in it read `Button.visualFocus`, and
`RippleButton` defaulted its pressed colour to its hover colour, so a press
changed no pixel that a hover had not already changed.

Neither is visible to check-design.py -- a missing state is an absence, and an
absence has no line to flag. Every other button in the shell is rooted in one of
these files, so a regression here is a regression in ~300 call sites at once.

Run: python3 tools/check-button-states.py
"""
import pathlib, re, sys

WIDGETS = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"

# The root type line, ignoring imports, pragmas and comments.
ROOT = re.compile(r"^(?:pragma .*|import .*|//.*|/\*.*?\*/|\s*)*?^(\w+) \{", re.M | re.S)


def root_type(src: str) -> str:
    body = re.sub(r"^\s*(?:pragma|import)\b.*$", "", src, flags=re.M)
    body = re.sub(r"//.*$", "", body, flags=re.M)
    m = re.search(r"^\s*(\w+)\s*\{", body, re.M)
    return m.group(1) if m else ""


roots = sorted(p for p in WIDGETS.glob("*.qml") if root_type(p.read_text()) == "Button")
assert roots, "no QQC2 Button-rooted widget found -- did the library move?"
assert len(roots) == 2, f"a new shared button root appeared: {[p.name for p in roots]}"

for path in roots:
    src = path.read_text()
    name = path.name

    # Focus: the state the library had nowhere. `focus` is Item's own property and
    # is set by anything that takes focus; `visualFocus` is the keyboard-only one.
    assert "visualFocus" in src, \
        f"{name}: renders no focus state -- bind a state layer to Button.visualFocus"

    # Disabled is 0.4 on the whole control, not a greyed-out fill (DESIGN.md 3.1).
    assert re.search(r"opacity:\s*root\.enabled\s*\?\s*1\s*:\s*0\.4", src), \
        f"{name}: disabled must be `opacity: root.enabled ? 1 : 0.4`, not a colour swap"

    # Pressed (0.10) and hover (0.08) are different tokens. A root may either
    # default a distinct pressed colour, or composite the film itself -- but it may
    # not default pressed to hover and then render nothing extra for the press.
    inherits_hover = re.search(
        r"property color colBackgroundActive:\s*colBackgroundHover\b", src)
    if inherits_hover:
        assert re.search(r"^\s*press:[^\n]*\bdown\b", src, re.M), \
            (f"{name}: pressed defaults to the hover colour and no press state layer "
             f"renders -- a press would look exactly like a hover")

print(f"ok: {len(roots)} shared button roots render hover, focus, pressed and disabled")
