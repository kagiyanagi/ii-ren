#!/usr/bin/env python3
"""Assert the desktop's parallax lands a finite number, and that its planes share a spec.

Two things about `modules/ii/background/Background.qml` that only a rare desktop shows:

1. **The clamp has to be NaN-safe.** The pan position is `(activeWorkspace.id - lower) /
   range`, where `lower`/`upper` round the occupied workspace ids out to the nearest
   `bar.workspaces.shown` chunk. Put every window inside one chunk -- all of them on
   workspace 10, which is one `Super+0` away -- and `range` is 0, the numerator is 0 too,
   and 0/0 is NaN. `Math.max(0, Math.min(1, NaN))` is NaN, not 0: the clamp that looks
   like it covers this does nothing, and the NaN reaches the wallpaper's `x`, which puts
   the whole plane nowhere. A monitor with no active workspace is the same NaN by the
   other route. Neither shape appears on a desktop with windows spread over 1..3.

2. **The four Behaviors have to name one spec.** `movableXSpace` is derived from the
   wallpaper's size, so a wallpaper swap moves `x`/`y` and resizes `width`/`height` in the
   same instant; the widget canvas parallaxes over the same distance at its own factor.
   Different durations there are not a wrong number, they are two planes sliding against
   each other, and a still frame of either one looks correct.

The expressions are lifted out of the QML rather than transcribed, so this file cannot
drift away from what it is asserting about.

Run: python3 tools/check-desktop-parallax.py
"""
import math
import pathlib
import re

QML = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/ii/background/Background.qml"
src = QML.read_text()


def expr(pattern: str) -> str:
    m = re.search(pattern, src)
    assert m, f"Background.qml no longer has {pattern!r} -- this check is stale"
    return m.group(1).strip()


# --- 1. the NaN guard ---------------------------------------------------------

# The guard's own two halves, lifted and then *run* below rather than restated here --
# a version of this check that transcribed the condition into Python passed happily
# when the QML's was commented out.
GUARD = expr(r"property real workspaceProgress: \{([\s\S]*?)\n +\}")
GUARD_COND, GUARD_FALLBACK = re.search(r"if \((.+?)\) return (\S+);", GUARD).groups()
GUARD_RETURN = re.search(r"return ([^;]+);\s*$", GUARD.strip()).group(1)

CHUNK = expr(r"property int chunkSize: Config\?\.options\.bar\.workspaces\.shown \?\? (\d+)")
LOWER = expr(r"property int lower: (.*)")
UPPER = expr(r"property int upper: (.*)")
CLAMP_X = expr(r"property real effectiveValueX: (.*)")
CLAMP_Y = expr(r"property real effectiveValueY: (.*)")


def js(text: str) -> str:
    """The subset of JS these expressions are written in, as Python."""
    return (text.replace("Math.floor", "math.floor")
                .replace("Math.ceil", "math.ceil")
                .replace("Math.min", "jsmin").replace("Math.max", "jsmax")
                .replace("bgRoot.", "").replace("chunkSize", str(int(CHUNK))))


def jsmin(*args):
    """Math.min, which is *not* Python's min: JS propagates NaN, Python drops it.

    `min(1, float('nan'))` is 1 in Python, because the comparison is false and it
    keeps the first argument. Translating the clamp with Python's builtins would
    sanitise exactly the value this check exists to catch.
    """
    return float("nan") if any(a != a for a in args) else min(args)


def jsmax(*args):
    return float("nan") if any(a != a for a in args) else max(args)


ENV = {"math": math, "jsmin": jsmin, "jsmax": jsmax}


def jsbool(text: str) -> str:
    """The boolean subset of JS the guard's condition is written in."""
    return (text.replace("===", "==").replace("!==", "!=")
                .replace("undefined", "None").replace("||", " or ").replace("&&", " and "))


