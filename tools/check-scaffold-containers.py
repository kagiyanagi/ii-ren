#!/usr/bin/env python3
"""The page/section/scroll containers keep what cw-scaffolding gave them.

Three things that only show up by driving the settings app, and one of which Qt
reports at runtime and nowhere else:

1. A collapsible section header is an interactive element, so it renders hover,
   focus and pressed (DESIGN.md 3.1) and is reachable from the keyboard (3.7).
   `check-button-states.py` cannot see it: the header is a MouseArea, not a
   QQC2 Button.
2. No direct child of a layout anchors itself. Qt calls that "undefined
   behavior" out loud at runtime -- 11 times in one settings session before this
   row -- and qmllint says nothing at all about it.
3. The two show/hide containers name a different spec for entering than for
   leaving (2.5). One shared spec is the easy "simplification" that puts the
   asymmetry back on the floor.
4. Neither flickable scales its content. The Android stretch overscroll was
   built here, anchored the wrong way, fixed, watched on a real desktop and
   removed as glitchy on 2026-09-20 (DESIGN.md 3.6). It is the one deliberate
   departure from Android in this shell, so it needs a check that says so --
   otherwise the next reader of 2.6 builds it again.
5. An Item wrapping a child for a layout reports both implicit dimensions. The
   header rewrite in (2) reported only a height, and a section is sized by its
   header: every `ConfigRow` cell with `Layout.fillWidth: false` collapsed to
   zero, stacked its chips in a column and left the card a 4px sliver. Nothing
   warns -- not Qt, not qmllint, not check-design.py.

6. ContentPage's page header is the shared RippleButton and vanishes for a
   titleless page. 61 sub-pages deleted their own copy against it, and a
   header that stops hiding itself widens 14 callers that never had one.

Usage: python3 tools/check-scaffold-containers.py
"""

import re
import sys
from pathlib import Path

WIDGETS = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii/modules/common/widgets"

FAMILY = [
    "ContentPage", "ContentGroup", "ContentSection", "ContentSubsection",
    "ContentSubsectionLabel", "PagePlaceholder", "StyledFlickable",
    "StyledScrollBar", "ScrollEdgeFade", "StyledListView", "WheelScrollHandler",
    "FocusedScrollMouseArea", "Revealer", "FadeLoader",
]

SECTIONS = ["ContentSection", "ContentSubsection"]
LAYOUT_TYPES = ("RowLayout", "ColumnLayout", "GridLayout", "Row", "Column", "Grid", "Flow")

failures = []


def fail(what):
    failures.append(what)


def src(name):
    return (WIDGETS / f"{name}.qml").read_text()


# --- 1. the collapsible header renders four states and takes the keyboard -----

