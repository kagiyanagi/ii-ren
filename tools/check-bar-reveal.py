#!/usr/bin/env python3
"""Assert the bar's two reveals name a direction each, and that neither exit is cut off.

`modules/ii/bar` hides and shows in two places, and both are the shape DESIGN.md 2.5
calls the most common motion bug in this shell: one spec used in both directions, or an
exit that never renders because the thing stops existing on the first frame of it.

1. **Auto-hide (`Bar.qml`).** The strip is a screen-edge panel: it slides in from its own
   edge on the default spatial spec and back out accelerating on fast effects at about a
   quarter of that. Both directions come out of one `revealSpec` assigned *inside* the
   binding that writes the margin, because a Behavior bakes its duration and curve at the
   instant of the write (2.9) -- read from a binding of its own the spec is a frame late
   and the exit runs on the enter's curve. `VerticalBar.qml` is the same panel on a side
   edge and is held to the same shape; it ran on one effects spec both ways after this
   one was fixed, and its right-hand bar hid by `barHeight`, the *horizontal* bar's
   thickness, leaving a strip of a wider vertical bar on screen.

2. **A widget coming and going (`BarComponent.qml`).** The record, screenshare and
   privacy indicators, the timer and an emptying tray call `toggleVisible()`. The
   delegate collapses along the bar's axis instead of popping, which only works if it
   stays `visible` while the collapse runs -- bind `visible` to the flag alone and the
   RowLayout drops it on frame one, so the exit is a pop after all. The cross axis has to
   keep its size, or the strip's height animates too.

The expressions are lifted out of the QML and run, not transcribed: a transcribed copy of
this passes happily when the QML's own version has been deleted.

Run: python3 tools/check-bar-reveal.py
"""
import pathlib
import re
from types import SimpleNamespace as NS

QML = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules"
bar = (QML / "ii/bar/Bar.qml").read_text()
vbar = (QML / "ii/verticalBar/VerticalBar.qml").read_text()
comp = (QML / "ii/bar/BarComponent.qml").read_text()
appearance = (QML / "common/Appearance.qml").read_text()


def grab(src, pattern, what):
    m = re.search(pattern, src)
    assert m, f"{what} -- this check is stale"
    return m


def block(src, opener, what):
    return grab(src, rf"{opener} \{{([\s\S]*?)\n +\}}", what).group(1)


# --- what the two motions' specs are actually worth ---------------------------

def spec(name):
    """`Appearance.animation.<name>` -> (duration in ms, curve token)."""
    m = grab(appearance,
             rf"property AnimSpec {name}: AnimSpec \{{\s*\n\s*duration: "
             rf"root\.animationCurves\.(\w+)\s*\n\s*bezierCurve: root\.animationCurves\.(\w+)",
             f"Appearance no longer declares {name}")
    ms = grab(appearance, rf"property real {m.group(1)}: (\d+)", f"no {m.group(1)}")
    return int(ms.group(1)), m.group(2)


ENTER_MS, ENTER_CURVE = spec("elementMoveEnter")
EXIT_MS, EXIT_CURVE = spec("elementMoveExit")
RESIZE_MS, RESIZE_CURVE = spec("elementResize")

for what, ms, curve in (("enter", ENTER_MS, ENTER_CURVE), ("resize", RESIZE_MS, RESIZE_CURVE)):
    assert "Spatial" in curve, f"the {what} spec runs on {curve}, not a spatial curve (2.1)"
assert "Effects" in EXIT_CURVE, f"the exit spec runs on {EXIT_CURVE}, not an effects curve (2.5)"
for what, ms in (("elementMoveEnter", ENTER_MS), ("elementResize", RESIZE_MS)):
    assert EXIT_MS <= ms / 2, \
        f"the exit is {EXIT_MS}ms against {what}'s {ms}ms -- 2.5 wants about half or less"


# --- the subset of JS these bindings are written in ---------------------------

