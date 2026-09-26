#!/usr/bin/env python3
"""A list that follows its end gets there without rebuilding every row, forever.

positionViewAtEnd() on a last row the view has not built makes Qt throw every row
away and rebuild them around a guessed position. A Hermes turn is built short -- its
text wraps a frame later, once its layout hands it a width -- so the rebuilt row
straddling the top of the view grew, shoved the end out of the view and out of the
cache, and the follow pinned again: a rebuild every other frame, contentY racing
~5000px a time over a blank view, until a scroll broke it off wherever it had got
to. The Scroll to Bottom button was the usual way in, since it only shows when the
end is far enough away not to be built.

None of it has a still frame. What is pinned:
- `jumpToEnd` calls positionViewAtEnd() only behind `itemAtIndex(count - 1)`, and
  otherwise walks, at most one page a frame (more is Qt's "jumped more than a page",
  which rebuilds everything the same way);
- the follow is not gated on `atYEnd` in `onContentHeightChanged`: Flickable emits
  that signal before it updates `atYEnd`, so the gate read the view as still on the
  end and left any growth that landed there hanging below it;
- the button scrolls through `scrollToEnd` on the programmatic scroll spec, not on a
  curve of its own (an overshooting one bounced the list past its end, DESIGN.md 3.6);
- Hermes never calls positionViewAtEnd() itself, and never clamps contentY against
  a bare contentHeight, which ignores where the estimated content starts (originY).
"""
import re
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
# Code only: the comments explaining this name the calls they forbid.
lv = "\n".join(line for line in (II / "modules/common/widgets/StyledListView.qml").read_text().splitlines()
               if not line.lstrip().startswith(("*", "/*", "//")))
button = (II / "modules/ii/sidebarPolicies/ScrollToBottomButton.qml").read_text()
hermes = (II / "modules/ii/sidebarPolicies/Hermes.qml").read_text()


def body(src: str, head: str) -> str:
    start = src.index(head)
    depth, i = 0, src.index("{", start)
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i:j + 1]
    raise AssertionError(f"unterminated block after {head!r}")


jump = body(lv, "function jumpToEnd()")
calls = [m.start() for m in re.finditer(r"positionViewAtEnd\(\)", lv)]
assert len(calls) == 1 and "positionViewAtEnd()" in jump, \
    "StyledListView: positionViewAtEnd() must appear once, inside jumpToEnd"
guard = jump.find("itemAtIndex(root.count - 1)")
assert 0 <= guard < jump.index("positionViewAtEnd()"), \
    "StyledListView: jumpToEnd reaches positionViewAtEnd() without checking the last row is built"

walk = body(lv, "id: endWalk")
steps = re.findall(r"root\.contentY \+ ([^,)]+)", walk)
assert steps and all(s.strip() == "root.height" for s in steps), \
    f"StyledListView: the walk must step at most one page a frame, found {steps}"
assert "!root.followingEnd" in walk, "StyledListView: the reader's own scroll no longer ends the walk"

follow = body(lv, "onContentHeightChanged:")
assert "atYEnd" not in follow, \
    "StyledListView: onContentHeightChanged reads atYEnd, which Flickable has not updated yet when it fires"
assert "Qt.callLater(root.jumpToEnd)" in follow, "StyledListView: the follow no longer re-pins through jumpToEnd"

to_end = body(lv, "function scrollToEnd()")
assert "root.jumpToEnd()" in to_end and "root.contentY = root.endY" in to_end, \
    "StyledListView: scrollToEnd must scroll a built, close end and jump otherwise"
assert not re.search(r"NumberAnimation\s*\{[^}]*property:\s*\"contentY\"", lv), \
    "StyledListView: contentY has an animation of its own; programmatic scrolling is the `scroll` spec"

assert re.search(r"downAction:\s*\(\)\s*=>\s*target\.scrollToEnd\(\)", button), \
    "ScrollToBottomButton: the button must go through scrollToEnd()"

assert "positionViewAtEnd" not in hermes, "Hermes: call jumpToEnd(), not positionViewAtEnd()"
for m in re.finditer(r"messageListView\.contentY\s*=\s*(.+);", hermes):
    assert not re.search(r"contentHeight|Math\.max\(0,", m.group(1)), \
        f"Hermes: `{m.group(1)}` clamps against a bare contentHeight or 0, ignoring originY"

print("ok: the end is walked to rather than rebuilt, and the follow is not gated on a stale atYEnd")
