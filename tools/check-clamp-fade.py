#!/usr/bin/env python3
"""A clamped box fades out what it cuts, and leaves no edge behind.

ClampBox holds long content at `maxHeight` with Show more under it, and paints
a gradient over the bottom of what it shows, ending in the surface it sits on,
to say the content goes on. Two things made the cut show instead (a turn of
yours with a code block in it, 2026-10-24):

- the gradient was only solid at its very last pixel, so a line the clip cut
  through still showed its upper half, sliced;
- a cut at half a pixel -- ten lines of the bubble's text land on one easily --
  gave the content the row it runs through, while the gradient, ending at the
  same height, left that row's centre out: a one-pixel line of unfaded content
  under the fade. Which way a half rounds depends on whether the scene is drawn
  y-up or y-down; drawn mirrored here, the offscreen grab rounds as the screen
  did, and the line shows in 15 of 16 half-pixel cuts.

This renders ClampBox as it is in a real Qt scene, upright and mirrored, over
content far brighter than the surface (the worst case for both), at whole,
half and other fractional cuts, and asserts from the pixels:

- the rows next to the cut on the content's side, and the row the cut runs
  through, are the surface's colour: nothing cut is left showing;
- the top of the fade still shows the content: it is a fade, not a wall.

Needs a Wayland session and quickshell (`qs -p`). The probe sits on the
background layer for about a second; its file is written into the shell dir
(the `qs.` imports only resolve there) and removed on exit.

    python3 tools/check-clamp-fade.py
"""
import json
import math
import os
import re
import subprocess
import tempfile
from pathlib import Path

SHELL = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
probe = SHELL / f".probe-clamp-fade-{os.getpid()}.qml"

SURFACE = (0x1f, 0x20, 0x21)
CONTENT = (0xff, 0xff, 0xff)
# (where the box starts, how much it shows): cuts at whole pixels, at halves --
# exactly and a hair either side -- and at other fractions.
CASES = [(8 + top, 60.5 - top + d) for top in (0, 0.25, 0.5, 0.75) for d in (-1e-5, 0, 1e-5, 0.5)]
CASES += [(8.5, 60.4), (8.25, 59.6), (9.4, 61.3)]
SLOT = 110
HEIGHT = SLOT * len(CASES)
# Rows next to the cut, on the content's side, that must be the surface alone.
HIDDEN = 8
FADE = 32

with tempfile.TemporaryDirectory() as tmp:
    shot = f"{tmp}/shot.ppm"
    probe.write_text("""//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets

ShellRoot {
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell:probe"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true }
        implicitWidth: 200
        implicitHeight: 200
        color: "SURFACE"

        Rectangle {
            id: scene
            width: 400
            height: HEIGHT
            color: "SURFACE"

            component Cuts: Item {
                width: 200
                height: HEIGHT
                Repeater {
                    model: CASES
                    Item {
                        id: slot
                        required property var modelData
                        required property int index
                        y: slot.index * SLOT
                        ClampBox {
                            x: 20
                            y: slot.modelData[0]
                            width: 160
                            maxHeight: slot.modelData[1]
                            colBase: "SURFACE"
                            // Content brighter than anything the shell draws, running
                            // far past the cut, with a clip of its own inside as a
                            // code block's scrolling text has.
                            Rectangle {
                                width: 160
                                height: 400
                                color: "CONTENT"
                                Flickable {
                                    width: 160
                                    height: 400
                                    contentHeight: 400
                                    clip: true
                                    Rectangle { width: 160; height: 400; color: "CONTENT" }
                                }
                            }
                        }
                    }
                }
            }

            Cuts {}
            Cuts { // Mirrored: a half pixel rounds the other way
                x: 200
                transform: [
                    Scale { yScale: -1 },
                    Translate { y: HEIGHT }
                ]
            }
        }
        Timer {
            interval: 900
            running: true
            onTriggered: scene.grabToImage(result => {
                result.saveToFile("SHOT");
                console.log("PROBE grabbed");
                Qt.quit();
            })
        }
    }
}
""".replace("HEIGHT", str(HEIGHT)).replace("SLOT", str(SLOT)).replace("CASES", json.dumps(CASES))
       .replace("SURFACE", "#%02x%02x%02x" % SURFACE).replace("CONTENT", "#%02x%02x%02x" % CONTENT).replace("SHOT", shot))
    try:
        out = subprocess.run(["timeout", "30", "qs", "-p", str(probe), "--no-color"], capture_output=True, text=True).stdout
    finally:
        probe.unlink(missing_ok=True)
    assert "PROBE grabbed" in out, f"the probe grabbed nothing:\n{out[-3000:]}"
    raw = Path(shot).read_bytes()

# Binary PPM: "P6\n<w> <h>\n<max>\n" then RGB.
header = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", raw)
assert header, "the grab is not a binary PPM"
width, height = int(header.group(1)), int(header.group(2))
assert (width, height) == (400, HEIGHT), f"the grab is {width}x{height}, not the scene"
pixels = raw[header.end():]


def at(x, y):
    i = (y * width + x) * 3
    return tuple(pixels[i:i + 3])


def near(a, b, slack=3):
    return all(abs(p - q) <= slack for p, q in zip(a, b))


for mirrored, x in ((False, 100), (True, 300)):
    way = "mirrored" if mirrored else "upright"
    for i, (top, shows) in enumerate(CASES):
        cut = i * SLOT + top + shows
        # Upright the content is above the cut; mirrored, below it. Every row the
        # last HIDDEN pixels before the cut touch -- the one it runs through too.
        if mirrored:
            cut = HEIGHT - cut
            hidden, faded, shown = range(math.floor(cut), math.ceil(cut + HIDDEN)), int(cut) + FADE - 2, int(cut) + FADE + 8
        else:
            hidden, faded, shown = range(math.floor(cut - HIDDEN), math.ceil(cut)), int(cut) - FADE + 2, int(cut) - FADE - 8
        for y in hidden:
            assert near(at(x, y), SURFACE), \
                f"{way}, cut at {cut:.5f}: row {y} is {at(x, y)}, not the surface {SURFACE} -- what the clip cut shows"
        assert sum(at(x, faded)) > sum(SURFACE) + 300, \
            f"{way}, cut at {cut:.5f}: the top of the fade (row {faded}) is {at(x, faded)}: a wall, not a fade"
        assert near(at(x, shown), CONTENT), f"{way}, cut at {cut:.5f}: above the fade (row {shown}) is {at(x, shown)}"

print(f"ok: a clamped box fades out what it cuts, with no edge left, at {len(CASES)} whole and fractional cuts, "
      f"either way up")
