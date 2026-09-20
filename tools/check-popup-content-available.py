#!/usr/bin/env python3
"""A popup's open condition must not ask its own content.

`StyledPopup` is a `LazyLoader`: its content is created when the popup opens and
**destroyed when it closes**. `contentAvailable` is ANDed into `_computedActive`,
so it decides whether the popup may open at all -- which means it is evaluated
while the content does not exist.

`ClockWidgetPopup` shipped this:

    contentAvailable: !Config.ready || columnLayout._visList.some(v => v)

`columnLayout` is inside the content. It opened once, and on close the id went
away, the binding threw, `contentAvailable` stopped being true and the popup
never opened again. Only that popup was affected, and only after the first
close, which is why nothing caught it: design-check sees no rule, qmllint
resolves ids lexically and is happy, and smoke.sh only proves the shell boots.

The rule: `contentAvailable` may read the root, singletons and literals. It may
not name an id declared inside the file, because every such id lives in the
content. Section conditions belong on the root, where they survive the close.

Run: python3 tools/check-popup-content-available.py
"""
import pathlib
import re

SHELL = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"

CONT = ("||", "&&", "?", ":", ".", "+", "-", "*", "/", ",", "(")


def expression(src: str, start: int) -> str:
    """The `contentAvailable:` binding, following operator continuations."""
    lines = src[start:].split("\n")
    out = [lines[0]]
    for nxt in lines[1:]:
        stripped = nxt.strip()
        if not stripped:
            break
        if not (out[-1].rstrip().endswith(CONT) or stripped.startswith(CONT)):
            break
        out.append(nxt)
    return "\n".join(out)


def declared_ids(src: str) -> set:
    # Unanchored: `Item { id: foo }` is legal QML and must be seen too. `\b`
    # keeps it off `grid:` and friends.
    return set(re.findall(r"\bid:\s*(\w+)", src))


def offenders(src: str) -> list:
    """Every id declared in this file that `contentAvailable` reads."""
    m = re.search(r"^[ \t]*contentAvailable:", src, re.M)
    if not m:
        return []
    expr = expression(src, m.start())
    root = re.search(r"\bid:\s*(\w+)", src)
    ids = declared_ids(src) - {root.group(1) if root else ""}
    return sorted(i for i in ids if re.search(rf"\b{i}\b", expr))


checked = 0
for path in sorted(SHELL.rglob("*.qml")):
    if "user_widgets" in path.parts:
        continue
    src = path.read_text()
    if not re.search(r"^[ \t]*contentAvailable:", src, re.M):
        continue
    checked += 1
    bad = offenders(src)
    assert not bad, (
        f"{path.relative_to(SHELL)}: contentAvailable reads "
        f"{', '.join(bad)}, declared inside the popup's own content.\n"
        "  The LazyLoader destroys that content on close, so the binding can "
        "answer only once and the popup never reopens.\n"
        "  Put the condition on the root, off config or a singleton."
    )

# The shipped bug, kept as a live counter-example so the rule cannot rot into a
# check that passes because it no longer looks at anything.
BROKEN = """
StyledPopup {
    id: root

    // a blank line above the binding is what hid this from the first draft
    contentAvailable: !Config.ready || columnLayout._visList.some(v => v)
    ColumnLayout {
        id: columnLayout
    }
}
"""
assert offenders(BROKEN) == ["columnLayout"], \
    "the check no longer catches the ClockWidgetPopup shape it was written for"

FIXED = """
StyledPopup {
    id: root
    readonly property bool hasAlarms: Config.options.time.alarms.showAlarmsSection
    contentAvailable: !Config.ready || root.hasClockFace
        || root.hasAlarms
    ColumnLayout {
        id: columnLayout
    }
}
"""
assert offenders(FIXED) == [], "the check rejects a correct root-derived condition"

print(f"ok: {checked} popup(s) gate opening on the root, not on content the "
      "LazyLoader destroys on close")
