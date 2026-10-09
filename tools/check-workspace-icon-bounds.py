#!/usr/bin/env python3
"""Keep Super-held workspace icons inside the monochrome effect's real bounds.

Expanding layer.sourceRect alone leaves MultiEffect sized to the smaller icon
row, so badges still get cropped. A padded Item owns both the layer and effect;
the row stays centered inside it. Check the rendered bounds through the elastic
morph, including its overshoot, for horizontal and vertical rows of many icons.

Run: python3 tools/check-workspace-icon-bounds.py
"""
import math
import pathlib
import re

shell = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
src = (shell / "modules/ii/bar/Workspaces.qml").read_text()
appearance = (shell / "modules/common/Appearance.qml").read_text()


def number(source, name):
    return float(re.search(rf"property \w+ {name}: ([\d.]+)", source)[1])


surface = src.split("id: iconSurface", 1)[1].split("id: layout", 1)[0]
assert "anchors.centerIn: parent" in surface
assert "layer.enabled:" in surface and "layer.effect: MultiEffect" in surface
assert "layer.sourceRect:" not in surface, "sourceRect cannot enlarge the effect's bounds"
padding_x = float(re.search(r"width: layout.implicitWidth \+ (\d+)", surface)[1]) / 2
padding_y = float(re.search(r"height: layout.implicitHeight \+ (\d+)", surface)[1]) / 2
assert "readonly property real heldIconSize: Math.min(Appearance.font.pixelSize.smallie, individualIconBoxHeight * iconRatio)" in src
assert "scale: root.showNumbersByMs ? root.heldIconSize / implicitSize : 1" in src
for axis in ("left", "top"):
    assert f"{axis}Margin: root.showNumbersByMs ? root.iconBoxWrapperSize - root.heldIconSize : 2" in src

cell = number(src, "individualIconBoxHeight")
full_size = cell * number(src, "iconRatio")
font_sizes = appearance.split("pixelSize: QtObject {", 1)[1].split("}", 1)[0]
held_size = min(number(font_sizes, "smallie"), full_size)
held_margin = number(src, "iconBoxWrapperSize") - held_size
period = float(re.search(r"easing.period: ([\d.]+)", src)[1])

for count in range(1, 9):
    for padding in (padding_x, padding_y):
        for frame in range(501):
            t = frame / 500
            progress = (0 if t == 0 else 1 if t == 1 else
                        1 + 2 ** (-10 * t) * math.sin((t - period / 4) * 2 * math.pi / period))
            for start, end in ((0, 1), (1, 0)):
                morph = start + (end - start) * progress
                margin = 2 + (held_margin - 2) * morph
                size = full_size + (held_size - full_size) * morph
                assert margin >= -padding, (count, frame, margin)
                assert (count - 1) * cell + margin + size <= count * cell + padding, (
                    count, frame, margin, size, padding)

print("ok: workspace icons fit the effect through hold/release overshoot in both orientations")
