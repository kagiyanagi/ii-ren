#!/usr/bin/env python3
"""Assert the Alt+Tab tile grid never paints outside its card.

Until this row the tiles were a `Row`: one line, no cap. The card clamped its own
width to 90% of the screen but nothing clipped, so past ~17 windows the tiles kept
drawing straight through the card border and off the edge of the screen, taking the
selection highlight with them. `currentWorkspaceOnly` ships `false`, so that is every
window on every workspace -- not a rare shape.

A `Grid` fixes it, and the arithmetic that makes it fit is the part no screenshot can
check: a desktop with four windows exercises none of the wrap, and staging twenty is
not something a session can do. So the expressions are lifted out of AltTab.qml and
evaluated here rather than transcribed, which is also what stops this file drifting
away from the QML it is asserting about.

Run: python3 tools/check-alttab-grid.py
"""
import math
import pathlib
import re
import sys

QML = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/ii/altTab/AltTab.qml"
src = QML.read_text()

# --- structural: the shape this file exists to defend -------------------------

assert re.search(r"Grid \{\s*\n\s*id: tiles", src), \
    "the Alt+Tab tiles are not a Grid any more -- a Row cannot wrap, and nothing clips"
assert "Behavior on y" in src, \
    "the highlight animates x but not y -- it cannot follow a selection onto the second row"


def expr(pattern: str) -> str:
    m = re.search(pattern, src)
    assert m, f"AltTab.qml no longer has {pattern!r} -- this check is stale"
    return m.group(1).strip()


def const(name: str) -> int:
    return int(expr(rf"property int {name}: (\d+)\b"))


def js(text: str) -> str:
    """The subset of JS these four expressions are written in, as Python."""
    for a, b in (
        ("Math.max(", "max("), ("Math.floor(", "math.floor("), ("Math.ceil(", "math.ceil("),
        ("panel.screen.width", "screenWidth"), ("card.padding", "padding"),
        ("root.tileSpacing", "tileSpacing"), ("root.tileSize", "tileSize"),
        ("root.windows.length", "n"), ("root.selectedIndex", "i"), ("tiles.columns", "columns"),
    ):
        text = text.replace(a, b)
    # One ternary, and it holds no other `?` or `:`.
    if "?" in text:
        cond, rest = text.split("?", 1)
        then, alt = rest.rsplit(":", 1)
        text = f"(({then}) if ({cond}) else ({alt}))"
    return text


TILE = const("tileSize")
GAP = const("tileSpacing")
PAD = const("padding")
MAX_COLUMNS = js(expr(r"property int maxColumns: (.+)"))
COLUMNS = js(expr(r"\n\s*columns: (.+)"))
HL_X = js(expr(r"\n\s*x: (\(root\.selectedIndex.+)"))
HL_Y = js(expr(r"\n\s*y: (Math\.floor\(root\.selectedIndex.+)"))

env = {"math": math, "max": max, "tileSize": TILE, "tileSpacing": GAP, "padding": PAD}

# A 1280-wide laptop through a 5120-wide ultrawide, and one absurd sliver.
for screen in (320, 1280, 1366, 1920, 2560, 3440, 5120):
    cap = screen * 0.9 - PAD * 2
    maxColumns = eval(MAX_COLUMNS, {}, {**env, "screenWidth": screen})
    assert maxColumns >= 1, f"{screen}px screen yields {maxColumns} columns -- a Grid with 0 columns lays out nothing"

    for n in range(1, 201):
        e = {**env, "screenWidth": screen, "n": n, "maxColumns": maxColumns}
        columns = eval(COLUMNS, {}, e)
        rows = math.ceil(n / columns)
        width = columns * (TILE + GAP) - GAP

        assert columns >= 1, f"{n} windows on {screen}px yields {columns} columns"
        # The whole point: a wider-than-the-cap grid is what painted off screen.
        # The sliver screen cannot fit one tile, and one tile is the floor.
        assert width <= cap or columns == 1, \
            f"{n} windows on {screen}px: grid is {width}px wide against a {cap:.0f}px cap"
        # Balanced rows. Unbalanced (columns = maxColumns) puts 21 windows on a
        # 1920 screen as a row of 20 and an orphan, which is what this guards.
        last = n - (rows - 1) * columns
        assert 1 <= last <= columns, f"{n} windows on {screen}px: last row holds {last} of {columns}"
        assert rows == 1 or columns - last < rows, \
            f"{n} windows on {screen}px: rows of {columns} then {last} -- not balanced"

        # The highlight has to land on a tile, not past the end of the grid.
        for i in (0, n // 2, n - 1):
            x = eval(HL_X, {}, {**e, "i": i, "columns": columns})
            y = eval(HL_Y, {}, {**e, "i": i, "columns": columns})
            assert 0 <= x and x + TILE <= width, f"highlight for window {i} of {n} sits at x={x} in a {width}px grid"
            assert 0 <= y and y + TILE <= rows * (TILE + GAP) - GAP, \
                f"highlight for window {i} of {n} sits at y={y} across {rows} rows"

# The regression, stated as a number: on a 1080p screen the old single row ran
# past the card at this many windows, and the wrap is what the fix rests on.
overflow = math.floor((1920 * 0.9 - PAD * 2 + GAP) / (TILE + GAP)) + 1
assert eval(COLUMNS, {}, {**env, "screenWidth": 1920, "n": overflow,
                          "maxColumns": eval(MAX_COLUMNS, {}, {**env, "screenWidth": 1920})}) < overflow, \
    f"{overflow} windows still lay out as one row on a 1080p screen"

print(f"ok: alt-tab grid fits {TILE}px tiles on 320..5120px screens, 1..200 windows "
      f"(1080p wraps at {overflow})")
