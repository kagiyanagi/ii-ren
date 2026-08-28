import QtQuick

// Runnable check for both wallpaper shaders. Renders every filter, every
// adjustment and every glass pattern/profile branch over a synthetic
// high-frequency pattern, saving one PNG each into ./shader-check/.
// check.sh then asserts each one differs from the unfiltered baseline, which
// catches a stale bake, a renamed uniform, or a branch that silently became a
// no-op. Needs a real GPU: the offscreen QPA plugin cannot run ShaderEffect.
Window {
    id: win
    width: 480
    height: 270
    visible: true

    // name, filterMode, then the uniforms that case exercises.
    readonly property var cases: [
        { name: "00-baseline",  f: 0 },
        { name: "01-grayscale", f: 1 },
        { name: "02-sepia",     f: 2 },
        { name: "03-negative",  f: 3 },
        { name: "04-posterize", f: 4, posterizeLevels: 3 },
        { name: "05-pixelate",  f: 5, pixelSize: 12 },
        { name: "06-sharpen",   f: 6, sharpen: 2.0 },
        { name: "07-chromatic", f: 7, chromatic: 8 },
        { name: "08-radial",    f: 8, radialBlur: 0.4 },
        { name: "09-saturation", f: 0, saturation: 0.2 },
        { name: "10-dim",       f: 0, dim: 0.6 },
        { name: "11-vignette",  f: 0, vignette: 0.9 },
        { name: "12-grain",     f: 0, grain: 1.0 },
        { name: "13-glass-lens",    glass: true, pattern: 0, profile: 0 },
        { name: "14-glass-prism",   glass: true, pattern: 0, profile: 1 },
        { name: "15-glass-contour", glass: true, pattern: 0, profile: 2 },
        { name: "16-glass-cascade", glass: true, pattern: 0, profile: 3 },
        { name: "17-glass-flat",    glass: true, pattern: 0, profile: 4, smear: 0.6 },
        { name: "18-glass-rain",    glass: true, pattern: 1, profile: 0 },
        { name: "19-glass-chevron", glass: true, pattern: 2, profile: 0 },
        { name: "20-glass-bubble",  glass: true, pattern: 3, profile: 0 }
    ]

    property int index: 0
    readonly property var current: win.cases[win.index]
    property int failures: 0

    // Deterministic, high frequency and colourful, so every branch has
    // something it can measurably change.
    // Visible on purpose: grabToImage renders only the visible subtree, so an
    // invisible source is sampled as pure black. The opaque shaders above
    // cover it anyway.
    Item {
        id: pattern
        anchors.fill: parent
        // layer.enabled makes this a texture provider, so the shaders bind its
        // texture directly. Without it grabToImage sees an unrendered source
        // and every branch comes out black.
        layer.enabled: true

        Grid {
            anchors.fill: parent
            columns: 16
            rows: 9
            Repeater {
                model: 144
                Rectangle {
                    required property int index
                    width: pattern.width / 16
                    height: pattern.height / 9
                    color: Qt.hsva(((index * 37) % 360) / 360, 0.85,
                                   0.25 + ((index * 53) % 60) / 100, 1)
                }
            }
        }
        Repeater {
            model: Math.ceil(pattern.width / 7)
            Rectangle {
                required property int index
                x: index * 7
                width: 1
                height: pattern.height
                color: "white"
            }
        }
    }

    ShaderEffect {
        id: glass
        anchors.fill: parent
        layer.enabled: true
        property variant src: pattern
        property vector2d resolution: Qt.vector2d(win.width, win.height)
        property real cellSize: 26
        property real angle: 0
        property real distortion: 0.6
        property real dispersion: 0.3
        property real blurAmount: win.current.smear ?? 0
        property real highlights: 0.5
        property real shadows: 0.35
        property real edges: 0.3
        property real grain: 0
        property real irregularity: 0
        property real waviness: 0.6
        property int pattern: win.current.pattern ?? 0
        property int profile: win.current.profile ?? 0
        fragmentShader: Qt.resolvedUrl("flutedGlass.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) {
            console.error("flutedGlass FAILED TO COMPILE:", log);
            win.failures++;
        }
    }

    ShaderEffect {
        anchors.fill: parent
        property variant src: (win.current.glass ?? false) ? glass : pattern
        property vector2d resolution: Qt.vector2d(win.width, win.height)
        property real saturation: win.current.saturation ?? 1.0
        property real dim: win.current.dim ?? 0.0
        property real vignette: win.current.vignette ?? 0.0
        property real grain: win.current.grain ?? 0.0
        property real pixelSize: win.current.pixelSize ?? 8
        property real posterizeLevels: win.current.posterizeLevels ?? 8
        property real sharpen: win.current.sharpen ?? 1.0
        property real chromatic: win.current.chromatic ?? 5
        property real radialBlur: win.current.radialBlur ?? 0.05
        property int filterMode: win.current.f ?? 0
        fragmentShader: Qt.resolvedUrl("wallpaperFilter.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) {
            console.error("wallpaperFilter FAILED TO COMPILE:", log);
            win.failures++;
        }
    }

    // One grab per case, then advance. 250ms is slack for the bake + upload.
    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            const name = win.current.name;
            win.contentItem.grabToImage(result => {
                if (!result.saveToFile("shader-check/" + name + ".png")) {
                    console.error("could not save", name);
                    win.failures++;
                }
                if (win.index + 1 >= win.cases.length) {
                    console.log(win.failures === 0
                        ? "rendered " + win.cases.length + " cases"
                        : win.failures + " FAILURES");
                    Qt.exit(win.failures === 0 ? 0 : 1);
                } else {
                    win.index++;
                }
            });
        }
    }

    Timer {
        interval: 30000
        running: true
        onTriggered: {
            console.error("timed out at case", win.index);
            Qt.exit(1);
        }
    }
}
