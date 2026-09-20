#!/usr/bin/env python3
"""Assert the geometry ResourcesPopup's five removed OpacityMasks used to cover.

The popup carried five `layer.enabled` + `OpacityMask` pairs, one framebuffer
each, on an integrated-graphics target (DESIGN.md 8). All five are gone, and
both replacements are geometric claims that nothing on screen will announce if
they stop being true -- a fill spilling past its track, or a plot painting into a
corner arc, both just look like a rendering glitch at 60fps:

1. The three meter pills masked their own fill to the track. The fill is
   left-aligned, the same height as the track and carries the same `full` radius,
   so Qt's radius clamp already keeps it inside at every width -- the mask was
   masking a shape that was never outside it. Change the fill's height or radius
   and that stops holding.

2. The two usage cards masked the graph well so the Canvas could not paint into
   a rounded corner. The Canvas is now inset by the well's own corner radius,
   past which the well's edge is straight. Drop the inset and the plot's fill
   spills out of the bottom corners.

And `getDelay` staggers over *visible* siblings, so hiding swap or docker does
not leave a hole in the sequence (DESIGN.md 2.8).

Run: python3 tools/check-resources-popup.py
"""
import math
import pathlib
import re

QML = (pathlib.Path(__file__).parent.parent
       / "dots/.config/quickshell/ii/modules/ii/bar/ResourcesPopup.qml")
SRC = QML.read_text()
CODE = "\n".join(ln for ln in SRC.splitlines()
                 if not ln.lstrip().startswith(("*", "//", "/*")))


def sdf(px, py, w, h, r):
    """Signed distance to a rounded rect at the origin; <= 0 is inside."""
    r = min(r, w / 2, h / 2)
    qx = abs(px - w / 2) - (w / 2 - r)
    qy = abs(py - h / 2) - (h / 2 - r)
    return (math.hypot(max(qx, 0.0), max(qy, 0.0))
            + min(max(qx, qy), 0.0) - r)


def covers(inner, outer, steps=140):
    """Every point of rounded rect `inner` (w, h, r, x-offset) lies in `outer`."""
    iw, ih, ir, ix = inner
    ow, oh, orr = outer
    worst = -1e9
    for i in range(steps + 1):
        for j in range(steps + 1):
            px, py = iw * i / steps, ih * j / steps
            if sdf(px, py, iw, ih, ir) > 0:
                continue  # not part of the inner shape
            worst = max(worst, sdf(px + ix, py, ow, oh, orr))
    return worst


# -- 1. the meter fill is inside its track at every percent -------------------
# MeterPill: implicitHeight 64, radius `full`. The fill is the track's silhouette
# behind a scissor clip, never narrower than the pill is tall.
assert "radius: Appearance.rounding.full" in CODE, "meter pill lost its full radius"
assert "implicitHeight: 64" in CODE, "meter pill height changed -- re-derive the fill geometry"
assert "radius: pill.radius" in CODE, "the meter fill no longer takes the track's radius"
assert re.search(r"width:\s*Math\.max\(fillClip\.width,\s*pill\.height\)", CODE), \
    "the meter fill may now be narrower than the pill is tall -- Qt clamps its " \
    "radius to min(w, h)/2 and it becomes a thin capsule that escapes the left cap"
assert re.search(r"id: fillClip\b[\s\S]{0,400}?clip: true", CODE), \
    "the meter fill lost its scissor clip -- nothing bounds it to the track now"

FULL, H = 9999, 64
for track_w in (240, 380, 420):
    for pct in [i / 40 for i in range(41)]:
        w = track_w * pct
        if w <= 0:
            continue
        # What actually paints: the inner rect, widened to the cap diameter, then
        # scissored to `w`. The scissor can only remove area, so checking the
        # un-scissored inner rect is the stricter test.
        inner_w = max(w, H)
        worst = covers((inner_w, H, min(FULL, inner_w / 2, H / 2), 0.0),
                       (track_w, H, FULL))
        assert worst <= 1e-6, (
            f"meter fill escapes its track at {pct:.3f} of {track_w}px "
            f"(overshoot {worst:.3f}px) -- it needs the mask back")

# The bug this replaced, kept as a live counter-example: a fill that takes the
# percent as its own width really does escape, so the widening is load-bearing.
naive = covers((6.0, H, min(FULL, 3.0, H / 2), 0.0), (240, H, FULL))
assert naive > 1, "a narrow raw-width fill no longer escapes; re-derive this check"

# -- 2. the graph inset keeps the plot clear of the well's corner arcs --------
assert re.search(r"anchors\.leftMargin:\s*graphWell\.radius", CODE), \
    "the graph lost its left inset -- the plot can reach a corner arc again"
assert re.search(r"anchors\.rightMargin:\s*graphWell\.radius", CODE), \
    "the graph lost its right inset -- the plot can reach a corner arc again"

WELL_H, WELL_R = 48, 12  # implicitHeight 48, radius `rounding.small` (12)
for well_w in (120, 174, 240):
    plot_w = well_w - 2 * WELL_R
    # The Canvas is a plain rectangle: radius 0, offset right by the inset.
    worst = covers((plot_w, WELL_H, 0.0, float(WELL_R)), (well_w, WELL_H, WELL_R))
    assert worst <= 1e-6, (
        f"the plot paints outside the {well_w}px well (overshoot {worst:.3f}px)")

# A radius bigger than the inset would put the arc back under the plot.
assert WELL_R * 2 <= WELL_H, "well radius exceeds half its height; the clamp changes the arc"

# -- 3. the stagger counts visible siblings, and covers every child -----------
STEP, CAP = (int(re.search(rf"{n}: (\d+)", (pathlib.Path(__file__).parent.parent
             / "dots/.config/quickshell/ii/modules/common/Appearance.qml").read_text()).group(1))
             for n in ("staggerStep", "staggerCap"))


def get_delay(index, vis):
    return STEP * min(sum(1 for i in range(index) if vis[i]), CAP)


vis_list = re.search(r"_visList:\s*\[(.*?)\]\n", SRC, re.S).group(1)
n_children = vis_list.count(",") + 1
assert n_children == len(re.findall(r"delay: contentLayout\.getDelay\(\d+\)", CODE)), \
    "_visList and the children that read getDelay have drifted apart"
assert sorted(int(m) for m in re.findall(r"getDelay\((\d+)\)", CODE)) == list(range(n_children)), \
    "the stagger indices are not 0..n-1 exactly once"

for hidden in ([], [3], [5], [3, 5]):
    vis = [i not in hidden for i in range(n_children)]
    delays = [get_delay(i, vis) for i in range(n_children) if vis[i]]
    assert delays == sorted(delays), f"stagger goes backwards with {hidden} hidden"
    assert delays[:CAP + 1] == [STEP * i for i in range(min(len(delays), CAP + 1))], \
        f"stagger leaves a hole with {hidden} hidden: {delays}"
    assert max(delays) <= STEP * CAP, "stagger ran past the cap"

# -- 4. the effects themselves are actually gone ------------------------------
for effect in ("layer.enabled", "OpacityMask"):
    assert effect not in CODE, f"{effect} is back in ResourcesPopup.qml (DESIGN.md 8)"

print(f"ok: meter fill inside its track, plot inside its well, "
      f"stagger {STEP}ms x min(i, {CAP}) over {n_children} children with no holes, "
      f"no layer/mask in ResourcesPopup")
