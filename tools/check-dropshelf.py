#!/usr/bin/env python3
"""The drop shelf opens where the files landed, closes visibly, and cannot be
destroyed out from under a drag.

Four things about `modules/ii/dropover/` are expressions or invariants rather
than pictures, so no screenshot and no smoke run proves any of them:

- **The pivot.** Launcher3's ArrowPopup.setPivotForOpenCloseAnimation() grows a
  popup out of the corner nearest the point that opened it. The card is placed
  at the drop point and then slid back inside the screen near an edge, so
  "nearest corner" has to be asked of the *drop point* against the placed card.
  Asking the clamp instead -- `x >= dropShelfX` -- agrees everywhere until the
  slide begins and is then wrong for the next half a card width. That is the bug
  `ii-desktopMenu` shipped and fixed, and this surface is built from the same
  arithmetic, so it is swept the same way.

- **The exit.** `visible: GlobalStates.dropShelfOpen` merges the request with
  the surface: the window is gone on the frame the flag flips and the close
  animation plays to nobody. There is no other symptom -- the shelf still
  disappears -- which is why it is asserted structurally rather than watched.

- **The coordinate space.** `dropShelfX`/`Y` are screen-local and only mean
  something next to `dropShelfScreen`. Two producers disagreed about that: the
  desktop menu passed screen-local coordinates and the wallpaper drop handler
  passed `mapToGlobal` ones into the same two globals. Every producer is checked
  for setting all three.

- **The drag guard.** `QDrag::exec` runs a nested event loop, so freeing the
  mime data mid-drag takes the shell down. Every `DropShelf` mutator refuses
  while `dragActive`, and the panel is a live window rather than a `Loader` that
  could destroy the proxy under one.

    python3 tools/check-dropshelf.py
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"
PANEL = SHELL / "modules/ii/dropover/DropShelfPanel.qml"
ITEM = SHELL / "modules/ii/dropover/DropShelfItem.qml"
PROXY = SHELL / "modules/ii/dropover/DragProxy.qml"
SERVICE = SHELL / "services/DropShelf.qml"

GUTTER = 8  # shelfCard.gutter
CARD_W = 360  # shelfCard.implicitWidth


# -- placement, lifted out of the x/y and leftAligned/topAligned bindings -----


def place(point, window, size):
    """shelfCard.x / .y: top-left at the drop point, slid back inside."""
    return max(GUTTER, min(point, window - size - GUTTER))


def pivot(px, py, win_w, win_h, w, h):
    """The placed rect and the corner it grows out of."""
    x = place(px, win_w, w)
    y = place(py, win_h, h)
    return x, y, px <= x + w / 2, py <= y + h / 2


def clamp_pivot(px, py, win_w, win_h, w, h):
    """The wrong one: ask where the slide left the card, not where the drop was."""
    x = place(px, win_w, w)
    y = place(py, win_h, h)
    return x, y, x >= px, y >= py


def nearest_corner(px, py, x, y, w, h):
    """Ground truth, by distance to each of the four corners."""
    corners = {
        (True, True): (x, y),
        (False, True): (x + w, y),
        (True, False): (x, y + h),
        (False, False): (x + w, y + h),
    }
    return min(corners, key=lambda k: (corners[k][0] - px) ** 2 + (corners[k][1] - py) ** 2)


SCREENS = [(1920, 1080), (2560, 1440), (3840, 2160), (1366, 768), (1280, 720)]
HEIGHTS = [216, 264, 180]  # one row of tiles, a taller card, the empty shelf


def check_pivot():
    """Every drop point on every screen: on screen, and out of the right corner."""
    disagreements = 0
    for win_w, win_h in SCREENS:
        for h in HEIGHTS:
            for px in range(0, win_w, 7):
                for py in range(0, win_h, 11):
                    x, y, left, top = pivot(px, py, win_w, win_h, CARD_W, h)

                    assert x >= GUTTER and y >= GUTTER, \
                        f"card off the top/left at {px},{py} on {win_w}x{win_h}: {x},{y}"
                    assert x + CARD_W <= win_w - GUTTER and y + h <= win_h - GUTTER, \
                        f"card off the bottom/right at {px},{py} on {win_w}x{win_h}: {x},{y}"

                    want = nearest_corner(px, py, x, y, CARD_W, h)
                    assert (left, top) == want, \
                        f"pivot {left,top} != nearest {want} at {px},{py} on {win_w}x{win_h}"

                    _, _, cleft, ctop = clamp_pivot(px, py, win_w, win_h, CARD_W, h)
                    if (cleft, ctop) != want:
                        disagreements += 1

    # The band the clamp form gets wrong has to be large, or this sweep is not
    # evidence that asking the drop point instead was worth doing.
    assert disagreements > 50000, \
        f"the clamp form only differs in {disagreements} places -- sweep is not covering the edges"

    # The sweep is of the arithmetic above, so the QML has to still be running it.
    src = PANEL.read_text()
    for axis, side in (("X", "leftAligned"), ("Y", "topAligned")):
        m = re.search(rf"readonly property bool {side}:\s*(.+)", src)
        assert m, f"the card no longer computes {side}"
        assert m.group(1).startswith(f"GlobalStates.dropShelf{axis} <="), \
            f"{side} asks the clamp, not the drop point -- that is the band this sweeps: {m.group(1)}"
    print(f"ok  pivot: nearest corner everywhere; the clamp form is wrong in {disagreements:,} spots")


def check_exit_survives_the_flag():
    """The window outlives the bool, or the close animation plays to nobody."""
    src = PANEL.read_text()

    m = re.search(r"^\s*visible:\s*(.+)$", src, re.M)
    assert m, "DropShelfPanel has no `visible:` binding"
    visible = m.group(1)
    assert "dropShelfOpen" in visible, f"visible no longer follows the request: {visible}"
    assert "opacity" in visible, (
        "visible is bound to dropShelfOpen alone -- the surface is destroyed on the frame "
        f"the flag flips and there is no exit animation left: {visible}"
    )

    # The motion itself is the shared composite, not a fifth hand transcription.
    assert "ArrowPopupMotion" in src, "the enter/exit is not the shared ArrowPopup composite"
    assert re.search(r"scale:\s*Appearance\.animationCurves\.arrowPopupScale", src), \
        "the card has no resting scale, so a second open starts from wherever the last close left it"
    assert re.search(r"^\s*opacity:\s*0\s*$", src, re.M), "the card has no resting opacity"

    # Both directions are wired, not just the one that is easy to notice.
    assert re.search(r"motion\.open\(\)", src) and re.search(r"motion\.close\(\)", src), \
        "only one direction of the motion is driven"
    print("ok  exit: the surface outlives the flag, on the shared ArrowPopup composite")


def check_transform_origin():
    """A scale with the wrong origin is wrong however good the timing is."""
    src = PANEL.read_text()
    # The shadow mirrors the card's, so take the one that names corners.
    origins = [o for o in re.findall(r"^\s*transformOrigin:\s*(.+)$", src, re.M) if "Item." in o]
    assert origins, "the card has no transformOrigin, so it grows out of its own centre"
    origin = origins[0]
    for corner in ("TopLeft", "TopRight", "BottomLeft", "BottomRight"):
        assert corner in origin, f"transformOrigin never reaches Item.{corner}: {origin}"
    assert "Center" in origin, \
        "opened with no drop point there is no nearest corner; it has to fall back to Item.Center"

    # The shadow is a sibling, so it does not inherit the card's transform.
    shadow = re.search(r"StyledRectangularShadow\s*\{(.+?)\n\s*\}", src, re.S)
    assert shadow, "the card lost its shadow"
    for prop in ("scale:", "transformOrigin:", "opacity:"):
        assert prop in shadow.group(1), \
            f"the shadow does not follow the card's {prop} and will sit full size around a growing card"
    print("ok  origin: all four corners plus the centre, and the shadow follows the card")


def check_screen_travels_with_the_point():
    """Screen-local coordinates mean nothing without the screen they are local to."""
    producers = [p for p in SHELL.rglob("*.qml") if "dropShelfX" in p.read_text()]
    assert producers, "nothing sets dropShelfX any more"

    for path in producers:
        src = path.read_text()
        if path.name == "GlobalStates.qml":
            continue
        # A file that only reads the point (the panel itself) is fine; one that
        # writes it has to say which screen it is on.
        if not re.search(r"dropShelfX\s*=", src) and "DropShelf.show(" not in src:
            continue
        assert "dropShelfScreen" in src or "DropShelf.show(" in src, \
            f"{path.relative_to(ROOT)} sets a drop point but never says which screen it is on"
        assert "mapToGlobal" not in src or "DropShelf.show(" not in src, \
            f"{path.relative_to(ROOT)} passes global coordinates into a screen-local field"

    service = SERVICE.read_text()
    assert re.search(r"function show\(urls, screen, x, y\)", service), \
        "DropShelf.show() no longer takes the screen, so the two producers can disagree again"
    print(f"ok  screen: all {len(producers)} files that touch the drop point carry the screen")


def check_drag_guard():
    """Freeing the mime data mid-drag is a segfault, not a glitch."""
    service = SERVICE.read_text()
    for fn in ("addItems", "removeItem", "clear", "hide"):
        body = re.search(rf"function {fn}\([^)]*\)[^{{]*\{{(.+?)\n    \}}", service, re.S)
        assert body, f"DropShelf.{fn}() is gone"
        assert "root.dragActive" in body.group(1), \
            f"DropShelf.{fn}() mutates the shelf without checking dragActive"

    panel = PANEL.read_text()
    assert "DragProxy" in panel, "the drag proxy no longer lives on the panel"
    assert not re.search(r"Loader\s*\{[^}]*sourceComponent:\s*PanelWindow", panel, re.S), \
        ("the panel is behind a Loader again -- a close mid-drag destroys the proxy and "
         "frees mime data the compositor is still reading")

    item = ITEM.read_text()
    assert "drag.target: root.dragProxy" in item, \
        "the tile drags itself again; a recycled delegate takes the shell down with it"
    assert re.search(r"Drag\.mimeData", PROXY.read_text()), "the proxy carries no mime data"
    print("ok  drag: every mutator guarded, and the proxy outlives its delegates")


def check_tile_states():
    """Four states, always -- the tile had none at all."""
    item = ITEM.read_text()
    overlay = re.search(r"StateOverlay\s*\{(.+?)\n\s{8}\}", item, re.S)
    assert overlay, "the tile has no StateOverlay, so it shows nothing under the pointer"
    body = overlay.group(1)
    for state in ("hover:", "press:", "drag:"):
        assert state in body, f"the tile's state overlay never binds {state}"
    assert "hoverEnabled: true" in item, "the tile's MouseArea reports no hover"
    print("ok  states: hover, press and drag layers on the tile")


if __name__ == "__main__":
    check_pivot()
    check_exit_survives_the_flag()
    check_transform_origin()
    check_screen_travels_with_the_point()
    check_drag_guard()
    check_tile_states()
    print("\nall ok")
