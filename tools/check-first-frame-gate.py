#!/usr/bin/env python3
"""A popup's open waits until its window can draw every frame of it.

The first visible frame of a popup is the first time Qt renders its content in
that window. On the dock menu and the bar popups it cost 50-110ms (measured
2026-10-05, 60fps recordings), and with this many windows the animation clock is
wall time: the open jumped that far, its first frames repeated one early state
and the grow resumed 40% of the way in. `FirstFrameGate` pays for that frame while
nothing shows, then lets the open start. What this guards:

- the warm opacity is above Qt's cull (QSGOpacityNode blocks a subtree under
  0.001, so 0 would warm nothing) and below 1/255, so it never shows;
- the gate times frames on `afterAnimating`, the GUI thread's. `frameSwapped` and
  the rendering signals arrive on the render thread, where no JS may run;
- the "steady" interval stays under two 60Hz frames, so a blocked frame (50ms+)
  can never pass for a drawn one;
- `ArrowPopupMotion.open()` and a new `StyledPopup` both start through the gate,
  not by starting their open animation directly.

Run: python3 tools/check-first-frame-gate.py
"""
import pathlib
import re

SHELL = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
GATE = (SHELL / "modules/common/widgets/FirstFrameGate.qml").read_text()
MOTION = (SHELL / "modules/common/widgets/ArrowPopupMotion.qml").read_text()
POPUP = (SHELL / "modules/ii/bar/StyledPopup.qml").read_text()

QT_CULL = 0.001  # QSGOpacityNode::isSubtreeBlocked
RENDER_THREAD = ("onFrameSwapped", "onBeforeRendering", "onAfterRendering",
                 "onBeforeSynchronizing", "onAfterSynchronizing", "onBeforeRenderPassRecording")


def body(src: str, head: str) -> str:
    """The brace-balanced block that starts at `head`."""
    i = src.index(head)
    i = src.index("{", i)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i:j + 1]
    raise AssertionError(f"unbalanced block after {head!r}")


warm = float(re.search(r"warmOpacity:\s*([0-9.]+)", GATE).group(1))
assert QT_CULL < warm < 1 / 255, f"warmOpacity {warm} must be in ({QT_CULL}, 1/255)"

assert "onAfterAnimating" in GATE, "the gate must time frames on afterAnimating"
for sig in RENDER_THREAD:
    assert sig not in GATE, f"{sig} runs JS on the render thread"

steady = int(re.search(r"now - root\._lastFrame >= (\d+)", GATE).group(1))
assert 1000 / 60 < steady <= 2 * 1000 / 60 + 1, f"steady interval {steady}ms must sit within two 60Hz frames"

opened = body(MOTION, "function open()")
assert "_gate.hold()" in opened and "warmOpacity" in opened, "ArrowPopupMotion.open() must warm and hold"
assert "openAnim.restart()" not in opened, "ArrowPopupMotion.open() must not start the open itself"
assert "onReady: openAnim.restart()" in MOTION, "the gate's ready must start the open"
assert "_gate.cancel()" in body(MOTION, "function close()"), "a close must cancel a held open"

created = body(POPUP, "        Component.onCompleted:")
assert "firstFrames.hold()" in created and "warmOpacity" in created, "a new StyledPopup must warm and hold"
assert "openAnim.start()" not in created, "a new StyledPopup must not start its open itself"
assert "firstFrames.cancel()" in POPUP, "a StyledPopup close must cancel a held open"

print("check-first-frame-gate: ok")
