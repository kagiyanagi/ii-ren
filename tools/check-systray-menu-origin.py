#!/usr/bin/env python3
"""The tray menu still grows out of the icon that opened it, and still animates shut.

DESIGN.md 2.6: a popup's transform origin is the corner or edge nearest the thing
that opened it. For the tray that lives in two files -- SysTrayItem.qml picks the
`anchor.edges` the popup attaches by, SysTrayMenu.qml picks the `transformOrigin`
it scales from -- so changing one without the other is silent: the menu still
appears in the right place, it just grows out of the wrong side. check-design.py
says so itself ("Not checkable here: transform origin").

Also guards DESIGN.md 2.5 / anti-pattern 10: the menu must run its close
animation, not hide the window from close().
"""

import re
import sys
from pathlib import Path

BAR = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii/modules/ii/bar"

# A popup placed off the anchor's bottom edge sits below it, so the point nearest
# the icon is the popup's top. Origin is the opposite of the edge it attaches by.
OPPOSITE = {"Left": "Right", "Right": "Left", "Top": "Bottom", "Bottom": "Top"}


def block(text, opener):
    """The body of the first `<opener>` block, brace-matched. `opener` ends in `{`."""
    i = text.index(opener) + len(opener) - 1
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    raise AssertionError(f"unbalanced braces after {opener!r}")


def main():
    item = (BAR / "SysTrayItem.qml").read_text()
    menu = (BAR / "SysTrayMenu.qml").read_text()

    edges_src = block(item, "edges: {")
    origin_src = block(menu, "transformOrigin: {")

    # Both blocks must branch on the same two config options, in the same order,
    # or comparing them position by position means nothing.
    for name, src in (("edges", edges_src), ("transformOrigin", origin_src)):
        conds = re.findall(r"Config\.options\.bar\.(vertical|bottom)", src)
        assert conds == ["vertical", "bottom", "bottom"], \
            f"{name} branches on {conds}, expected vertical then bottom twice"

    # Edges.Middle / Edges.Center only say "centred along the bar", not which side.
    edges = [e for e in re.findall(r"Edges\.(\w+)", edges_src) if e in OPPOSITE]
    origins = [o for o in re.findall(r"Item\.(\w+)", origin_src) if o in OPPOSITE]

    assert len(edges) == 4, f"expected 4 attach edges, got {edges}"
    assert len(origins) == 4, f"expected 4 transform origins, got {origins}"

    for edge, origin in zip(edges, origins):
        assert origin == OPPOSITE[edge], (
            f"menu attaches by Edges.{edge} but scales from Item.{origin}; "
            f"DESIGN 2.6 wants Item.{OPPOSITE[edge]}"
        )

    # The exit has to run. Hiding the window from close() skips it entirely.
    close_body = block(menu, "function close() {")
    assert "visible = false" not in close_body, \
        "SysTrayMenu.close() hides the window directly -- the exit never plays (DESIGN 2.5)"
    assert re.search(r"onFinished:\s*\{[^}]*visible\s*=\s*false", menu), \
        "nothing hides the window when the close animation finishes"

    print(f"ok: tray menu grows from {'/'.join(origins)} for attach edges {'/'.join(edges)}, "
          "and closes through its exit animation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
