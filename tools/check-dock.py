#!/usr/bin/env python3
"""The dock's per-icon cost, and the motion its popups open and close on.

Both are things no screenshot of the dock shows, and neither is covered by a
gate that already exists.

- **The cost.** `check-effect-budget.py` finds an effect inside a repeated
  delegate by reading a `Repeater` or `delegate:` block *in one file*. Every one
  of the dock's delegates is its own file -- `DockAppButton.qml`,
  `DockFileButton.qml`, `DockFolderButton.qml`, and `DockIcon.qml` under all
  three -- so that gate has never seen a single one of them, and it did not see
  the three offscreen passes each app icon was paying: a `Desaturate` *and* a
  `ColorOverlay` in `DockIcon` (monochrome is on by default), plus a blurred
  `StyledDropShadow` in `DockAppButton`. Thirteen pinned apps made that forty
  framebuffers for a strip of 39px icons. This is the shrink-only ceiling for
  those files, stated per file, so a fourth one fails rather than being absorbed.

- **The motion.** `DockFolderPopup` and `DockContextMenuBase` are two of the
  four places AOSP's `ArrowPopup` open/close was transcribed by hand, and the
  hand copies drifted in exactly the ways you cannot see in a still frame: one
  grew an inline bezier, and the other ran its enter and its exit off the *same*
  `Behavior` on a spatial spec -- which is not an exit, it is the enter played
  backwards at the wrong speed -- out of a `transformOrigin: Item.Center` that
  ignored the icon the menu belongs to. Both now call `ArrowPopupMotion`, so the
  assertions are: the recipe is assembled once, its two halves use different
  curves and different durations, and every dock surface that pops pivots on the
  dock's edge rather than on itself.

Run: python3 tools/check-dock.py
"""
import pathlib
import re

SHELL = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
DOCK = SHELL / "modules/ii/dock"
MOTION = SHELL / "modules/common/widgets/ArrowPopupMotion.qml"


def src(p: pathlib.Path) -> str:
    """File text with comments blanked, so a comment cannot satisfy a check."""
    s = p.read_text()
    s = re.sub(r"//[^\n]*", "", s)
    return re.sub(r"/\*.*?\*/", "", s, flags=re.S)


def passes(s: str) -> list:
    """The offscreen passes one file costs.

    `layer.enabled` plus `layer.effect: MultiEffect {}` is ONE pass -- the layer
    is the framebuffer and the effect is the shader that reads it. A standalone
    effect with its own `source:` is a second one, which is the distinction this
    whole row turns on, so the effect named as a layer.effect is not counted
    twice.
    """
    s = re.sub(r"layer\.effect\s*:\s*\w+\s*\{", "layer.effect: _ {", s)
    return [m.group(1).split("{")[0].split(":")[0].strip() for m in EFFECT.finditer(s)]


EFFECT = re.compile(
    r"\b(layer\.enabled\s*:\s*(?!false\b)|MultiEffect\s*\{|OpacityMask\s*\{"
    r"|ShaderEffect\s*\{|StyledBlurEffect\s*\{|StyledDropShadow\s*\{|Colorizer\s*\{"
    r"|DropShadow\s*\{|GaussianBlur\s*\{|FastBlur\s*\{|RecursiveBlur\s*\{"
    r"|ColorOverlay\s*\{|Desaturate\s*\{|Glow\s*\{)")

# Files the dock instantiates once per app, file or folder on the strip, and the
# most offscreen passes each may cost. Shrink only: lowering a number is the
# point of the row, raising one needs the argument written next to it.
#
# DockIcon 1     -- one MultiEffect, as a layer effect so there is no second
#                   ShaderEffectSource, and only while monochrome or
#                   dim-inactive is on. It cannot rise to the container: the
#                   running-window dots sit one level up and must not be
#                   desaturated, which is decision 26's argument for Workspaces.
# DockFileButton 1 -- one layer, rounding an image thumbnail. Pinned files are
#                   a handful at most and default to none, so this is the
#                   cheapest of the three and is left alone.
DELEGATE_BUDGET = {
    "widgets/DockIcon.qml": 1,
    "DockAppButton.qml": 0,
    "DockFolderButton.qml": 0,
    "DockFileButton.qml": 1,
}

for rel, ceiling in DELEGATE_BUDGET.items():
    path = DOCK / rel
    assert path.exists(), f"{rel} is gone -- update DELEGATE_BUDGET, do not delete the check"
    hits = passes(src(path))
    assert len(hits) <= ceiling, (
        f"{rel} costs {len(hits)} offscreen passes per delegate, budget {ceiling}: {hits}.\n"
        "Every app on the strip pays this. Cache it at the container or drop it "
        "(DESIGN.md 8); check-effect-budget.py cannot see this file.")

# The one that regressed before: DockIcon must do its desaturate and its tint in
# the SAME pass, and must not pay for either when both options are off.
icon = src(DOCK / "widgets/DockIcon.qml")
assert "layer.effect" in icon, \
    "DockIcon's effect must be a layer.effect -- a standalone effect with `source:` " \
    "adds a ShaderEffectSource of its own, which is the pass this row removed"
