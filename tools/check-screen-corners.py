#!/usr/bin/env python3
"""Assert every monitor gets its own screen corners, and the hot corner fires on arrival only.

`ScreenCorners` is four `PanelWindow`s per monitor: the fake rounding and, in the same
windows, the hot corner that opens a sidebar. Each defect below had no symptom a single
monitor or a single screenshot shows.

**The screen.** `CornerPanelWindow` declared `property var screen`. `PanelWindow` already
has one, so the redeclaration took `screen: modelData` for itself and the real one was
never set: with a second monitor attached, all eight corners mapped on the focused one
(measured with `hyprctl output create headless`) and the second monitor had square
corners and no hot corner. The scan is repo-wide because the failure is not specific to
this file and qmllint's `property-override` warning drowns in its own noise.

**The hot corner and the rounding.** One window carries both, and its `visible` read the
rounding mode alone, so with rounding set to *No* or *Wrapped* the enabled hot corner had
no surface at all (measured: zero corner layers). The hot corner also sat *inside* the
`RoundCorner`, which is why hiding one meant hiding the other.

**The edge trigger.** `clicklessCornerEnd` ran in `onPositionChanged`, so it fired on every
motion event at the edge; only the opened sidebar's focus grab stopped the repeats, and a
pinned sidebar takes none. It is a binding now and acts on its rising edge. Hover only
opens; the click toggles. The binding does not cover the other half: closing a sidebar ends
its grab and a pointer resting in the corner comes back as a fresh hover, which read as an
arrival and reopened the sidebar on the spot (measured on the old code and the new; joining
the grab does not help, the grab changing re-sends the enter). The guard that ignores
hover for a moment after this side's sidebar closes is asserted structurally.

Run: python3 tools/check-screen-corners.py
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
SRC = (ROOT / "modules/ii/screenCorners/ScreenCorners.qml").read_text()
WINDOWS = ("PanelWindow", "FloatingWindow", "PopupWindow")


def block_from(src: str, start: int) -> str:
    """The body of the block whose brace is the first one at or after `start`."""
    i = src.index("{", start)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i + 1:j]
    raise AssertionError(f"unbalanced braces after offset {start}")


def block(src: str, pattern: str) -> str:
    m = re.search(pattern, src)
    assert m, f"{pattern!r} no longer matches -- this check is stale"
    return block_from(src, m.start())


def own_lines(body: str):
    """The lines of a block that belong to it and not to a nested object."""
    depth = 0
    for line in body.splitlines():
        if depth == 0:
            yield line
        depth += line.count("{") - line.count("}")


def prop(body: str, name: str) -> str:
    """A property's expression, with its `&&`/`||` continuation lines."""
    lines = body.splitlines()
    for k, line in enumerate(lines):
        m = re.match(rf"\s*(?:readonly property \w+ )?{name}: (.+)", line)
        if m:
            expr = m.group(1)
            for nxt in lines[k + 1:]:
                if not re.match(r"\s*(&&|\|\|)", nxt):
                    break
                expr += " " + nxt.strip()
            return expr
    raise AssertionError(f"{name} is no longer declared -- this check is stale")


def js(text: str, names: dict) -> str:
    """The subset of JS the lifted expressions are written in, as Python."""
    for a, b in sorted(names.items(), key=lambda kv: -len(kv[0])):
        text = text.replace(a, b)
    text = text.replace("===", "==").replace("&&", " and ").replace("||", " or ")
    return re.sub(r"!(?!=)", " not ", text)


def check_no_window_shadows_screen():
    offenders = []
    for path in ROOT.rglob("*.qml"):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(("user_widgets/", "modules/common/widgets/shapes/")):
            continue
        src = path.read_text(errors="replace")
        for m in re.finditer(rf"(?<![\w.])(?:{'|'.join(WINDOWS)})\s*\{{", src):
            body = block_from(src, m.start())
            for line in own_lines(body):
                if re.match(r"\s*(readonly\s+|required\s+)*property\s+\S+\s+screen\b", line):
                    offenders.append(f"{rel}: {line.strip()}")
    assert not offenders, ("a window redeclares `screen`, so `screen: ...` writes the "
                           "shadow and the window maps on the focused monitor:\n  "
                           + "\n  ".join(offenders))
    uses = re.findall(r"CornerPanelWindow \{([^}]*)\}", SRC)
    assert len(uses) == 4, f"expected four corners per monitor, found {len(uses)}"
    assert all(re.search(r"\bscreen:\s*monitorScope\.modelData", u) for u in uses), \
        "a corner no longer says which monitor it belongs to"


