#!/usr/bin/env python3
"""The shell's JS is ES2018-ish; nothing in it may call what the engine lacks.

Quickshell runs QML on Qt's V4 engine, which (Qt 6.12, Quickshell 0.3.2) has
no Object.fromEntries, trimEnd, flatMap, replaceAll, at, findLast and the rest
listed below. node has all of them, so the checks that run the shell's JS
under node pass while the shell itself throws a TypeError at the call - in a
signal handler, which aborts it quietly at that line. That is how a Fast Pair
card could not be dismissed, floating mode never learned which windows draw
their own title bars, cover art stopped after one failed download and the
MPRIS page-url map was never pruned: each was one Object.fromEntries call.

The list was taken from the engine itself: each name was called inside
`qs -p` and threw. Grow it the same way, never from a compatibility table.
Tests that run only under node (`*.test.js`, `test_*.js`) are exempt.

Run: python3 tools/check-js-engine.py
"""

import re
import sys
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"

MISSING = re.compile(
    r"\bObject\.(fromEntries|hasOwn|groupBy)\s*\("
    r"|\.(trimEnd|trimStart|trimLeft|trimRight|flatMap|flat|replaceAll|at|findLast|findLastIndex"
    r"|matchAll|toSorted|toReversed|toSpliced|isWellFormed)\s*\("
    r"|\bPromise\.(allSettled|any)\s*\("
    r"|\bArray\.fromAsync\s*\("
    r"|\bstructuredClone\s*\("
)


def node_only(path):
    return path.name.endswith(".test.js") or path.name.startswith("test_")


def code_lines(text):
    """Lines with // comments cut, so a comment may name what it avoids."""
    for number, line in enumerate(text.splitlines(), 1):
        yield number, re.sub(r"(^|\s)//.*$", "", line)


found = []
for path in sorted([*II.rglob("*.qml"), *II.rglob("*.js")]):
    if node_only(path):
        continue
    for number, line in code_lines(path.read_text(errors="replace")):
        for match in MISSING.finditer(line):
            found.append(f"{path.relative_to(II)}:{number}: {match.group(0).rstrip('(').strip()}")

assert not found, "not in the shell's JS engine (throws at runtime):\n  " + "\n  ".join(found)
print("ok: no shell QML or JS calls a method the V4 engine lacks")
