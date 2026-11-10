#!/usr/bin/env python3
"""A window preview comes back after Hyprland fails one of its frames.

Hyprland fails a window frame whose buffer no longer fits the window: a resize
between the request and the copy, so every frame of a re-tile. One probe
(2026-11-10, Hyprland 0.57.1) saw 400-500ms of failed frames per re-tile.
Quickshell's ScreencopyView answers the first failure by deleting its capture
context, and it makes another only when `captureSource` changes to a different
object; `live` and `captureFrame()` do nothing without one. The overview keeps
its window delegates for the whole session, so one re-tile, a window dragged to
another workspace for example, left that preview blank until the shell
restarted. Nothing was logged but a WARN, and every other window still showed.

`ToplevelScreencopyView` re-arms its source (null, then the window again) while
it has no frame. What this guards:

- the re-arm runs only while there is no frame, there is a window, and `retry`
  holds, so a window that cannot be captured costs nothing once hidden;
- it fires at once when it starts, so a capture that died while the overview was
  closed is back on the first frame of the next open, not an interval later;
- the interval stays under the measured re-tile, so the blank after one lasts
  about as long as the window takes to settle;
- no window preview in the ii family or the shared widgets is a bare
  ScreencopyView (screen captures, `captureSource: root.screen`, stay bare: an
  output capture is not resized under it), and each one's `retry` follows
  whether it is shown.

Run: python3 tools/check-toplevel-screencopy.py
"""
import pathlib
import re

SHELL = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
VIEW = (SHELL / "modules/common/widgets/ToplevelScreencopyView.qml").read_text()
RETILE_MS = 400  # shortest failure span measured for one re-tile


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


assert re.search(r"captureSource:\s*armed \? toplevel : null", VIEW), \
    "the capture source must follow `armed`, or toggling it re-arms nothing"
rearm = body(VIEW, "function rearm()")
assert rearm.index("armed = false") < rearm.index("armed = true"), \
    "rearm() must drop the source and then set it again"

timer = body(VIEW, "    Timer {")
running = re.search(r"running:\s*(.+)", timer).group(1)
for term in ("root.retry", "root.toplevel", "!root.hasContent"):
    assert term in running, f"the re-arm timer must run only with {term}"
assert "repeat: true" in timer, "a re-tile fails several frames in a row: keep retrying"
assert "triggeredOnStart: true" in timer, "a capture that died while hidden must come back on open"
assert "onTriggered: root.rearm()" in timer

interval = int(re.search(r"property int retryInterval:\s*(\d+)", VIEW).group(1))
assert 0 < interval < RETILE_MS, f"retryInterval {interval}ms must be under one re-tile ({RETILE_MS}ms)"

previews = 0
for path in sorted([*(SHELL / "modules/ii").rglob("*.qml"), *(SHELL / "modules/common").rglob("*.qml")]):
    if path.name == "ToplevelScreencopyView.qml":
        continue
    src = path.read_text()
    rel = path.relative_to(SHELL)
    for m in re.finditer(r"\bScreencopyView\s*\{", src):
        block = body(src, src[m.start():m.end()])
        source = re.search(r"captureSource:\s*(.+)", block)
        assert source and "screen" in source.group(1), \
            f"{rel}: a window preview must be a ToplevelScreencopyView, not a bare ScreencopyView"
    for m in re.finditer(r"\bToplevelScreencopyView\s*\{", src):
        block = body(src, src[m.start():m.end()])
        assert "captureSource:" not in block, f"{rel}: set `toplevel`, not `captureSource`"
        assert re.search(r"\bretry:", block), f"{rel}: bind `retry` to whether the preview is shown"
        previews += 1

assert previews >= 2, "the overview and the dock both show window previews"
print(f"ok: {previews} window previews re-arm a failed capture, every {interval}ms while shown")