def check_hot_corner_does_not_need_the_rounding():
    window = block(SRC, r"component CornerPanelWindow: PanelWindow\s*\{")
    corner = block(window, r"RoundCorner\s*\{")
    assert "Loader" not in corner, "the hot corner is inside the RoundCorner again, so hiding one hides both"
    loader = block(window, r"Loader\s*\{\s*id:\s*hotCornerLoader\b")
    assert re.search(r"active:\s*cornerPanelWindow\.hotCorner\b", loader), "the hot corner no longer loads on hotCorner"
    assert re.search(r"visible:\s*cornerPanelWindow\.rounded\b", corner), "the corner no longer paints on rounded"

    names = {
        "Config.options.appearance.fakeScreenRounding": "mode",
        "Appearance.rounding.screenRounding": "radius",
        "Config.options.sidebar.cornerOpen.enable": "enable",
        "Config.options.sidebar.cornerOpen.bottom": "bottom",
        "cornerWidget.isBottom": "is_bottom",
    }
    rounded = js(prop(window, "rounded"), names)
    hot = js(prop(window, "hotCorner"), names)
    visible = js(prop(window, "visible"), {"hotCorner": "hot", "rounded": "rounded"})
    for mode in range(4):
        for radius in (0, 23):
            for enable in (False, True):
                for fullscreen in (False, True):
                    for bottom in (False, True):
                        for is_bottom in (False, True):
                            env = dict(mode=mode, radius=radius, enable=enable, fullscreen=fullscreen,
                                       bottom=bottom, is_bottom=is_bottom)
                            env["rounded"] = eval(rounded, {}, env)
                            env["hot"] = eval(hot, {}, env)
                            want_round = radius > 0 and (mode == 1 or (mode == 2 and not fullscreen))
                            want_hot = enable and not fullscreen and bottom == is_bottom
                            assert env["rounded"] == want_round, f"rounding wrong at {env}"
                            assert env["hot"] == want_hot, f"hot corner wrong at {env}"
                            assert eval(visible, {}, env) == (want_round or want_hot), \
                                f"window visibility wrong at {env}"


def check_edge_trigger_fires_on_arrival():
    area = block(SRC, r"sourceComponent: FocusedScrollMouseArea\s*\{")
    assert "onPositionChanged" not in area, \
        "the hot corner acts from onPositionChanged again -- that fires on every motion event"
    opens = re.findall(r"setSidebarOpen\(true\)", area)
    assert len(opens) == 2, f"expected the edge and the hover to be the only openers, found {len(opens)}"
    for handler in ("onAtEndChanged", "onEntered"):
        body = block(area, handler + r":\s*\{")
        assert "!reentryGuard.running" in body, f"{handler} ignores the re-entry guard"
        assert "setSidebarOpen(true)" in body, f"{handler} toggles instead of opening"
    assert "!cornerPanelWindow.sidebarOpen" in block(area, r"onPressed:\s*\{"), "the click no longer toggles"

    window = block(SRC, r"component CornerPanelWindow: PanelWindow\s*\{")
    changed = block(window, r"onSidebarOpenChanged:\s*\{")
    assert re.search(r"if \(!sidebarOpen\)\s*reentryGuard\.restart\(\)", changed), \
        "closing the sidebar no longer arms the guard, so a resting pointer reopens it"
    assert re.search(r"interval:\s*Qt\.styleHints\.mouseDoubleClickInterval", block(window, r"Timer\s*\{\s*id:\s*reentryGuard\b")), \
        "the guard's interval is no longer the platform's gesture window"

    body = block(area, r"readonly property bool atEnd:\s*\{")
    early = re.search(r"if \((.+)\)\s*return false;", body).group(1)
    offset = re.search(r"const verticalOffset = (.+);", body).group(1)
    cx = re.search(r"const correctX = (.+);", body).group(1)
    cy = re.search(r"const correctY = (.+);", body).group(1)
    names = {
        "Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset": "off",
        "Config.options.sidebar.cornerOpen.clicklessCornerEnd": "corner_end",
        "Config.options.sidebar.cornerOpen.clickless": "clickless",
        "cornerWidget.isRight": "is_right", "cornerWidget.isLeft": "is_left",
        "cornerWidget.isTop": "is_top", "cornerWidget.isBottom": "is_bottom",
        "verticalOffset": "off", "containsMouse": "inside", "mouseX": "mx", "mouseY": "my",
        "width": "w", "height": "h",
    }
    expr = f"(not ({js(early, names)})) and ({js(cx, names)}) and ({js(cy, names)})"
    assert js(offset, names).strip() == "off", "the vertical offset is no longer read from the config"

    def arrivals(clickless, is_top, path):
        env = dict(clickless=clickless, corner_end=True, off=1, w=250, h=5,
                   is_right=True, is_left=False, is_top=is_top, is_bottom=not is_top)
        count, last = 0, False
        for my in path:
            env.update(inside=0 <= my < env["h"], mx=249, my=my)
            now = eval(expr, {}, env)
            count += now and not last
            last = now
        return count

    # A slow slide along the right edge into the corner, half a pixel per event: the
    # old handler fired on each of the ~6 events inside the band.
    up = [8 - k / 2 for k in range(17)]  # 8 .. 0, entering at the band's far edge
    down = [-3 + k / 2 for k in range(17)]  # down the edge into a bottom corner
    assert arrivals(False, True, up) == 1, "sliding into the top corner does not fire exactly once"
    assert arrivals(False, False, down) == 1, "sliding into the bottom corner does not fire exactly once"
    assert arrivals(True, True, up) == 0, "the edge trigger fires while hover-to-trigger is on"


check_no_window_shadows_screen()
check_hot_corner_does_not_need_the_rounding()
check_edge_trigger_fires_on_arrival()
print("ok: every monitor gets its own corners, the hot corner survives rounding off, and the edge fires on arrival")