def ternary(expr):
    """`a ? b : c` -> `((b) if (a) else (c))`, outermost first, paren aware."""
    depth = 0
    for i, ch in enumerate(expr):
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == "?" and depth == 0:
            cond, rest = expr[:i], expr[i + 1:]
            d = pending = 0
            for j, c in enumerate(rest):
                if c in "([":
                    d += 1
                elif c in ")]":
                    d -= 1
                elif c == "?" and d == 0:
                    pending += 1
                elif c == ":" and d == 0:
                    if pending:
                        pending -= 1
                        continue
                    return (f"(({ternary(rest[:j])}) if ({ternary(cond)}) "
                            f"else ({ternary(rest[j + 1:])}))")
            raise AssertionError(f"unbalanced ternary in {expr!r}")
    # None at this level: descend into each parenthesised group instead.
    out, i = "", 0
    while i < len(expr):
        if expr[i] == "(":
            d, j = 1, i
            while d:
                j += 1
                d += (expr[j] == "(") - (expr[j] == ")")
            out += f"({ternary(expr[i + 1:j])})"
            i = j + 1
        else:
            out += expr[i]
            i += 1
    return out


def js(expr):
    expr = expr.replace("?.", ".")
    expr = re.sub(r"!(?!=)", " not ", expr)
    return ternary(expr.replace("&&", " and ").replace("||", " or "))


# A spec stands for its own name, so the pick can be asserted by what it returns.
APPEARANCE = NS(animation=NS(elementMoveEnter="elementMoveEnter", elementMoveExit="elementMoveExit",
                             elementResize="elementResize"),
                sizes=NS(barHeight=40, verticalBarWidth=46))


# --- 1. auto-hide -------------------------------------------------------------

# (file, name, the two margins the reveal moves, the far-edge state, thickness token)
BARS = ((bar, "Bar.qml", ("anchors.topMargin", "anchors.bottomMargin"),
         "anchors.bottomMargin: barContent.edgeOffset", "barHeight"),
        (vbar, "VerticalBar.qml", ("anchors.leftMargin", "anchors.rightMargin"),
         "anchors.rightMargin: barContent.edgeOffset", "verticalBarWidth"))

for src, name, margins, far_edge, thickness in BARS:
    REVEALED = grab(src, r"readonly property bool revealed: (.*)",
                    f"{name} no longer derives `revealed`").group(1)
    OFFSET = block(src, r"readonly property real edgeOffset:", f"{name} no longer has `edgeOffset`")
    PICK = grab(OFFSET, r"barContent\.revealSpec = ([^;]+);",
                f"{name}: edgeOffset no longer picks the spec from inside its own binding (2.9)").group(1)
    RETURN = grab(OFFSET, r"return ([^;]+);", f"{name}: edgeOffset returns nothing").group(1)

    def autohide(enabled, hovering):
        env = {"Config": NS(options=NS(bar=NS(autoHide=NS(enable=enabled)))),
               "barRoot": NS(mustShow=hovering)}
        revealed = eval(js(REVEALED), env)
        env = {"barContent": NS(revealed=revealed), "Appearance": APPEARANCE}
        return revealed, eval(js(PICK), env), eval(js(RETURN), env)

    for hovering in (False, True):
        revealed, picked, offset = autohide(False, hovering)
        assert revealed and offset == 0, f"{name}: auto-hide off still parks the bar off its edge"
        assert picked == "elementMoveEnter", f"{name}: a bar that never hides picked {picked}"

    revealed, picked, offset = autohide(True, True)
    assert revealed and offset == 0 and picked == "elementMoveEnter", \
        f"{name} hovered: revealed={revealed} offset={offset} spec={picked} -- enter is the spatial spec"

    revealed, picked, offset = autohide(True, False)
    want = -getattr(APPEARANCE.sizes, thickness)
    assert not revealed and offset == want, \
        f"{name}: unhovered the bar sits at {offset}, not its own thickness ({want}) off its edge"
    assert picked == "elementMoveExit", \
        f"{name}: the bar leaves on {picked} -- 2.5 wants the accelerating exit, not the enter's curve"

    for prop in margins:
        blk = block(src, f"Behavior on {re.escape(prop)}", f"{name}: no Behavior on {prop}")
        assert "revealSpec.duration" in blk and "revealSpec.bezierCurve" in blk, \
            f"{name}: the Behavior on {prop} does not read revealSpec -- one of the two directions is fixed"
        assert "alwaysRunToEnd: false" in blk, \
            f"{name}: the Behavior on {prop} runs to the end -- a hover reversal cannot cut in (2.7)"
    assert far_edge in src, \
        f"{name}: the far-edge state no longer hides through edgeOffset, so it moves on its own terms"


