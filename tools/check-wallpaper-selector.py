#!/usr/bin/env python3
"""The wallpaper selector leaves visibly, costs one mask for the whole grid, and
cannot be pointed at a folder that is not there.

- **The exit.** `Loader.active` read `GlobalStates.wallpaperSelectorOpen`, so the
  window was destroyed on the frame the flag cleared and no exit ever drew. It
  reads a latch now, which only the content's finished exit clears.
- **One mask.** Every tile carried an `OpacityMask` for its picture and another
  for a browser preview, plus a shadow: `check-effect-budget.py` never saw them,
  because the tile is its own file (the dock's blind spot). The grid holds one
  mask drawn from one rounded card per visible cell. That only works while the
  mask and the tile draw the card from the same numbers, and while the mask's
  scroll phase stays inside a cell, including past the top, where the
  rubber-band makes `contentY` negative. The phase is lifted out and swept.
- **The folder.** `setDirectory` assigned every path before it checked it, so a
  typo in the address bar or a stale rail entry replaced the folder with one
  that does not exist, and `FolderListModel` then lists the shell's working
  directory. The paths also went into `bash -c` as text: a folder with a space
  got no thumbnails, and a `"` in one ran code. So did the browser's remote
  download URL.

    python3 tools/check-wallpaper-selector.py
"""

import re
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
DIR = II / "modules/ii/wallpaperSelector"


def read(path):
    return re.sub(r"//.*", "", re.sub(r"/\*.*?\*/", "", path.read_text(), flags=re.S))


selector = read(DIR / "WallpaperSelector.qml")
content = read(DIR / "WallpaperSelectorContent.qml")
tile = read(DIR / "WallpaperDirectoryItem.qml")
image_bar = read(DIR / "ImageOptionsToolbar.qml")
color_bar = read(DIR / "ColorFilterToolbar.qml")
service = read(II / "services/Wallpapers.qml")

# The exit.
active = re.search(r"id: wallpaperSelectorLoader\s+active: (.+)", selector).group(1) + re.search(r"^\s+visible: (.+)", selector, re.M).group(1)
assert "wallpaperSelectorOpen" not in active, "Loader.active reads the open flag again: the exit is deleted"
assert "onClosed: root.rendered = false" in selector and "visible: root.rendered" in selector, "only the finished exit may unmap the window"
assert re.search(r"if \(surface\.reveal === 0 && !GlobalStates\.wallpaperSelectorOpen\) wallpaperSelectorContent\.closed\(\)", content), \
    "closed() must fire when the exit lands, not when it is asked for"
assert re.search(r"transform: Translate \{\s+y: -surface\.height \* \(1 - surface\.reveal\)", content), \
    "the surface hangs from the bar: it slides out from under it"
surface_block = content[content.index("id: surface"):content.index("StyledRectangularShadow")]
assert not re.search(r"^\s+(opacity|scale):", surface_block, re.M), "the sheet slides; it does not fade or scale (the owner's call)"
for name, bar in (("ImageOptionsToolbar", image_bar), ("ColorFilterToolbar", color_bar)):
    assert "ArrowPopupMotion" in bar and "visible: opacity > 0" in bar, f"{name} must leave on ArrowPopupMotion, not snap"
assert "imageToolbar.modelData = wallpaperSelectorContent.moreOptionsModelData" in image_bar, \
    "the contextual toolbar must keep its tile while it leaves, or its buttons change under the exit"

# One mask.
for effect in ("layer.enabled", "OpacityMask", "MultiEffect", "ShaderEffect", "Shadow"):
    assert effect not in tile, f"{effect} in WallpaperDirectoryItem, which repeats once per wallpaper"
assert content.count("OpacityMask") == 1 and "maskSource: tileMask" in content, "the grid should hold exactly one mask"
assert "loadTimer" not in content and "shouldLoad" not in content, "the per-frame tile release timer is back"
for prop in ("inset", "labelGap", "labelHeight"):
    assert re.search(rf"required property real {prop}\b", tile), f"the tile must take {prop} from the grid, not own it"
    assert f"{prop}: wallpaperSelectorContent.tile" in content, f"the grid must hand the tile its {prop}"
mask_card = re.search(r"readonly property real cardHeight: (.+)", content).group(1)
tile_card = re.search(r"readonly property rect cardRect: Qt\.rect\((.+)\)$", tile, re.M).group(1).split(", ")[3]
norm = lambda e: set(re.findall(r"[a-z]\w*", e.replace("grid.cellHeight", "H").replace("height", "H")
                                .replace("wallpaperSelectorContent.tile", "").lower()))
assert norm(mask_card) == norm(tile_card), f"mask card height ({mask_card}) and tile card height ({tile_card}) disagree"

phase_expr = re.search(r"readonly property real phase: \{(.+?)\n\s+\}", content, re.S).group(1)
assert "offset < 0 ? offset + grid.cellHeight" in phase_expr, "the phase must fold a negative offset back into the cell"


def phase(content_y, origin_y, cell):
    offset = (content_y - origin_y) % cell if content_y - origin_y >= 0 else -((origin_y - content_y) % cell)  # JS %
    return offset + cell if offset < 0 else offset


for cell in (160.5, 180, 237.25):
    for y in [i * 7.3 - 400 for i in range(400)]:
        p = phase(y, 0, cell)
        assert 0 <= p < cell, f"phase {p} out of [0, {cell}) at contentY {y}"
        assert abs(((y - p) / cell) - round((y - p) / cell)) < 1e-9, "the mask no longer lines up with a row"

# The folder.
handler = re.search(r"onStreamFinished: \{(.+?)\n            \}", service, re.S).group(1)
assert re.search(r'if \(result === "dir"\) \{\s+root\.directory = ', handler), \
    "setDirectory must assign the directory only once the path is known to be one"
assert handler.count("root.directory =") == 2, "an unconditional assignment is back in setDirectory"
for name, text in (("Wallpapers.qml", service), ("ImageOptionsToolbar.qml", image_bar)):
    for script in re.findall(r'"bash", "-c",\s*([\'`"].*?[\'`"]),', text, re.S):
        assert "${" not in script, f"{name} interpolates into a bash -c script again: {script[:60]}"
assert "wallpapers.paths.download" not in image_bar, "Config.options.wallpapers.paths.download does not exist"
assert 'current.startsWith("/")' in service, "the folder must open where the applied wallpaper is, which exists"

print("ok: wallpaper selector latched on its exit, one grid mask in step with the tile, folders validated")
