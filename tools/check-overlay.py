#!/usr/bin/env python3
"""The widget overlay leaves when it is dismissed, and lets go of what it pinned.

Everything here is invisible: two of the four defects it pins produced no warning, no
wrong pixel and no missing widget on the screen you were looking at.

* **A pin could not survive a shell restart, and a closed pin was never released.**
  `Loader.active` was `overlayOpen || OverlayContext.hasPinnedWidgets`, and
  `hasPinnedWidgets` was a list that live widgets pushed themselves onto -- widgets
  that live *inside* the window that list decides to open. Chicken and egg in both
  directions. Measured, with nothing but `hyprctl layers`: pin a widget, restart the
  shell, `quickshell:overlay` never appears until you open the overlay by hand; close
  that pinned widget from its own X and the full-screen `WlrLayer.Overlay` surface
  stays mapped for the rest of the session with a destroyed `Item` still in its input
  mask. Derived from `Persistent` it is 1 and 0 as it should be.

* **`property bool open: Persistent.states.overlay.open`**, a `list<string>` assigned
  to a `bool`. QML coerces any object to `true` -- an empty list included, measured
  with a `qs -p` probe -- so the guard that was supposed to say "this widget left the
  open list" said `true` from the first frame and `actuallyPinned` could never fall.
  That is what made the paragraph above unrecoverable rather than merely late.

* **The surface had no exit.** `Loader.active` reading the open request destroys the
  component on the frame the flag clears: measured unmapping ~30ms after the request,
  which is the next frame, against ~148ms now for a 130ms `elementMoveExit`. The card
  chrome was worse than nothing -- the scrim and the taskbar had a `Behavior` each and
  the card's background, outline and title bar had none, so the one exit a pinned
  widget could ever show was half animated.

* **The effect budget nobody could see.** Every overlay widget is a `Repeater`
  delegate, but the delegate is two files away (`OverlayWidgetDelegateChooser`), so
  `check-effect-budget.py` -- which reads a `Repeater` block inside one file -- has
  never counted one of these. The shared card in `StyledOverlayWidget` spent a
  `layer.enabled` + `OpacityMask` per open widget to round a corner that only the
  title bar ever reached: with the shipped five widgets open that was seven offscreen
  passes standing, and rounding two corners of the title bar took it to three.

Run: python3 tools/check-overlay.py
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OVERLAY = ROOT / "dots/.config/quickshell/ii/modules/ii/overlay"

overlay = (OVERLAY / "Overlay.qml").read_text()
context = (OVERLAY / "OverlayContext.qml").read_text()
content = (OVERLAY / "OverlayContent.qml").read_text()
card = (OVERLAY / "StyledOverlayWidget.qml").read_text()
taskbar = (OVERLAY / "OverlayTaskbar.qml").read_text()

QML = sorted(p for p in OVERLAY.rglob("*.qml"))


# ── 1. the window outlives the request ───────────────────────────────────────

active = re.search(r"^\s*active:\s*(.+)$", overlay, re.M)
assert active, "Overlay.qml declares no `active:` on its Loader"
assert "GlobalStates.overlayOpen" not in active.group(1), (
    f"`active: {active.group(1).strip()}` destroys the surface on the frame the request "
    "clears. That binding and whatever starts the exit hang off one change signal in an "
    "undefined order, and the binding wins -- ii-onScreenKeyboard measured the close "
    "handler never running at all. Read a latch, not the request."
)
latch = re.search(r"OverlayContext\.(\w+)", active.group(1))
assert latch, f"`active: {active.group(1).strip()}` -- the latch must live on OverlayContext"
latch = latch.group(1)
assert f"property bool {latch}" in context, f"OverlayContext declares no `{latch}`"

# and only the exit reaching zero may clear it
clears = [m for m in re.finditer(rf"root\.{latch}\s*=\s*false", context)]
assert clears, f"nothing ever clears `{latch}`; the surface would never unmap"
for m in clears:
    before = context[: m.start()]
    assert "onShownProgressChanged" in before or "wasShowing" in before, (
        f"`{latch}` is cleared outside the exit, at char {m.start()}. Every other path "
        "is the same undefined ordering the latch exists to avoid."
    )


# ── 2. a list is not a bool ──────────────────────────────────────────────────

for path in QML:
    src = path.read_text()
    for m in re.finditer(r"property\s+bool\s+\w+:\s*(.+)$", src, re.M):
        rhs = m.group(1).strip().rstrip(";")
        assert not re.fullmatch(r"[\w.]*\boverlay\.open", rhs), (
            f"{path.name}: `property bool ...: {rhs}` -- QML coerces any object to true, "
            "an empty list included (measured). Ask `.includes(<identifier>)`."
        )


# ── 3. a pin is derived from what is on disk, never reported by a widget ─────

assert "function pin(" not in context, (
    "OverlayContext.pin() is back. A widget cannot report that it is pinned before the "
    "window that hosts it exists, which is exactly what decides whether to open one."
)
pinned = re.search(r"readonly property list<string> pinnedWidgetIdentifiers:\s*(.+?)\n\n",
                   context, re.S)
assert pinned, "pinnedWidgetIdentifiers must be a readonly binding, not storage"
assert "Persistent.states.overlay.open" in pinned.group(1), (
    "pinnedWidgetIdentifiers must be derived from the persisted open list, or a pin "
    "cannot survive a shell restart"
)
assert "extensionWidgets" in pinned.group(1), (
    "an extension widget's pin lives in ExtensionManager, not Persistent; "
    "`getContributionPoint` merges it into extensionWidgets, so read it from there"
)

# the one registration that has to stay, because the input mask needs the live Item
assert "Component.onDestruction" in card and "registerClickableWidget" in card, (
    "StyledOverlayWidget must unregister on destruction. A card closed from its own X is "
    "destroyed by the Repeater, and a destroyed Item left in `clickableWidgets` is a "
    "Region over nothing that also holds the whole surface open."
)
reg = re.search(r"function registerClickableWidget.*?\n    \}", context, re.S).group(0)
assert ".push(" not in reg, (
    "registerClickableWidget must reassign on both paths. Adding in place and removing by "
    "reassignment is how one direction notifies and the other silently does not."
)


# ── 4. one progress per kind, and opacity never rides the spatial one ────────

specs = dict(re.findall(r"root\.(openSpec|showSpec)\s*=\s*Appearance\.animation\.(\w+)", context))
assert specs.get("openSpec") and specs.get("showSpec"), \
    "both the scale and the opacity spec must be picked where the direction is known"
enter = re.findall(r"root\.(?:open|show)Spec = Appearance\.animation\.(\w+)", context)
assert "elementMoveExit" in enter, "the exit must name elementMoveExit"
assert "elementMoveEnter" in enter, "the enter must name elementMoveEnter"
# `openedProgress` may overshoot; `shownProgress` may not, so nothing may fade on it.
assert "shownProgress" in content and "openedProgress" in content, \
    "OverlayContent must read both progresses"
scale = re.search(r"^\s*scale:\s*(.+)$", content, re.M)
assert scale and "openedProgress" in scale.group(1), \
    "the zoom is the spatial one; it rides openedProgress"
for src, name in ((content, "OverlayContent"), (card, "StyledOverlayWidget"), (taskbar, "OverlayTaskbar")):
    for m in re.finditer(r"^\s*(opacity|color|border\.color):\s*(.+)$", src, re.M):
        assert "openedProgress" not in m.group(2), (
            f"{name}: `{m.group(1)}` on openedProgress. That rides a spatial spec which "
            "overshoots past 1 on the enter; opacity and colour must not (DESIGN.md 3)."
        )

# the pinned plane must not be inside the zoom while anything is pinned
init = re.search(r"initScale:\s*(.+)$", content, re.M)
assert init and "hasPinnedWidgets" in init.group(1), (
    "the zoom scales the plane the pinned cards sit on, so it has to be suppressed while "
    "anything is pinned -- otherwise a pinned crosshair slides every time the overlay goes"
)


# ── 5. the card's opacity, swept ─────────────────────────────────────────────
#
# `clickthroughOpacity` has no settings page, so it is whatever is in config.json:
# anything in [0, 1]. Two properties have to hold at every value of it.

def card_opacity(pinned, clickthrough, progress, clickthrough_opacity):
    resting = clickthrough_opacity if clickthrough else 1.0
    if not pinned:
        return progress
    return resting + (1 - resting) * progress

for i in range(0, 101):
    co = i / 100
    for clickthrough in (False, True):
        for pinned in (False, True):
            assert abs(card_opacity(pinned, clickthrough, 1.0, co) - 1.0) < 1e-9, (
                f"a card is not fully opaque with the overlay open "
                f"(pinned={pinned}, clickthrough={clickthrough}, clickthroughOpacity={co})"
            )
        assert card_opacity(False, clickthrough, 0.0, co) == 0.0, \
            "an unpinned card must be gone once the overlay has left"
        assert card_opacity(True, clickthrough, 0.0, co) == (co if clickthrough else 1.0), \
            "a pinned card must rest at exactly its resting opacity"

# and the binding in the file is that formula
assert re.search(r"restingOpacity\s*\+\s*\(1 - root\.restingOpacity\) \* OverlayContext\.shownProgress",
                 card), "StyledOverlayWidget's opacity is no longer the swept formula"
assert re.search(r"^\s*visible:\s*opacity > 0\s*$", card, re.M), (
    "`visible` must follow the animated opacity. Bound to the open request instead, a "
    "card unmaps on the frame the flag clears and its fade plays to nobody."
)


# ── 6. the effect budget the delegate scan cannot reach ──────────────────────
#
# Each widget is a Repeater delegate, but through OverlayWidgetDelegateChooser -- two
# files from the Repeater, which is why check-effect-budget.py has never seen one.

EFFECT = re.compile(r"\b(layer\.enabled|OpacityMask|MultiEffect|ShaderEffect|RectangularShadow)\b")


def effects(src):
    """Offscreen passes in one file. `layer.effect: OpacityMask {}` is the mask the
    `layer.enabled` above it already paid for, so it is dropped rather than counted
    twice."""
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"layer\.effect:\s*\w+", "layer.effect:", src)
    return len(EFFECT.findall(src))


counts = {p.relative_to(OVERLAY).as_posix(): effects(p.read_text()) for p in QML}

assert counts["StyledOverlayWidget.qml"] == 0, (
    f"the shared card carries {counts['StyledOverlayWidget.qml']} effect(s). It stands "
    "once per open widget, so one here is five offscreen passes on the shipped config. "
    "The title bar is the only child that reaches the card's edge: round its own two top "
    "corners instead."
)
for name, n in sorted(counts.items()):
    assert n <= 1, (
        f"{name} carries {n} effects; the ceiling is one per delegate file (DESIGN.md 8). "
        "Anything more stands simultaneously with every other open widget."
    )
assert "topLeftRadius" in card and "topRightRadius" in card, \
    "the title bar's top corners are what replaced the card's mask"


# ── 7. an identifier no widget answers to is filtered, not indexed ───────────

models = re.findall(r"values: Persistent\.states\.overlay\.open\.map\((.*?)\n\s*objectProp",
                    content, re.S)
assert len(models) == 2, f"expected two widget Repeaters in OverlayContent, found {len(models)}"
for m in models:
    assert ".filter(" in m, (
        "an identifier no widget answers to -- every extension widget, and anything left "
        "by an older config -- puts `undefined` in the model, which `objectProp` indexes"
    )


# ── 8. the assistant's input row pins its own height ─────────────────────────
#
# `ToolbarButton` sets `Layout.fillHeight: true`, and a nested layout that holds a
# child which fills starts filling itself -- which beats `Layout.preferredHeight`.
# The row took the whole card: transcript 9px tall with its empty-state line against
# the title bar, and `IconToolbarButton`'s `implicitWidth: height` turned the eye
# toggle into a 390px circle. One caller in the shell hits this shape; this is it.

assist = (OVERLAY / "assist/AssistContent.qml").read_text()
row = re.search(r"RowLayout \{(.*?)\n            spacing:", assist, re.S)
assert row, "AssistContent's input row moved"
assert "Layout.fillHeight: false" in row.group(1), (
    "the input row must refuse to fill. It holds ToolbarButtons, which declare "
    "`Layout.fillHeight: true`, and that propagates to the row and beats its "
    "`preferredHeight` -- measured at 389px tall against the 38 it asks for."
)
assert "Layout.preferredHeight" in row.group(1), (
    "the row needs a pinned height. It cannot be grown from the draft either: a "
    "QQuickLayout reads this hint once and ignores every later change, measured across "
    "a binding, a plain property, a deferred assignment and lineCount."
)
assert re.search(r"oneLine\.height \* 3", row.group(1)), (
    "three lines, measured off the field's own font with TextMetrics. One line of "
    "viewport on a wrapped field scrolls the draft out of sight as it is typed -- the "
    "caret ends up in what looks like an empty box while the whole thing still sends."
)
# both buttons opt out of filling, or the row is capped at 35 and they stretch to ovals
buttons = re.findall(r"IconToolbarButton \{(.*?)\n            \}", assist, re.S)
assert len(buttons) == 2, f"expected the eye and the send button, found {len(buttons)}"
for b in buttons:
    assert "Layout.fillHeight: false" in b and "Layout.alignment: Qt.AlignBottom" in b, (
        "a composer button must opt out of ToolbarButton's fill and sit on the bottom "
        "edge. Left filling it stretches to the row height, and `IconToolbarButton` is "
        "`implicitWidth: height`, so it stops being square."
    )
field = re.search(r"StyledTextArea \{(.*?)\n                    Keys\.", assist, re.S)
assert field, "AssistContent's input field moved"
field = re.sub(r"//[^\n]*", "", field.group(1))  # the comment below names anchors.fill
assert "anchors.fill" not in field and "availableWidth" in field, (
    "the field is sized by `width: inputScroll.availableWidth`. Anchored to the viewport "
    "it is sized by the thing measuring it -- measured running to 680px inside a 460px "
    "card, so the wrap points were wrong as well as the height."
)


# ── 9. nine icon-only buttons are labelled ───────────────────────────────────

assert "StyledToolTip" in taskbar, (
    "the taskbar's widget toggles are icon-only: `point_scan` and `browse_activity` do "
    "not read as a crosshair and a resource monitor without the tooltip their title-bar "
    "siblings already carry"
)
assert "OverlayContext.titleFor" in taskbar and "OverlayContext.titleFor" in card, \
    "the tooltip and the card's title bar must derive the same label from one place"

print(f"ok  overlay: exit latched off `{latch}`, pins derived from disk, "
      f"{sum(counts.values())} effects over {len(QML)} files "
      f"(shared card {counts['StyledOverlayWidget.qml']}), card opacity swept over "
      "clickthroughOpacity 0..1")
