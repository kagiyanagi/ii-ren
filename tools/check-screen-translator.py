#!/usr/bin/env python3
"""The screen translator leaves visibly, stays on the screen it froze, and
reveals every box at once.

None of what `modules/ii/screenTranslator/` got wrong shows in a screenshot:

- **The exit.** The Scope's `Loader.active` went false on the frame the request
  cleared, so the surface was destroyed with nothing played. The request and the
  surface are kept apart now: the panel fades out on `elementMoveExit`, passive,
  and releases the Loader itself. Its signal is not `closed`, which QsWindow
  already declares and only the reload log says so.

- **Pan and zoom.** Zoom went down to 0.1 and a drag could pull the frozen frame
  off any edge, both of which show the window around it -- and the window was
  painted black. A wheel event zoomed 10% whatever its delta, so a touchpad's
  stream of small deltas went from 1x to 5x in one flick. The arithmetic is
  lifted out of the QML and swept here.

- **The reveal.** Each box's colour came from its own process (a magick decode
  and a Python start with cv2), all at once and after the boxes were on screen:
  30 boxes held all 8 cores for 1.7s and every box changed colour as its answer
  landed. It is one process now, and nothing is drawn until the translations and
  the colours are both in. That ordering, and the filter that builds delegates
  only for real translations, are evaluated here. So is the batched script. The
  box is opaque: at 60% over a masked blur, the blurred glyphs showed wherever the
  translation ran shorter than its source, and the blur was the surface's only
  offscreen cost.

- **The scrim** faded on a spatial spec, which overshoots, so its opacity
  clipped (DESIGN.md rule 3). And the panel claimed the region selector's layer
  namespace, so its rules and anything looking for it found the translator too.

    python3 tools/check-screen-translator.py [dots-dir]

The optional argument points it at another `dots/` (a `git archive` of the old
tree fails every check).
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOTS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "dots"
SHELL = DOTS / ".config/quickshell/ii"
DIR = SHELL / "modules/ii/screenTranslator"
SCOPE = DIR / "ScreenTranslator.qml"
PANEL = DIR / "ScreenTranslatorPanel.qml"
OVERLAY = DIR / "ScreenTextOverlay.qml"
RULES = DOTS / ".config/hypr/hyprland/rules.lua"
TEXT_COLOR = SHELL / "scripts/images/text_color.py"


def code(path):
    """The file with `//` comments stripped: these are about what the QML does."""
    return re.sub(r"(?<![:\\])//[^\n]*", "", path.read_text())


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


def node(script):
    out = subprocess.run(["node", "-e", script], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def check_exit():
    scope = code(SCOPE)
    loader = block(scope, "Loader {")
    assert re.search(r"\n\s*active:\s*false\b", loader), \
        "the Loader's `active` is bound -- to the request, it destroys the surface before its fade out"
    handler = block(loader, "function onScreenTranslatorOpenChanged()")
    assert re.search(r"if\s*\(\s*!GlobalStates\.screenTranslatorOpen\s*\|\|\s*translatorLoader\.active\s*\)\s*return", handler), \
        "a reopen during the fade out rebuilds the panel instead of reversing its fade"
    assert "translatorLoader.active = false" not in handler, "the request clearing still destroys the panel"
    assert re.search(r"onFadedOut:\s*translatorLoader\.active\s*=\s*false", loader), \
        "nothing releases the Loader once the panel has faded"
    assert re.search(r"open:\s*GlobalStates\.screenTranslatorOpen", loader), "the panel is not told the request"

    panel = code(PANEL)
    assert re.search(r"signal fadedOut\b", panel) and not re.search(r"signal closed\b", panel), \
        "the release signal must not be `closed`: QsWindow already has one"
    assert re.search(r'\n    color:\s*"transparent"', panel), "the window is not transparent -- a fade shows its colour at once"
    content = panel[panel.index("id: content"):]
    fade = re.search(r"opacity:\s*\{([^}]*)\}", content)
    assert fade, "the content fade is gone -- this check is stale"
    assert re.search(r"content\.fadeSpec\s*=\s*root\.open\s*\?\s*Appearance\.animation\.elementMoveFast\s*:\s*Appearance\.animation\.elementMoveExit",
                     fade.group(1)), "the fade's spec is not chosen inside the binding that drives it (DESIGN.md 2.9)"
    assert re.search(r"onOpacityChanged:\s*if\s*\(content\.opacity === 0 && !root\.open\)\s*root\.fadedOut\(\)", content), \
        "the fade out reaching 0 does not release the window"
    assert re.search(r"mask:\s*root\.open\s*\?\s*null\s*:\s*passthroughRegion", panel) and \
        re.search(r"keyboardFocus:\s*root\.open\s*\?\s*WlrKeyboardFocus\.OnDemand\s*:\s*WlrKeyboardFocus\.None", panel), \
        "the window still takes input while it fades out"
    print("ok  exit: latched, faded out on elementMoveExit, passive while it goes")


def check_namespace():
    panel = code(PANEL)
    m = re.search(r'WlrLayershell\.namespace:\s*"([^"]+)"', panel)
    assert m and m.group(1) == "quickshell:screenTranslator", \
        f"the panel's namespace is {m and m.group(1)!r} -- the region selector's rules and tools find it"
    rules = [r for r in re.findall(r'hl\.layer_rule\(\{\s*match = \{ namespace = "([^"]+)" \}, no_anim = true\}\)', RULES.read_text())]
    assert any(re.fullmatch(r, "quickshell:screenTranslator") for r in rules), \
        "no no_anim rule for quickshell:screenTranslator: Hyprland's popin scales the whole surface on top of its fade"
    assert any(re.fullmatch(r, "quickshell:regionSelector") for r in rules), "the region selector lost its no_anim rule"
    print("ok  namespace: its own, with a no_anim rule")


def check_pan_and_zoom():
    panel = code(PANEL)
    place = block(panel, "function place(x, y, zoom)")
    wheel = block(panel, "onWheel: event =>")
    drag = block(panel, "onPositionChanged: mouse =>")
    assert re.search(r"root\.place\(root\.contentX \+ mouse\.x - lastX, root\.contentY \+ mouse\.y - lastY, root\.zoom\)", drag), \
        "a drag no longer goes through place(), so nothing keeps the frame on screen"
    res = node(f"""
        const W = 1920, H = 1080;
        const root = {{ width: W, height: H, zoom: 1, contentX: 0, contentY: 0 }};
        const placeFn = new Function("x", "y", "zoom", "root", {json.dumps(place)});
        root.place = (x, y, zoom) => placeFn(x, y, zoom, root);
        const wheel = new Function("event", "root", {json.dumps(wheel)});
        const w = (x, y, dy, dx = 0) => wheel({{ x, y, angleDelta: {{ x: dx, y: dy }} }}, root);
        const out = {{ bad: [] }};
        const inside = (tag) => {{
            if (!(root.zoom >= 1 && root.zoom <= 5)) out.bad.push(tag + " zoom " + root.zoom);
            if (!(root.contentX <= 0 && root.contentX >= W * (1 - root.zoom) - 1e-9)) out.bad.push(tag + " x " + root.contentX);
            if (!(root.contentY <= 0 && root.contentY >= H * (1 - root.zoom) - 1e-9)) out.bad.push(tag + " y " + root.contentY);
        }};
        // Zooming in keeps the point under the cursor where it is.
        w(700, 400, 120);
        out.fixed = [(700 - root.contentX) / root.zoom, (400 - root.contentY) / root.zoom];
        out.notch = root.zoom;
        // A touchpad: eight deltas of 15 are one notch.
        Object.assign(root, {{ zoom: 1, contentX: 0, contentY: 0 }});
        for (let i = 0; i < 8; i++) w(700, 400, 15);
        out.touchpad = root.zoom;
        // A horizontal scroll zooms nothing.
        w(700, 400, 0, 120);
        out.horizontal = root.zoom;
        // A seeded sweep of wheel turns and drags, anywhere, including off the screen.
        let s = 7;
        const rnd = () => (s = (s * 16807) % 2147483647) / 2147483647;
        Object.assign(root, {{ zoom: 1, contentX: 0, contentY: 0 }});
        for (let i = 0; i < 20000; i++) {{
            if (rnd() < 0.5) w(rnd() * W, rnd() * H, (rnd() - 0.5) * 2400);
            else root.place(root.contentX + (rnd() - 0.5) * 4 * W, root.contentY + (rnd() - 0.5) * 4 * H, root.zoom);
            inside("step " + i);
        }}
        // Out as far as it goes, from anywhere, and the frame is the screen again.
        for (let i = 0; i < 50; i++) w(rnd() * W, rnd() * H, -1200);
        out.home = [root.zoom, root.contentX, root.contentY];
        out.bad = out.bad.slice(0, 3);
        console.log(JSON.stringify(out));
    """)
    assert not res["bad"], f"the frozen frame left the screen or the zoom its range: {res['bad']}"
    assert abs(res["fixed"][0] - 700) < 1e-6 and abs(res["fixed"][1] - 400) < 1e-6, \
        f"zooming in moved the point under the cursor to {res['fixed']}"
    assert abs(res["notch"] - 1.1) < 1e-9, f"a wheel notch zooms to {res['notch']}, not 1.1"
    assert abs(res["touchpad"] - res["notch"]) < 1e-9, \
        f"eight touchpad deltas of 15 zoom to {res['touchpad']:.3f}, one notch of 120 to {res['notch']}"
    assert res["horizontal"] == res["touchpad"], "a horizontal scroll changed the zoom"
    assert res["home"] == [1, 0, 0], f"zoomed all the way out the frame sits at {res['home']}"
    print("ok  pan/zoom: 1x to 5x, never off the screen, by the wheel's delta")


def check_reveal():
    overlay = code(OVERLAY)
    finish = block(overlay, "function finish()")
    # Up to its own closing brace: its regexes hold a `{` that block() would count.
    real = re.search(r"function isRealTranslation\(source: string, translated: string\): bool \{([\s\S]*?)\n    \}", overlay)
    assert real, "isRealTranslation() is gone -- this check is stale"
    real = real.group(1)
    empty = re.search(r"readonly property bool empty:\s*([^\n]+)", overlay)
    assert empty, "`empty` is gone -- this check is stale"
    res = node(f"""
        const isReal = new Function("source", "translated", {json.dumps(real)});
        const finishFn = new Function("root", {json.dumps(finish)});
        const box = (x) => ({{ boundingBox: {{ vertices: [{{x, y: 0}}, {{x: x + 10, y: 0}}, {{x: x + 10, y: 10}}, {{x, y: 10}}] }} }});
        const make = () => ({{
            paragraphs: [{{ text: "今日は", ...box(0) }}, {{ text: "Already English.", ...box(20) }}, {{ text: "駅", ...box(40) }}],
            translations: null, colours: null, boxes: [], loading: true, isRealTranslation: isReal,
        }});
        const emptyOf = (root) => String(new Function("root", "return " + {json.dumps(empty.group(1))})(root));
        const out = {{}};
        let r = make();
        r.translations = ["Today", "Already English", "Station"];
        finishFn(r);
        out.withoutColours = r.loading;
        r = make();
        r.colours = [];
        finishFn(r);
        out.withoutTranslations = r.loading;
        r = make();
        r.translations = ["Today", "Already English", "Station"];
        r.colours = [{{ background: "#112233", text: "#ffffff" }}, null];
        finishFn(r);
        out.loading = r.loading;
        out.boxes = r.boxes.map(b => [b.text, b.translated, b.colour]);
        out.empty = emptyOf(r);
        r = make();
        r.translations = ["今日は", "Already English.", "駅"];
        r.colours = [];
        finishFn(r);
        out.nothing = [r.loading, r.boxes.length, emptyOf(r)];
        console.log(JSON.stringify(out));
    """)
    assert res["withoutColours"] and res["withoutTranslations"], \
        "the boxes are drawn before both the translations and the colours are in -- they change colour on screen"
    assert res["loading"] is False, "finish() never ends the loading state"
    assert res["boxes"] == [["今日は", "Today", {"background": "#112233", "text": "#ffffff"}], ["駅", "Station", None]], \
        f"delegates are built for {res['boxes']} -- only real translations, in order, each with its own colour"
    assert res["empty"] == "false", "a screen with translations reads as empty"
    assert res["nothing"] == [False, 0, "true"], \
        f"a screen already in the target language ends as {res['nothing']} instead of saying so"

    # Delegates carry no process of their own, and are built from the boxes alone.
    body = block(overlay, "component TextItem:")
    assert not re.search(r"\b(Process|MultiTurnProcess|StdioCollector)\b", body), \
        "TextItem starts a process -- one per box, all at once"
    models = re.findall(r"model:\s*([^\n]+)", overlay)
    assert models and all(m.strip() == "root.boxes" for m in models), \
        f"a Repeater is built from {models} -- every OCR paragraph gets delegates, visible or not"
    assert re.search(r"\?\?\s*Appearance\.colors\.colSecondaryContainer", overlay) and \
        re.search(r"\?\?\s*Appearance\.colors\.colOnSecondaryContainer", overlay), \
        "a box with no colour has no theme fallback"
    # The box is opaque, and that is what erases the text under it. The blur it
    # replaced cost a masked MultiEffect, its mask layer and a second decode of
    # the screenshot, and at 60% the blurred glyphs still showed through.
    assert not re.search(r"\b(MultiEffect|MaskMultiEffect|layer\.enabled|StyledImage)\b", overlay), \
        "the overlay pays for an offscreen pass again -- the opaque box already erases the text"
    assert not re.search(r"transparentize\(", body), "the box is translucent -- the source text shows through it"

    # The scrim leaves on an effects spec: a spatial one overshoots and its opacity clips.
    panel = code(PANEL)
    spec = re.search(r"color:\s*Appearance\.colors\.colScrim[\s\S]*?Behavior on opacity \{\s*animation:\s*Appearance\.animation\.(\w+)", panel)
    assert spec and spec.group(1) in ("elementMoveExit", "elementMoveFast"), \
        f"the scrim fades on {spec and spec.group(1)} -- a spatial spec overshoots and the opacity clips"
    print("ok  reveal: waits for translations and colours, real translations only, one colour process")


def check_colour_script():
    try:
        import cv2  # noqa: F401
        import numpy as np
    except ImportError:
        print("--  text_color.py: no cv2 in this python, not run")
        return
    img = np.full((60, 200, 3), (230, 230, 230), np.uint8)  # BGR, light grey page
    img[20:40, 10:90] = (40, 30, 200)                         # a red "word" on it
    with tempfile.NamedTemporaryFile(suffix="") as f:
        # No extension, like the screenshot it reads: format comes from the content.
        ok, buf = cv2.imencode(".ppm", img)
        f.write(buf.tobytes())
        f.flush()
        boxes = ["0,10,100,40", "500,500,10,10", "-20,-20,10,10", "150.0,5.5,40,20"]
        out = subprocess.run([sys.executable, str(TEXT_COLOR), f.name, *boxes], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    res = json.loads(out.stdout)
    assert len(res) == len(boxes), f"{len(boxes)} boxes in, {len(res)} out -- the list no longer lines up"
    assert res[0] == {"background": "#e6e6e6", "text": "#c81e28"}, f"the word box reads {res[0]}"
    assert res[1] is None and res[2] is None, "a box with no pixels on the image did not come back null"
    assert res[3] == {"background": "#e6e6e6", "text": "#e6e6e6"}, f"a blank box with float coordinates reads {res[3]}"
    print("ok  text_color.py: one run, every box, in order")


check_exit()
check_namespace()
check_pan_and_zoom()
check_reveal()
check_colour_script()
