#!/usr/bin/env python3
"""A `PanelWindow` never masks an item that carries a transform.

`mask: Region { item: x }` is how every click-through surface in this shell
carves out the part of a full-screen layer that should take input. The region is
computed from the masked item's rect *with its transform applied*, and it is
recomputed when that item's **geometry** changes -- not when its `scale`,
`transform` or `transformOrigin` does.

So an item that rests at a scale and animates to 1 bakes the resting scale into
the input region and never refreshes it. Nothing about that is visible: the
surface paints at full size, the pointer changes shape nowhere, no warning is
printed, and the clicks land in whatever window is behind. The drop shelf shipped
that way -- `mask: Region { item: shelfCard }` with the card resting at
`arrowPopupScale` (0.5) -- so the input region was a half-size rectangle in the
middle of the card, and the close button, both actions and the entire drop target
were dead. The only way to get rid of the shelf was to restart the shell.

The fix is always the same shape: mask a plain `Item` that holds the geometry,
and put the `scale`/`opacity`/`transform` on a child that fills it.

    python3 tools/check-mask-regions.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"

# Properties that move or resize the painted item without touching its geometry,
# which is exactly the set the region does not follow.
TRANSFORMS = ("scale:", "transformOrigin:", "transform:")

# Two surfaces predate this gate. Both were swept with the same click grid that
# found the drop shelf's; what each one measured is written next to it, because
# "same shape" is not the same claim as "same bug".
KNOWN = {
    # The pilot surface, same shape at a milder scale -- the card rests at 0.8, so
    # this would be the outer ~10% of the toast rather than the outer 50%.
    # **Not measured**: the toast would not trigger from `wl-copy` in the session
    # that found this, so whether its geometry settles late enough to re-bake the
    # region at 1 is unknown. Left alone rather than fixed blind, because the card
    # also carries a `transform: Translate` for swipe-to-dismiss and its x/y move
    # whenever a sidebar opens, so wrapping it changes what the drag grabs.
    "modules/ii/clipboardToast/ClipboardToast.qml": "card",

    # **Measured clean**: a 3x3 grid over the open sheet landed 9/9 at scale 1.
    # Its content loads lazily, so implicitWidth/implicitHeight change after the
    # reveal has finished and re-bake the region at full size. That is an accident
    # of load order rather than a design, which is why it stays listed.
    "modules/ii/cheatsheet/Cheatsheet.qml": "cheatsheetBackground",
}


def masked_items(src):
    """Every `mask: Region { item: <id> }` in a file, as (line, id)."""
    out = []
    for m in re.finditer(r"mask:\s*Region\s*\{(.*?)\n\s*\}", src, re.S):
        item = re.search(r"\bitem:\s*([A-Za-z_]\w*)\s*$", m.group(1), re.M)
        if item and item.group(1) != "null":
            out.append((src[: m.start()].count("\n") + 1, item.group(1)))
    return out


def declares_transform(src, item_id):
    """The properties set on the object that declares `id: <item_id>`.

    Scoped by brace depth from the `id:` line, so a transform on a child does not
    count -- a child is exactly where it is supposed to be.
    """
    m = re.search(rf"^([ \t]*)id:\s*{re.escape(item_id)}\s*$", src, re.M)
    if not m:
        return []
    indent = len(m.group(1))
    found = []
    for line in src[m.end():].split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        here = len(line) - len(line.lstrip())
        if here < indent:  # left the object
            break
        if here != indent:  # inside a child
            continue
        for prop in TRANSFORMS:
            if stripped.startswith(prop):
                found.append(stripped.split(":")[0])
    return found


def main():
    hits = []
    for path in sorted(SHELL.rglob("*.qml")):
        rel = path.relative_to(SHELL).as_posix()
        if rel.startswith("user_widgets/"):
            continue
        src = path.read_text()
        for line, item in masked_items(src):
            props = declares_transform(src, item)
            if not props:
                continue
            if KNOWN.get(rel) == item:
                print(f"known  {rel}:{line}  masks `{item}` ({', '.join(props)})")
                continue
            hits.append((rel, line, item, props))

    for rel, line, item, props in hits:
        print(f"FAIL   {rel}:{line}  masks `{item}`, which sets {', '.join(props)}")
        print("         the input region bakes that transform and never refreshes;")
        print("         mask a plain Item holding the geometry and scale a child of it")

    if hits:
        sys.exit(1)
    print(f"ok  no masked item carries a transform ({len(KNOWN)} known, argued in KNOWN)")


if __name__ == "__main__":
    main()