# --- 2. a widget collapsing out of the row ------------------------------------

IW = grab(block(comp, r"implicitWidth:", "BarComponent no longer computes implicitWidth"),
          r"return ([^;]+);", "implicitWidth returns nothing").group(1)
IH = grab(block(comp, r"implicitHeight:", "BarComponent no longer computes implicitHeight"),
          r"return ([^;]+);", "implicitHeight returns nothing").group(1)
VISIBLE = grab(comp, r"\n    visible: (.*)", "BarComponent no longer derives `visible`").group(1)
CLIP = grab(comp, r"\n    clip: (.*)", "BarComponent no longer derives `clip`").group(1)
SIZE_PICK = grab(comp, r"rootItem\.sizeSpec = ([^;]+);",
                 "BarComponent no longer picks a size spec (2.9)").group(1)

NATURAL_W, NATURAL_H = 120, 40


def widget(shown, vertical, mid_w=None, mid_h=None):
    """One delegate, at rest or `mid_*` of the way through its collapse."""
    wrapper = NS(implicitWidth=NATURAL_W, implicitHeight=NATURAL_H)
    root = NS(shown=shown, vertical=vertical)
    env = {"rootItem": root, "wrapper": wrapper, "Appearance": APPEARANCE}
    root.implicitWidth = eval(js(IW), env) if mid_w is None else mid_w
    root.implicitHeight = eval(js(IH), env) if mid_h is None else mid_h
    return NS(w=root.implicitWidth, h=root.implicitHeight, visible=eval(js(VISIBLE), env),
              clip=eval(js(CLIP), env), spec=eval(js(SIZE_PICK), env))


at_rest = widget(True, False)
assert (at_rest.w, at_rest.h) == (NATURAL_W, NATURAL_H) and at_rest.visible and not at_rest.clip, \
    f"a shown widget is not its own size: {at_rest}"
assert at_rest.spec == "elementResize", f"a widget resizes on {at_rest.spec}, not fast spatial"

gone = widget(False, False)
assert gone.w == 0 and gone.h == NATURAL_H, \
    f"hiding collapsed the cross axis too ({gone.w}x{gone.h}) -- the strip's height would animate"
assert not gone.visible, "a finished collapse still holds the row's spacing open"
assert gone.spec == "elementMoveExit", f"a widget leaves on {gone.spec}, not the accelerating exit"

going = widget(False, False, mid_w=NATURAL_W / 2)
assert going.visible, \
    "a widget mid-collapse is already invisible -- the layout drops it and the exit never renders"
assert going.clip, "a widget mid-collapse does not clip, so its content spills over its neighbours"

vgone = widget(False, True, mid_h=NATURAL_H / 2)
assert vgone.w == NATURAL_W, f"the vertical bar collapsed width too ({vgone.w})"
assert vgone.visible and vgone.clip, f"the vertical collapse does not render: {vgone}"

for prop, guard in (("implicitWidth", "!rootItem.vertical"), ("implicitHeight", "rootItem.vertical")):
    blk = block(comp, f"Behavior on {prop}", f"no Behavior on {prop}")
    assert "SizeAnim" in blk, f"the Behavior on {prop} does not use the tokenised animation"
    enabled = grab(blk, r"enabled: (.*)", f"the Behavior on {prop} is not gated at all").group(1)
    assert enabled.strip() == guard, \
        f"the Behavior on {prop} is gated on {enabled.strip()}, not {guard} -- wrong axis"

anim = block(comp, r"component SizeAnim: NumberAnimation", "SizeAnim is gone")
assert "sizeSpec.duration" in anim and "sizeSpec.bezierCurve" in anim, \
    "SizeAnim no longer reads sizeSpec, so both directions run on one spec"
assert "alwaysRunToEnd: false" in anim, \
    "SizeAnim runs to the end -- a widget that comes back mid-collapse cannot cut in (2.7)"

print(f"ok: both bars reveal on {ENTER_CURVE} in {ENTER_MS}ms and hide on {EXIT_CURVE} in "
      f"{EXIT_MS}ms, and a widget collapsing out of the row stays visible to do it")
