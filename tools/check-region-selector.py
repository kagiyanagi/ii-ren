#!/usr/bin/env python3
"""The region selector takes what was selected and nothing else, and it leaves visibly.

Most of what `modules/ii/regionSelector/` got wrong had no symptom on screen, and a
screenshot of the selector looks right under every failure below:

- **An empty selection ran anyway.** `snip()` warned about a zero-sized region,
  dismissed, and carried on: there was no `return`. A probe showed that the rest of
  the function keeps running after the Loader destroys the window, and that its
  `execDetached` fires. magick reads `-crop 0x0+X+Y` as "from here to the corner",
  so a right-click on bare desktop opened the annotator on that crop. In OCR and QR
  mode the empty click read it, and in Search mode it uploaded it to a public host.
  Only the default left-click copy escaped, because its preview handler died with
  the window. The clamp is lifted and swept here, as is the screen clamp: it slid a
  padded window target back onto the screen instead of intersecting it, which
  captured a strip of whatever was beside it.

- **Clicks versus drags, and what a click can take.** A click was exact equality
  of press and release, so a tap that wobbled a pixel became a 1x1 crop instead of
  the window under it. The target lookup also ignored the config: in circle mode,
  and with `targetRegions.layers` off (the default), invisible layers and windows
  still caught clicks. Invisible layers still knocked every window they overlap out
  of the list; on the machine this was written on, a 1x1 helper surface in the
  corner was enough to make a fullscreen window unclickable.

- **The exit.** `Loader.active` was bound straight to the request, so the window
  was destroyed on the frame it was dismissed and nothing could ever fade out. The
  request and the surface are kept apart now. This also asserts that the window
  goes passive for the fade (a click during it would snip again), and that the
  signal releasing it is not called `closed`: that name clashes with QsWindow's own
  signal, which qml.invalidOverride reports on load and nothing else does.

- **Cost and types.** A screen-sized `layer.enabled` under a `CurveRenderer` shape
  that antialiases itself. A `Canvas` outline that re-uploaded a selection-sized
  texture on every pointer move. An infinite pulse repainting a full-screen overlay
  for the length of every recording. `contentRegionOpacity` declared `bool`, which
  turned the config's 0.8 into fully opaque. Two `Synchronizer`s that logged a
  binding loop on every open.

    python3 tools/check-region-selector.py [shell-dir]

The optional argument points it at another tree: every assertion fires against
the code this row replaced (`git archive` it into a temp dir).
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "dots/.config/quickshell/ii"
DIR = SHELL / "modules/ii/regionSelector"
SELECTOR = DIR / "RegionSelector.qml"
SELECTION = DIR / "RegionSelection.qml"
RECT = DIR / "RectCornersSelectionDetails.qml"
CIRCLE = DIR / "CircleSelectionDetails.qml"
PREVIEW = DIR / "ScreenshotPreviewPopup.qml"
TOOLBAR = DIR / "OptionsToolbar.qml"


def code(path):
    """The file with `//` comments stripped: these assertions are about what the
    QML does, and most of them are also described in a comment next to the
    thing they guard."""
    return re.sub(r"//[^\n]*", "", path.read_text())


def block(src, opener):
    """The brace-balanced body that follows `opener`."""
    start = src.find(opener)
    assert start >= 0, f"{opener!r} is gone -- this check is stale"
    i = src.index("{", start)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i + 1:j]
    raise AssertionError(f"unbalanced braces after {opener!r}")


def js(text, names):
    """The subset of JS the lifted expressions are written in, as Python."""
    for a, b in names:
        text = text.replace(a, b)
    text = text.replace("Math.max(", "max(").replace("Math.min(", "min(")
    text = text.replace("||", " or ").replace("&&", " and ")
    if "?" in text:
        cond, rest = text.split("?", 1)
        then, alt = rest.rsplit(":", 1)
        text = f"(({then}) if ({cond}) else ({alt}))"
    return text


def check_empty_selection_does_nothing():
    src = code(SELECTION)
    body = block(src, "function snip(")
    guard = re.search(r"if\s*\(([^)]*<=\s*0[^)]*)\)\s*return\s*;", body)
    assert guard, ("snip() has no early return on an empty region -- a click on nothing "
                   "hands magick a zero size, which it reads as \"to the corner\"")
    first_write = re.search(r"root\.region(X|Y|Width|Height)\s*=", body)
    assert first_write and first_write.start() > guard.end(), \
        "snip() writes the region before refusing it, freezing the bindings the next drag needs"
    assert "dismiss()" not in body[:guard.end()], "an empty selection still closes the selector"

    # The clamp and the guard, lifted and evaluated.
    names = [("root.screen.width", "W"), ("root.screen.height", "H")]
    clamp = {}
    for name in ("x1", "y1", "w", "h"):
        m = re.search(rf"const {name}\s*=\s*([^;]+);", body)
        assert m, f"snip() no longer computes {name} -- this check is stale"
        clamp[name] = js(m.group(1), names)
    refuse = js(guard.group(1), names)

    def run(x, y, width, height, W=1920, H=1080):
        env = {"x": x, "y": y, "width": width, "height": height, "W": W, "H": H}
        for name in ("x1", "y1", "w", "h"):
            env[name] = eval(clamp[name], {}, env)
        return None if eval(refuse, {}, env) else (env["x1"], env["y1"], env["w"], env["h"])

    # Nothing selected: a click that hit no target keeps its zero-sized region.
    for x, y in ((1701, 701), (0, 0), (1919, 1079)):
        assert run(x, y, 0, 0) is None, f"a click at {(x, y)} on nothing still snips"
    assert run(400, 300, 250, 0) is None, "a drag along one axis snips a zero-height strip"
    assert run(-300, 100, 200, 50) is None, "a region wholly off screen snips something"

    # Inside the screen: untouched.
    assert run(100, 200, 300, 400) == (100, 200, 300, 400), "an on-screen region was altered"

    # A padded target hanging off an edge is cut to the screen, never slid back in.
    # A window at x = -100, 500 wide, padding 5: the visible part is x 0..395.
    assert run(-105, 40, 510, 300) == (0, 40, 405, 300), \
        "a target hanging off the left edge was slid back in, taking a strip beside it"
    assert run(1700, 800, 400, 400) == (1700, 800, 220, 280), \
        "a target hanging off the bottom-right corner was not cut to the screen"
    print("ok  snip: an empty selection does nothing, and the screen clamp intersects")


def check_click_versus_drag():
    src = code(SELECTION)
    pressed = block(src, "onPressed: (mouse)")
    released = block(src, "onReleased:")
    moved = block(src, "onPositionChanged:")
    assert "Qt.styleHints.startDragDistance" in moved, \
        "click-versus-drag is exact equality again -- a one-pixel wobble becomes a 1x1 crop"
    assert re.search(r"root\.draggedAway\s*=\s*true", moved), "draggedAway is not latched on the threshold"
    for reset in (r"root\.draggedAway\s*=\s*false", r"root\.points\s*=\s*\[\]"):
        assert re.search(reset, pressed), \
            f"a press does not reset {reset!r} -- an empty click keeps the window, so it carries over"
    assert re.search(r"root\.dragging\s*=\s*false", released), \
        "dragging is never cleared -- after an empty click the next hover drags a region"
    click = re.search(r"if\s*\(\s*!root\.draggedAway\s*\)\s*\{(.*?)\n\s{16}\}", released, re.S)
    assert click, "the release handler no longer branches on draggedAway -- this check is stale"
    assert re.search(r"if\s*\(\s*!root\.targetedRegionValid\(\)\s*\)\s*return", click.group(1)), \
        "a click on no target is not a no-op"
    print("ok  press: Qt's drag threshold decides click from drag, and every press starts clean")


def intersection_over_union(a, b):
    """`RegionFunctions.intersectionOverUnion`, transcribed."""
    ax2, ay2 = a["at"][0] + a["size"][0], a["at"][1] + a["size"][1]
    bx2, by2 = b["at"][0] + b["size"][0], b["at"][1] + b["size"][1]
    inter = max(0, min(ax2, bx2) - max(a["at"][0], b["at"][0])) * max(0, min(ay2, by2) - max(a["at"][1], b["at"][1]))
    union = a["size"][0] * a["size"][1] + b["size"][0] * b["size"][1] - inter
    return inter / union if union > 0 else 0


def check_only_drawn_targets_are_taken():
    src = code(SELECTION)
    layers = block(src, "readonly property list<var> layerRegions:")
    assert re.match(r"\s*if\s*\(\s*!root\.enableLayerRegions\s*\)\s*return\s*\[\]", layers), \
        "layerRegions is computed while layers are off -- invisible layers catch clicks and hide windows"

    lookup = block(src, "function updateTargetedRegion(")
    assert re.search(r"root\.enableWindowRegions\s*\?\s*root\.windowRegions\.find", lookup), \
        "windows are targeted in circle mode, or with window targets switched off"
    assert re.search(r"root\.enableContentRegions\s*\?\s*root\.imageRegions\.find", lookup), \
        "content regions are targeted while switched off"

    # Why the layer gate matters beyond clicks: RegionFunctions drops every window
    # that overlaps any layer at all. The helper surface on the machine this was
    # written on, and a fullscreen window.
    helper = {"at": [1919, 1017], "size": [1, 1]}
    fullscreen = {"at": [0, 0], "size": [1920, 1080]}
    functions = (DIR / "RegionFunctions.qml").read_text()
    assert "intersectionOverUnion(windowRegion, layerRegions[i]) > 0" in functions, \
        "filterWindowRegionsByLayers changed -- re-derive why the layer gate matters"
    assert intersection_over_union(fullscreen, helper) > 0, "the premise of the layer gate moved"
    print("ok  targets: only what is drawn catches a click, and hidden layers hide no windows")


def check_exit_outlives_the_request():
    selector = code(SELECTOR)
    active = re.search(r"\n\s*active:\s*([^\n]+)", selector)
    assert active, "the per-screen Loader has no active binding"
    assert "regionSelectorOpen" not in active.group(1) and "wanted" not in active.group(1), \
        ("Loader.active is bound to the request again -- the window is destroyed on the "
         "frame it is dismissed and the fade out plays to nobody")
    wanted = block(selector, "onWantedChanged:")
    assert re.search(r"rendered\s*=\s*false;\s*regionSelectorLoader\.rendered\s*=\s*true", wanted), \
        ("a new request reuses the old instance -- `retrigger` stops a recording only "
         "because a fresh instance runs its own pidof check")
    assert re.search(r"onFadedOut:\s*regionSelectorLoader\.rendered\s*=\s*false", selector), \
        "nothing releases the Loader once the fade has played -- the window leaks"

    src = code(SELECTION)
    assert not re.search(r"signal\s+closed\s*\(", src), \
        "RegionSelection declares `closed`, which clashes with QsWindow's own signal"
    fade = block(src, "opacity:")
    assert re.search(r"content\.fadeSpec\s*=\s*root\.open\s*\?\s*Appearance\.animation\.elementMoveFast\s*:\s*Appearance\.animation\.elementMoveExit", fade), \
        ("the fade's spec is not assigned inside the binding that drives it -- the "
         "exit runs on the enter's curve (DESIGN.md 2.9)")
    assert re.search(r"onOpacityChanged:\s*if\s*\(content\.opacity === 0 && !root\.open\)\s*root\.fadedOut\(\)", src), \
        "the fade reaching 0 does not release the window"
    assert re.search(r"!root\.open\s*&&\s*\(!root\.visible\s*\|\|\s*content\.opacity === 0\)", src), \
        "a dismiss before the window was ever shown never releases it"
    for gate in (r"keyboardFocus:\s*root\.passive", r"mask:\s*root\.passive", r"enabled:\s*!root\.passive"):
        assert re.search(gate, src), f"the window is not passive while it fades ({gate})"
    assert re.search(r"readonly property bool passive:\s*root\.postPhase\s*\|\|\s*!root\.open", src), \
        "passive no longer covers both the recording border and the fade out"
    print("ok  exit: the window fades out passive, and is released by the fade, not the request")


def check_cost_and_types():
    circle = code(CIRCLE)
    assert "layer.enabled" not in circle, \
        "a screen-sized offscreen layer is back under a CurveRenderer shape that antialiases itself"
    rect = code(RECT)
    assert "DashedBorder" not in rect and "Canvas" not in rect, \
        "the selection outline is a Canvas again -- a selection-sized texture per pointer move"
    for path in DIR.glob("*.qml"):
        text = code(path)
        assert "Animation.Infinite" not in text, f"{path.name} runs an infinite animation"
        assert "Synchronizer" not in text, f"{path.name} uses a Synchronizer -- the binding loop is back"
    assert re.search(r"property real contentRegionOpacity:", code(SELECTION)), \
        "contentRegionOpacity is not a real -- 0.8 in the config reads as true, fully opaque"
    assert re.search(r"signal selectionModeRequested", code(TOOLBAR)), \
        "the toolbar writes the mode itself again instead of asking for it"
    print("ok  cost: no offscreen layer, no Canvas per drag frame, no pulse, no Synchronizer")


def check_size_label_stays_on_screen():
    src = code(RECT)
    label = block(src, "StyledText {")
    names = [("selectionBorder.height", "bh"), ("selectionBorder.width", "bw"),
             ("selectionBorder.x", "bx"), ("selectionBorder.y", "by"), ("root.height", "H")]
    exprs = {}
    for prop in ("below", "x", "y"):
        pattern = rf"readonly property real {prop}:\s*([^\n]+)" if prop == "below" else rf"\n\s*{prop}:\s*([^\n]+)"
        m = re.search(pattern, label)
        assert m, f"the size label has no {prop} -- this check is stale"
        # The label's own width and height, after the border's have been renamed.
        text = js(m.group(1), names).replace("width", "lw").replace("height", "lh")
        exprs[prop] = text.replace("gap", "8")
    W, H, lw, lh = 1920, 1080, 90, 20
    for bx, by, bw, bh in ((100, 100, 400, 300), (0, 0, 40, 30), (100, 700, 400, 380),
                           (0, 0, 1920, 1080), (1880, 1060, 40, 20), (300, 1000, 60, 80)):
        env = {"bx": bx - 2, "by": by - 2, "bw": bw + 4, "bh": bh + 4, "lw": lw, "lh": lh, "H": H}
        env["below"] = eval(exprs["below"], {}, env)
        x, y = eval(exprs["x"], {}, env), eval(exprs["y"], {}, env)
        assert 0 <= x and x + lw <= W and 0 <= y and y + lh <= H, \
            f"the size label for a region at {(bx, by, bw, bh)} lands off screen at {(x, y)}"
    print("ok  label: the size readout stays on screen at every edge")


def check_preview_card_motion():
    src = code(PREVIEW)
    x = block(src, "\n            x:")
    assert re.search(r"card\.slideSpec\s*=\s*previewPopup\.shown\s*\?\s*Appearance\.animation\.elementMoveEnter\s*:\s*Appearance\.animation\.elementMoveExit", x), \
        "the card leaves on the enter spec again (DESIGN.md 2.5), or the spec is read outside the x binding (2.9)"
    y = block(src, "Behavior on y")
    assert "elementMove." in y, "the dodge is not interruptible default spatial"
    assert re.search(r"SwipeToDismiss\s*\{[^}]*onDismissed:\s*previewPopup\.discard\(\)", src), \
        "the card cannot be swiped away like the other corner cards"
    card = block(src, "id: card")
    assert "transform:" not in card.split("id: body")[0], \
        "the masked card carries a transform -- the input region would freeze (check-mask-regions.py)"
    print("ok  preview: enters and leaves on two specs, dodges interruptibly, swipes away")


if __name__ == "__main__":
    check_empty_selection_does_nothing()
    check_click_versus_drag()
    check_only_drawn_targets_are_taken()
    check_exit_outlives_the_request()
    check_cost_and_types()
    check_size_label_stays_on_screen()
    check_preview_card_motion()