def block_at(text, opener):
    """The brace block that `opener` opens, opener's own `{` through its match."""
    i = text.index(opener) + len(opener) - 1
    depth = 0
    for k in range(i, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return text[i:k + 1]
    return text[i:]


def block_containing(text, needle):
    """The innermost brace block that encloses `needle`."""
    depth = 0
    start = 0
    for j in range(text.index(needle), -1, -1):
        if text[j] == "}":
            depth += 1
        elif text[j] == "{":
            if depth == 0:
                start = j
                break
            depth -= 1
    return block_at(text[start:], "{")


def check_header_states(name):
    s = src(name)

    if "StateOverlay {" not in s:
        fail(f"{name}: no StateOverlay -- the collapsible header has no state film "
             f"(3.1 ranks colLayerNHover first and StateOverlay second; a colour "
             f"ternary is neither)")
        return

    overlay = block_at(s, "StateOverlay {")
    for prop, token in (("hover", "0.08"), ("focused", "0.10"), ("press", "0.10")):
        if not re.search(rf"\b{prop}:\s*\w", overlay):
            fail(f"{name}: StateOverlay does not bind `{prop}` -- the {token} state layer never renders")

    if "id: headerArea" not in s:
        fail(f"{name}: no headerArea -- nothing drives the state film")
        return
    area = block_containing(s, "id: headerArea")

    if not re.search(r"activeFocusOnTab:\s*true", area):
        fail(f"{name}: header is not in the tab chain (3.7)")
    if not re.search(r"Keys\.onPressed", area):
        fail(f"{name}: header has no keyboard activation -- focus that cannot act is not reachable (3.7)")
    # A pointing hand over a title nobody can click is worse than no cursor at
    # all, so the interaction only exists when the section actually collapses.
    if not re.search(r"visible:\s*root\.collapsible", area):
        fail(f"{name}: the header MouseArea is not gated on `collapsible` -- "
             f"a non-collapsible title claims a pointing-hand cursor")
    if not re.search(r"visible:\s*root\.collapsible", overlay):
        fail(f"{name}: the header StateOverlay is not gated on `collapsible`")


# --- 2. nothing anchors a direct child of a layout ----------------------------

OPEN_BLOCK = re.compile(r"(?:^|\s)([A-Z][A-Za-z0-9_.]*)\s*\{\s*$")
ANCHOR = re.compile(r"^\s*anchors(\.[a-zA-Z]+)?\s*[:{]")


def check_no_anchors_in_layout(name):
    """Walk brace depth and flag `anchors` written in a block whose *parent*
    block is a positioner. The item's own anchors are then fighting the layout
    for its geometry, which is the shape Qt warns about."""
    stack = []  # one frame per open brace: the type that opened it, or ""
    for lineno, line in enumerate(src(name).splitlines(), 1):
        code = line.split("//", 1)[0]

        if ANCHOR.match(code) and len(stack) >= 2 and stack[-2] in LAYOUT_TYPES:
            fail(f"{name}:{lineno}: `{code.strip()}` on a direct child of {stack[-2]} -- "
                 f"Qt calls anchors on a layout-managed item undefined behavior")

        # OPEN_BLOCK only matches a trailing `{`, so at most one frame per line
        # carries a type name; every other brace pushes an anonymous frame.
        m = OPEN_BLOCK.search(code)
        pending = m.group(1) if m else None
        for ch in code:
            if ch == "{":
                stack.append(pending or "")
                pending = None
            elif ch == "}" and stack:
                stack.pop()


# --- 3. entering and leaving are not the same spec ----------------------------

ENTER_SPECS = ("elementMove", "elementMoveEnter", "elementMoveSmall", "elementMoveFast", "emphasizedDecel")
EXIT_SPECS = ("elementMoveExit", "emphasizedAccel")

# The shape that silently breaks the asymmetry: resolving the direction in a
# binding of its own. A Behavior bakes its spec when the binding that writes its
# property runs, and that can happen before this one has been re-evaluated, so
# the exit gets the enter's spec. Assign it from inside the driving binding.
STALE_SPEC = re.compile(r"property\s+AnimSpec\s+\w+\s*:.*\?")


def check_enter_and_exit(name):
    s = src(name)
    named = lambda spec: re.search(rf"animation\.{spec}\b", s)
    if not any(named(spec) for spec in ENTER_SPECS):
        fail(f"{name}: names no enter spec")
    if not any(named(spec) for spec in EXIT_SPECS):
        fail(f"{name}: names no exit spec -- it appears on one timing and leaves on the same one (2.5)")
    m = STALE_SPEC.search(s)
    if m:
        fail(f"{name}: `{m.group(0)[:60]}` resolves the direction in its own binding -- "
             f"the Behavior can read it before it updates and run the exit on the enter's "
             f"spec (2.9). Assign it from inside the binding that drives the animation")


for section in SECTIONS:
    check_header_states(section)

for widget in FAMILY:
    check_no_anchors_in_layout(widget)

for widget in ("Revealer", "PagePlaceholder"):
    check_enter_and_exit(widget)

missing = [w for w in FAMILY if not (WIDGETS / f"{w}.qml").exists()]
if missing:
    fail(f"family member(s) gone: {', '.join(missing)} -- update this list with the queue row")

# --- 4. a wrapper Item reports both implicit dimensions -----------------------

def item_blocks(text):
    """Every `Item { ... }` block in the file, outermost first."""
    for m in re.finditer(r"\bItem\s*\{", text):
        yield block_at(text[m.start():], "Item {")


def check_wrapper_implicit_size(name):
    s = src(name)
    for block in item_blocks(s):
        # only the ones standing in for a child inside a layout
        if "implicitHeight:" not in block:
            continue
        if "Layout." not in block:
            continue
        if "implicitWidth:" not in block:
            head = block.strip().splitlines()[1].strip() if len(block.splitlines()) > 1 else block[:40]
            fail(f"{name}: an Item reports implicitHeight but no implicitWidth ({head!r}) -- "
                 "a section is sized by it, so a non-filling cell collapses to zero")


for n in SECTIONS:
    check_wrapper_implicit_size(n)


# --- 5. no overscroll stretch ------------------------------------------------

STRETCHERS = ["StyledFlickable", "StyledListView"]


def check_no_stretch(name):
    s = src(name)
    if re.search(r"contentItem\.transform", s):
        fail(f"{name}: sets `contentItem.transform` -- the overscroll stretch was removed on "
             "2026-09-20 for being glitchy (DESIGN.md 3.6). Scaling the content is what it was")
    if "verticalOvershoot" in s:
        fail(f"{name}: reads `verticalOvershoot` -- that only ever fed the stretch, and with "
             "`boundsMovement` back at its default a drag past the end already rubber-bands")
    if "StopAtBounds" in s:
        fail(f"{name}: sets `boundsMovement: StopAtBounds` -- that was the hook the stretch "
             "drew from, and it holds the content still during a drag past the end")


for n in STRETCHERS:
    check_no_stretch(n)


WHEEL = (WIDGETS / "WheelScrollHandler.qml").read_text()
if re.search(r"(?<![A-Za-z])[oO]verscroll", WHEEL):
    fail("WheelScrollHandler still accumulates overscroll -- nothing draws it any more, and "
         "piling it up means eating wheel turns at a bound for nothing")


# --- 6. ContentPage's page header ---------------------------------------------
# 61 settings sub-pages hand-rolled the same header before sw-clock-configs moved
# it here. Two things have to hold, and neither is visible in a diff of one page:
# the back button has to be the shared RippleButton (so it inherits all four
# states rather than re-mixing two of them), and the header has to disappear
# entirely for a page that sets no title -- ContentPage reports
# contentColumn.implicitWidth, and a header that is merely transparent would
# widen all 14 titleless callers. Decision 21 is what a silent width change costs.

PAGE = src("ContentPage")

for prop in ("property string title", "property bool showBackButton", "signal goBack"):
    if prop not in PAGE:
        fail(f"ContentPage: no `{prop}` -- ConfigSubPageHost loads sub-pages against "
             "showBackButton and goBack, and the 61 pages get their header from title")

header = re.search(r"RowLayout \{(.*?)\n        \}", PAGE, re.S)
if not header:
    fail("ContentPage: no header RowLayout -- the 61 copies were deleted against it")
else:
    h = header.group(1)
    if not re.search(r'visible:\s*root\.title !== ""', h):
        fail('ContentPage: the header is not gated on `visible: root.title !== ""` -- a '
             "ColumnLayout only skips an invisible child, and every titleless caller "
             "would gain the header's width (decision 21)")
    if "RippleButton" not in h:
        fail("ContentPage: the header's back button is not a RippleButton -- hand-rolling "
             "it is what put 61 copies of two of the four states in this directory")
    for tok in ("Appearance.sizes.pageHeaderButtonSize", "Appearance.rounding.full"):
        if tok not in h:
            fail(f"ContentPage: header does not use {tok} -- the 40dp was written four "
                 "different ways across the copies, one of them as arithmetic")


if failures:
    print("FAIL: scaffolding containers")
    for f in failures:
        print(f"  {f}")
    sys.exit(1)

print(f"ok: {len(SECTIONS)} collapsible headers render hover, focus and pressed and take the keyboard")
print(f"ok: {len(FAMILY)} scaffolding files anchor nothing a layout manages")
print("ok: Revealer and PagePlaceholder specify both directions")
print(f"ok: {len(SECTIONS)} sections report an implicit width, so a non-filling cell keeps its card")
print(f"ok: {len(STRETCHERS)} flickables scale nothing -- no overscroll stretch (3.6)")
print("ok: ContentPage carries the page header, gated on title, on a shared RippleButton")