assert re.search(r"layer\.enabled\s*:\s*(?!true\b)\S", icon), \
    "DockIcon's layer.enabled must be conditional, not `true` -- an icon with " \
    "neither monochrome nor dim-inactive on should cost nothing at all"
assert "Desaturate" not in icon and "ColorOverlay" not in icon, \
    "DockIcon is back to two Qt5Compat effects; MultiEffect does saturation and " \
    "colorization in one"

# ---------------------------------------------------------------------------
# The ArrowPopup recipe: assembled once, asymmetric, and pivoted on the dock.

assert MOTION.exists(), "ArrowPopupMotion.qml is gone (DECISIONS.md 14)"
motion = src(MOTION)

for token in ("arrowPopupScale", "arrowPopupOvershoot", "arrowPopupSettle",
              "arrowPopupScaleDuration", "arrowPopupCloseDuration",
              "arrowPopupFadeDuration", "arrowPopupFadeHold"):
    assert token in motion, f"ArrowPopupMotion no longer uses {token}"

# Enter decelerates, exit accelerates, and they are not the same length
# (DESIGN.md 2.5). Running both off one spec is what DockContextMenuBase did,
# and a still frame of either end looks identical whichever way it is wrong.
assert "emphasizedDecel" in motion and "emphasizedAccel" in motion, \
    "the enter and the exit must be on different curves, or the exit is just " \
    "the enter played backwards (DESIGN.md 2.5)"
assert "elementResize" not in motion, \
    "opacity must never animate on a spatial spec -- it overshoots and clips (3)"
assert re.search(r"\bduration\s*:\s*\d", motion) is None, \
    "no literal duration in ArrowPopupMotion: every number comes from " \
    "Appearance.animationCurves.arrowPopup* (DESIGN.md 2)"

# The dock's two popping surfaces go through it rather than re-typing it.
for rel in ("DockFolderPopup.qml", "widgets/DockContextMenuBase.qml"):
    body = src(DOCK / rel)
    assert "ArrowPopupMotion" in body, \
        f"{rel} must open and close through ArrowPopupMotion, not its own copy"
    stray = [t for t in ("arrowPopupOvershoot", "arrowPopupSettle",
                         "arrowPopupCloseDuration", "arrowPopupFadeHold")
             if t in body]
    assert not stray, f"{rel} is re-assembling the recipe by hand: {stray}"
    # 2.6: a surface grows out of whatever opened it. Both of these hang off an
    # icon pinned to the dock's edge, so the pivot is that edge -- and it has to
    # be read from dockPos, because the dock moves.
    origins = [m.group(1) for m in
               re.finditer(r"transformOrigin\s*:\s*(\{.*?\n\s*\}|[^\n]+)", body, re.S)]
    assert origins, f"{rel} has no transformOrigin"
    assert not any("Item.Center" in o for o in origins), \
        f"{rel} pivots on itself; it belongs to the icon that opened it (DESIGN.md 2.6)"
    chosen = max(origins, key=len)
    for edge in ("Item.Top", "Item.Bottom", "Item.Left", "Item.Right"):
        assert edge in chosen, \
            f"{rel}'s pivot does not cover {edge} -- the dock moves, so all four do"

# ---------------------------------------------------------------------------
# Law 11 across the dock's menus: whitespace, not rules.

for path in sorted(DOCK.rglob("*.qml")):
    body = src(path)
    for m in re.finditer(r"implicitHeight\s*:\s*1\b", body):
        line = body.count("\n", 0, m.start()) + 1
        window = body[max(0, m.start() - 400):m.start() + 200]
        assert "color" not in window.split("Rectangle")[-1], (
            f"{path.relative_to(SHELL)}:{line}: a 1px coloured Rectangle is a "
            "divider whatever it is called -- law 11 separates with whitespace "
            "on the 4dp grid")

# ---------------------------------------------------------------------------
# DockButton composes its two scales instead of animating `scale` directly.
# `Behavior on scale` on top of a `scale:` binding kills the binding, which is
# anti-pattern 4 and has shipped here before.

button = src(DOCK / "widgets/DockButton.qml")
assert re.search(r"scale\s*:\s*root\.hoverScale\s*\*\s*root\.pressScale", button), \
    "DockButton must compose scale: hoverScale * pressScale (DESIGN.md 2.9, 3.3)"
assert "Behavior on scale" not in button, \
    "a Behavior on scale would destroy the composition binding (anti-pattern 4)"
assert "iconHover" in button and "iconPressSquish" in button, \
    "the hover and squish durations are AOSP's, and live in Appearance.animation"
assert re.search(r"\bduration\s*:\s*\d", button) is None, \
    "DockButton is back to literal durations (DESIGN.md 2, anti-pattern 7)"

print(f"ok: {len(DELEGATE_BUDGET)} dock delegates within their per-icon effect budget, "
      "ArrowPopup assembled once and pivoted on the dock edge, no divider rules")