def progress(first: int, last: int, active):
    """What Background.qml computes -- its own guard, evaluated, not reimplemented."""
    lower = eval(js(LOWER), ENV, {"firstWorkspaceId": first})
    upper = eval(js(UPPER), ENV, {"lastWorkspaceId": last})
    env = {**ENV, "id": active, "lower": lower, "range": upper - lower}
    if eval(jsbool(GUARD_COND), ENV, env):
        return float(GUARD_FALLBACK)
    try:
        return eval(js(GUARD_RETURN), ENV, env)
    except (ZeroDivisionError, TypeError):
        # JS raises neither: 0/0 is NaN, n/0 is Infinity, and `undefined - 1` is NaN.
        # All three are what this check is hunting, so keep going and let the assert
        # below name the case rather than dying on a Python-only exception.
        return float("nan") if active is None or active == lower else math.inf


def clamped(first: int, last: int, active, sidebar: float = 0.0):
    p = progress(first, last, active)
    env = {**ENV, "valueX": p, "valueY": p, "sidebarOffsetX": sidebar}
    return eval(js(CLAMP_X), ENV, env), eval(js(CLAMP_Y), ENV, env)


chunk = int(CHUNK)

# The guard is load-bearing, not decorative: feed the clamp a NaN as it is written in
# the QML and it hands one straight back. This is the whole reason the check exists --
# `Math.max(0, Math.min(1, x))` reads like it cannot return anything but 0..1, and for
# NaN it does, because every comparison NaN takes part in is false.
nan = float("nan")
leaked = eval(js(CLAMP_X), ENV, {**ENV, "valueX": nan, "sidebarOffsetX": 0.0})
assert leaked != leaked, \
    "effectiveValueX sanitises NaN on its own now -- re-derive what workspaceProgress is for"

# The two shapes that produced NaN, and the ordinary one that did not.
for first, last, active, label in [
    (chunk, chunk, chunk, "every window on the last workspace of a chunk"),
    (chunk * 2, chunk * 2, chunk * 2, "every window on the last workspace of the 2nd chunk"),
    (1, 1, 1, "every window on workspace 1"),
    (1, 5, None, "monitor with no active workspace"),
    (1, 5, 3, "windows spread over 1..5"),
]:
    for x, axis in zip(clamped(first, last, active), "xy"):
        assert x == x, f"{label}: effectiveValue{axis} is NaN -- the wallpaper plane goes nowhere"
        assert math.isfinite(x), f"{label}: effectiveValue{axis} is {x}"

# ...and across every occupied span a 10-workspace bar can produce, with the sidebar
# offset that is added *after* the clamp and is allowed to overshoot it by 0.15.
for first in range(1, 31):
    for last in range(first, 31):
        for active in range(first, last + 1):
            for sidebar in (-0.15, 0.0, 0.15):
                vx, vy = clamped(first, last, active, sidebar)
                assert math.isfinite(vx) and math.isfinite(vy), \
                    f"workspaces {first}..{last}, active {active}: ({vx}, {vy})"
                assert -0.15 <= vx <= 1.15 and 0.0 <= vy <= 1.0, \
                    f"workspaces {first}..{last}, active {active}: ({vx}, {vy}) out of range"

# --- 2. the planes travel together --------------------------------------------

SPEC = r"animation: Appearance\.animation\.(\w+)\.numberAnimation\.createObject\(this\)"


def specs_after(anchor: str, count: int) -> list[str]:
    """The animation spec each of the next `count` Behaviors names, from `anchor` on."""
    at = src.index(anchor)
    found = re.findall(rf"Behavior on (\w+) \{{\s*\n\s*{SPEC}", src[at:])
    assert len(found) >= count, f"fewer than {count} tokenised Behaviors after {anchor!r}"
    return found[:count]


wallpaper = dict(specs_after("id: wallpaper\n", 4))
assert set(wallpaper) == {"x", "y", "width", "height"}, \
    f"the wallpaper plane animates {sorted(wallpaper)}, not x/y/width/height"
assert len(set(wallpaper.values())) == 1, \
    f"the wallpaper's position and size run on different specs: {wallpaper}"

canvas = dict(specs_after("id: widgetCanvas", 3))
for axis in ("x", "y"):
    assert canvas[axis] == wallpaper[axis], (
        f"the widget canvas parallaxes on {canvas[axis]} while the wallpaper under it "
        f"uses {wallpaper[axis]} -- the two planes slide against each other")

print(f"ok: desktop parallax is finite for 1..30 workspaces in chunks of {chunk}, "
      f"and wallpaper + widget canvas both travel on {wallpaper['x']}")
