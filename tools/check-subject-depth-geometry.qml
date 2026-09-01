// Run: QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_LOGGING_RULES="qml.warning=true" \
//        /usr/lib/qt6/bin/qml tools/check-subject-depth-geometry.qml
//
// Checks the one piece of Background.qml nobody can eyeball: the subject-depth
// cutout lives inside the widget canvas so a single `z` per widget decides
// which side of the subject it lands on, but it has to draw exactly on the
// wallpaper - which is a sibling, parallaxes at a different rate, and squares
// up to the screen when the lock screen centres the canvas. Exits non-zero if
// any of those states pulls the two apart.

import QtQuick
import QtQuick.Window

// Reproduces Background.qml's nesting exactly: `wallpaper` and `widgetCanvas`
// are siblings under wallpaperItem, and the subject layer lives inside the
// canvas but has to land on the wallpaper, whatever the canvas is doing.
Window {
    visible: true
    width: 1920; height: 1080

    Item {
        id: wallpaperItem
        anchors.fill: parent
        // The desktop plane's own zoom - 1.04 by default, since
        // overview.scrollingStyle.zoomStyle is "in". The cutout rides it along
        // with the wallpaper, so it has to cancel out rather than show up here.
        scale: 1.04

        Item {
            id: wallpaper
            width: 2100; height: 1200
            x: -140; y: -80
        }

        Item {
            id: widgetCanvas
            width: wallpaper.width; height: wallpaper.height
            x: 0; y: 0
            scale: 1

            Item {
                id: subjectLayer

                width: wallpaper.width
                height: wallpaper.height
                scale: 1 / widgetCanvas.scale
                x: (wallpaper.x - widgetCanvas.x + (width - widgetCanvas.width) / 2) / widgetCanvas.scale
                    + (widgetCanvas.width - width) / 2
                y: (wallpaper.y - widgetCanvas.y + (height - widgetCanvas.height) / 2) / widgetCanvas.scale
                    + (widgetCanvas.height - height) / 2
            }
        }

        // Screen coordinates, not plane coordinates: the plane's own scale is
        // exactly what the video case has to cancel, so measuring inside it
        // would hide the bug.
        // Returns 1 if the cutout missed the rect it is supposed to land on.
        function compare(want, label) {
            var got = rectOf(subjectLayer);
            var off = 0;
            for (var k = 0; k < 4; k++)
                off = Math.max(off, Math.abs(want[k] - got[k]));
            var ok = off < 0.001;
            console.warn((ok ? "ok   " : "FAIL ") + label
                + "\n        want [" + want.map(function (v) { return v.toFixed(2); }).join(", ") + "]"
                + "  got [" + got.map(function (v) { return v.toFixed(2); }).join(", ") + "]"
                + "  offset " + off.toFixed(4) + "px");
            return ok ? 0 : 1;
        }

        function rectOf(item) {
            var tl = item.mapToItem(null, 0, 0);
            var br = item.mapToItem(null, item.width, item.height);
            return [tl.x, tl.y, br.x - tl.x, br.y - tl.y];
        }

        Timer {
            running: true
            interval: 50
            onTriggered: {
                var cases = [
                    [1.00, 0, 0, wallpaper.width, wallpaper.height, "flat: canvas sits on the wallpaper"],
                    [0.96, 0, 0, wallpaper.width, wallpaper.height, "zoom-in overview style, canvas scale 0.96"],
                    [1.04, -33, -12, wallpaper.width, wallpaper.height, "canvas scaled up and parallaxed apart"],
                    [1.00, 0, 0, 1920, 1080, "screen locked: canvas squares up to the screen"],
                    [0.96, -60, 25, 1920, 1080, "locked, scaled and parallaxed: worst case"]
                ];
                var bad = 0;
                for (var i = 0; i < cases.length; i++) {
                    var c = cases[i];
                    widgetCanvas.scale = c[0];
                    widgetCanvas.x = c[1]; widgetCanvas.y = c[2];
                    widgetCanvas.width = c[3]; widgetCanvas.height = c[4];
                    bad += wallpaperItem.compare(wallpaperItem.rectOf(wallpaper), c[5]);
                }
                console.warn(bad === 0 ? "all cases registered" : bad + " case(s) misregistered");
                Qt.exit(bad === 0 ? 0 : 1);
            }
        }
    }
}
