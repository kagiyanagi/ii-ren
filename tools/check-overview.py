#!/usr/bin/env python3
"""Assert the overview leaves visibly, costs what it says, that deleting the
launcher's mask was licensed, and that the results list is built once per query.

Four concerns, none of which a still frame of the surface shows.

**The exit.** `Overview.qml` maps and unmaps its own layer surface from
`scaleAnimated`, the animated zoom -- not from `GlobalStates.overviewOpen`. Bind
`visible` to the request and the surface unmaps on the frame the flag clears, so
the close animation plays to nobody; the overview still disappears, which is what
it is supposed to do, so there is no symptom at all. Five other surfaces shipped
the same defect wearing `Loader.active`. The spec the zoom runs on is checked
too: it used to be `elementMoveFast` -- 200ms on the *effects* curve -- in both
directions, while the desktop plane behind it zooms on `elementMoveEnter`, so the
two halves of one gesture travelled over durations 2.5x apart. A scale is spatial
(DESIGN.md 2.1) and enter and exit are asymmetric (2.5), so this evaluates the real
durations out of `Appearance.qml` rather than trusting the token names.

**The cost.** `OverviewWindow.qml` is one offscreen pass per open window, inside a
`Repeater`. `check-effect-budget.py` cannot see it: that gate reads a `Repeater` or
`delegate:` block *inside one file*, and every overview window is its own file --
the same blind spot that hid three effects per dock icon. The pass stays, because
the rounding is the thumbnail's whole silhouette and `ClippingRectangle` is the same
two framebuffers rather than fewer. What this pins is that it stays at *one*, and
that `SearchWidget.qml` does not grow one back.

**The mask that went.** The launcher card used to carry `layer.enabled` + an
`OpacityMask` whose mask rect was `width x width` -- square, stretched over a card
that is always taller than it is wide. It was also masking nothing, and that is the
licence for deleting it rather than fixing it: every `SearchItem` is inset
`horizontalMargin` from the card edge and the list ends a layout margin above it, so no
delegate pixel reaches the corner arc. That is arithmetic over four numbers in three
files, and if any of them shrinks the delegates start clipping with no gate and no
mask. It is evaluated here, at both the collapsed radius (which Qt clamps) and the
expanded one.

**The rebuilds.** The launcher's `model:` is a plain JS array, so assigning it
destroys every delegate and builds them all again -- QQmlDelegateModel::setModel
emits a remove of the old count and an insert of the new one. The rows come back
saying the same thing in the same places, so nothing about a rebuild is visible;
the motion the shared list hangs off those two signals is, and so is the highlight,
which the new current row fades in from nothing. Typing `fire` used to cost seven,
of which three landed after the list had settled: a 200ms debounce handing over the
full set it had already sliced, and `qalc`, which answers every string (`fire` is 0,
`firefox` is 0 B) and reports that it did not understand only in its exit code. The
three causes and the alignment of the row's action buttons -- off centre by the
button's own vertical padding, first one way and then the other -- are pinned here.

Run: python3 tools/check-overview.py
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
OVERVIEW = ROOT / "modules/ii/overview"

overview = (OVERVIEW / "Overview.qml").read_text()
window = (OVERVIEW / "OverviewWindow.qml").read_text()
widget = (OVERVIEW / "OverviewWidget.qml").read_text()
search_widget = (OVERVIEW / "SearchWidget.qml").read_text()
search_bar = (OVERVIEW / "SearchBar.qml").read_text()
search_item = (OVERVIEW / "SearchItem.qml").read_text()
appearance = (ROOT / "modules/common/Appearance.qml").read_text()


def one(src: str, pattern: str, what: str) -> str:
    m = re.search(pattern, src)
    assert m, f"{what} no longer matches {pattern!r} -- this check is stale"
    return m.group(1).strip()


def block(src: str, header: str) -> str:
    """The braced body that follows `header`, matched by depth."""
    i = src.index(header)
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return src[j:k + 1]
        k += 1
    raise AssertionError(f"unbalanced braces after {header!r}")


def spec_duration(name: str) -> int:
    """The real duration of an Appearance.animation.<name>, through its curve name."""
    body = block(appearance, f"property AnimSpec {name}:")
    curve = one(body, r"duration: root\.animationCurves\.(\w+)", f"{name}'s duration")
    return int(one(appearance, rf"property real {curve}: (\d+)", curve))


def spec_curve(name: str) -> str:
    body = block(appearance, f"property AnimSpec {name}:")
    return one(body, r"bezierCurve: root\.animationCurves\.(\w+)", f"{name}'s curve")


# --- the exit ----------------------------------------------------------------

visible = block(overview, "visible: {")
assert "scaleAnimated" in visible, \
    "the overview's `visible` no longer reads `scaleAnimated` -- bound to the open request " \
    "instead, the layer unmaps on the frame the flag clears and the exit plays to nobody"

# The one legitimate direct read is the `showOpeningAnimation: false` branch, which
# is the opt-out from animating at all. Anything else means the request is driving
# the surface again.
open_reads = re.findall(r"GlobalStates\.overviewOpen", visible)
assert len(open_reads) == 1, \
    f"`visible` reads GlobalStates.overviewOpen {len(open_reads)}x -- only the " \
    "`!showOpeningAnimation` opt-out may, or the animated branch is bypassed"

zoom = block(overview, "property real scaleAnimated:")
enter_spec = one(zoom, r"overviewOpen \? Appearance\.animation\.(\w+)", "the zoom's enter spec")
exit_spec = one(zoom, r"overviewOpen \? Appearance\.animation\.\w+ : Appearance\.animation\.(\w+)",
                "the zoom's exit spec")

assert "spatial" in spec_curve(enter_spec.replace("Appearance.animation.", "")).lower(), \
    f"the overview's enter runs on {enter_spec}, whose curve is " \
    f"{spec_curve(enter_spec)} -- a scale is spatial (2.1), not an effects curve"

enter_ms, exit_ms = spec_duration(enter_spec), spec_duration(exit_spec)
assert exit_ms < enter_ms, \
    f"the overview's exit ({exit_spec}, {exit_ms}ms) is not shorter than its enter " \
    f"({enter_spec}, {enter_ms}ms) -- leaving would read as entering played backwards (2.5)"

# In register with the desktop plane behind it, which is the whole point of the
# retime: `ii-background-root` left this here because it could not drive the overview.
desktop = (ROOT / "modules/ii/background/Background.qml").read_text()
assert f"Appearance.animation.{enter_spec}" in desktop, \
    f"the desktop plane no longer animates on {enter_spec} -- the overview's zoom and the " \
    "wallpaper zoom behind it are two halves of one gesture and have to share a spec"

# The Behavior has to be interruptible: it drives `visible`, so a close that waits out
# a 500ms enter leaves the surface mapped and holding keyboard focus for that long.
zoom_behavior = block(overview, "Behavior on scaleAnimated")
assert "alwaysRunToEnd: false" in zoom_behavior, \
    "the zoom Behavior runs to end -- a close during the open is held off for the " \
    f"enter's full {enter_ms}ms, with the layer mapped and grabbing the keyboard"
assert "root.zoomSpec" in zoom_behavior, \
    "the zoom Behavior no longer reads `zoomSpec` -- the enter/exit swap has no effect"


# --- the cost ----------------------------------------------------------------

EFFECTS = (r"layer\.enabled\s*:\s*true", r"\bMultiEffect\b", r"\bOpacityMask\b",
           r"\bShaderEffect\b", r"\bStyledRectangularShadow\b", r"\bStyledDropShadow\b",
           r"\bClippingRectangle\b", r"\bCanvas\b", r"\bColorOverlay\b", r"\bDesaturate\b")


def uncommented(src: str) -> str:
    """Line comments stripped -- these files *name* the effects they do not use."""
    return "\n".join(re.sub(r"//.*", "", line) for line in src.splitlines())


def effect_passes(src: str) -> list:
    """`layer.enabled` and its `layer.effect` are one pass pair, counted once."""
    src = uncommented(src)
    hits = [p for p in EFFECTS if re.search(p, src)]
    if r"layer\.enabled\s*:\s*true" in hits and r"\bOpacityMask\b" in hits:
        hits.remove(r"\bOpacityMask\b")
    return hits


win_effects = effect_passes(window)
assert len(win_effects) <= 1, \
    f"OverviewWindow.qml carries {len(win_effects)} effects ({win_effects}) -- it is a " \
    "Repeater delegate rendered once per open window, and check-effect-budget.py " \
    "cannot see it because the delegate is its own file. The ceiling is one"

# The card's one StyledRectangularShadow is allowed -- one per widget, not repeated.
# What must not come back is an offscreen pass to round corners nothing reaches.
MASKS = (r"layer\.enabled\s*:\s*true", r"\bOpacityMask\b", r"\bClippingRectangle\b",
         r"\bShaderEffect\b", r"\bMultiEffect\b")
regrown = [p for p in MASKS if re.search(p, uncommented(search_widget))]
assert regrown == [], \
    f"SearchWidget.qml grew a masking pass back ({regrown}). Its OpacityMask was deleted, " \
    "not moved -- see the arithmetic below for why nothing in the card needs masking"
assert "StyledRectangularShadow" in uncommented(search_widget), \
    "the launcher card lost its shadow -- it floats over the desktop with nothing behind it"


# --- the mask that went ------------------------------------------------------

def token(name: str) -> int:
    return int(one(appearance, rf"property int {name}: (\d+) \* scale", f"rounding.{name}"))


card_radius_token = one(search_widget, r"radius: Appearance\.rounding\.(\w+)", "the launcher card radius")
r_expanded = token(card_radius_token)

# Collapsed, the card is the bar plus its padding, and Qt clamps radius to half the
# short side -- so the arc is tighter than the token and the check has to use both.
bar_height = int(one(search_bar, r"implicitHeight: (\d+)", "the search field height"))
bar_margins = int(one(search_bar, r"Layout\.topMargin: (\d+)", "the field's top margin")) * 2
padding = int(one(search_widget, r"property real verticalPadding: (\d+)", "the bar's vertical padding")) * 2
collapsed_h = bar_height + bar_margins + padding
r_collapsed = min(r_expanded, collapsed_h / 2)

inset = int(one(search_item, r"property int horizontalMargin: (\d+)", "the result row's inset"))
# Layout space, not ListView's scroll `bottomMargin`: that one only pads the end of
# the content, so mid-scroll a row still drew to the card's edge and poked out.
assert not re.search(r"^\s*bottomMargin:", uncommented(search_widget), re.M), \
    "the results list's bottom gap is a scroll margin again -- it only pads the end of the " \
    "content, so mid-scroll a hovered row reaches the card's corner arc. Use Layout.bottomMargin"
list_gap = int(one(search_widget, r"Layout\.bottomMargin: (\d+)", "the results list's bottom margin"))


def inside_corner(x: float, y: float, r: float) -> float:
    """How far a point sits inside the corner arc. Negative = it pokes out."""
    if x >= r or y >= r:
        return r  # past the quarter-circle entirely, nothing to clip
    return r - math.hypot(r - x, r - y)


for label, r in (("collapsed", r_collapsed), ("expanded", r_expanded)):
    slack = inside_corner(inset, list_gap, r)
    assert slack >= 0, (
        f"a result row reaches the launcher card's {label} corner arc by {-slack:.1f}px "
        f"(inset {inset}, list margin {list_gap}, radius {r}). The OpacityMask that used to "
        "cover this is gone and nothing replaced it -- either restore the inset or clip again")

# The bar's trailing control may overhang the arc, because it paints a round
# MaterialShape inside its box rather than filling it. That licence is bounded by
# the control's own corner: a square one at these numbers would clip.
btn_margin = int(one(block(search_bar, "IconToolbarButton {\n        id: songRecButton"),
                     r"Layout\.rightMargin: (\d+)", "the trailing button's margin"))
bar_margin = int(one(search_widget, r"Layout\.rightMargin: (\d+)", "the search bar's right margin"))
corner = btn_margin + bar_margin
overhang = -inside_corner(corner, corner, r_collapsed)
assert overhang < bar_height / 2, (
    f"the bar's trailing control overhangs the card's corner arc by {overhang:.1f}px, which is "
    f"past its own {bar_height / 2:.0f}px corner rounding -- its painted pixels now clip")


# --- four states on a workspace tile -----------------------------------------

assert "StateOverlay" in widget, \
    "the workspace tile lost its StateOverlay -- it is clickable, so it needs all four " \
    "states (6), and it used to have only a hand-mixed drag film"
overlay = block(widget, "StateOverlay {")
for state in ("hover:", "press:", "drag:"):
    assert state in overlay, \
        f"the workspace tile's StateOverlay does not bind `{state}` -- that state is dead"
assert "hoverEnabled: true" in block(widget, "MouseArea {\n                                id: workspaceArea"), \
    "the workspace MouseArea stopped tracking hover -- `containsMouse` is then always false " \
    "and the hover film can never appear"

# --- the results list rebuilds once per query, not four times ----------------
#
# `model:` here is a plain JS array, and QQmlDelegateModel::setModel emits a remove
# of the old count followed by an insert of the new one -- so *assigning* it
# destroys every delegate and builds them all again. A still frame shows none of
# that: the rows come back with the same text in the same places. What shows is the
# motion the shared list hangs off those two signals, and the highlight, which the
# new current row has to fade in from nothing because it is created before the
# index is put back. Measured on the shipped launcher, typing `fire` cost seven
# rebuilds where four were real -- one per keystroke -- and the three spare ones
# landed *after* the list had settled, each dipping the green off the current row
# to (45,50,37) for about 240ms. Their three causes are pinned here.

launcher = (ROOT / "services/LauncherSearch.qml").read_text()

# qalc answers every string -- `fire` is 0, `firefox` is 0 B, `code` is code() --
# and says whether it understood one only in its exit code. Reading stdout as it
# streams takes the answer regardless, which puts a Math result row under every
# ordinary app search and, because qalc lands a quarter second behind the rows,
# rewrites the model once more just after the list has settled.
math_proc = block(launcher, "Process {\n        id: mathProc")
assert "SplitParser" not in math_proc, \
    "mathProc reads qalc as it streams again -- stdout alone cannot say whether qalc " \
    "understood the query, so every app search grows a junk Math result row and the " \
    "whole list rebuilds a second time when it arrives"
exited = block(math_proc, "onExited:")
assert "exitCode === 0" in exited and "mathResult" in exited, \
    "mathProc no longer gates the math result on qalc's exit code -- `qalc -t firefox` " \
    "exits 1 and prints `0 B`, and that is what the surface would show"

pushes = list(re.finditer(r"result\.push\(mathResultObject\)", launcher))
assert len(pushes) == 2, \
    f"the math row is pushed from {len(pushes)} places, not 2 -- this check is stale"
for m in pushes:
    assert "hasMathResult" in launcher[m.start() - 200:m.start()], \
        "a math row is pushed without checking there is a result -- an empty row under " \
        "every search, which then rewrites itself and rebuilds the model"

# The list is handed its model once per results change. The second assignment was a
# 200ms debounce handing over the full set after a 15-item slice, which bought
# nothing -- a ListView instantiates what fits its viewport, about 11 rows here,
# whether `count` is 15 or 57.
assigns = re.findall(r"root\.currentResults =", search_widget)
assert len(assigns) == 1, \
    f"`currentResults` is assigned {len(assigns)}x per results change -- every assignment " \
    "destroys and rebuilds every delegate, and a second one carrying content the first " \
    "already carried is a flash with nothing behind it"

results_list = block(search_widget, "StyledListView { // App results")
assert "animateAppearance: false" in results_list, \
    "the launcher results list animates its rows in and out again -- its model is " \
    "replaced wholesale rather than added to, so that slid every row off to the right " \
    "and scaled every row back in from zero on each keystroke"


# --- the action buttons sit on the row --------------------------------------

# The row layout fills a button that is two vertical paddings taller than the
# layout's own content, so a child that does not centre is pinned that far off the
# name and the verb beside it. This started as a top margin paid for with a
# negative bottom one (11) -- which put the buttons below centre -- and pinning
# them to the top instead moved them the same distance the other way.
actions = block(search_item, "RowLayout {\n            Layout.alignment:")
assert "(root.entry.actions ?? [])" in actions, \
    "the action row is not where this check thinks it is -- stale"
pad = int(one(search_item, r"property int buttonVerticalPadding: (\d+)", "the row's vertical padding"))
align = one(actions, r"Layout\.alignment: (Qt\.\w+)", "the action row's alignment")
assert align == "Qt.AlignVCenter", \
    f"the search result's action buttons are aligned {align}, which puts them {pad}px off " \
    "the centre of a row whose name and verb are centred on it"
assert "Margin: -" not in actions, \
    "a negative margin is back on the action row (11) -- it cancels height rather than " \
    "moving anything, and leaves the buttons off centre by what it cancelled"


print(f"ok: overview exits on {exit_spec} ({exit_ms}ms) after entering on {enter_spec} "
      f"({enter_ms}ms), 1 effect per window delegate, launcher rows clear the "
      f"{r_collapsed:.0f}/{r_expanded}px corner by {inside_corner(inset, list_gap, r_collapsed):.1f}px, "
      f"results rebuild once per query")
sys.exit(0)
