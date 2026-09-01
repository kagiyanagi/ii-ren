import QtQuick
import QtQuick.Window
import "../"

// Runnable check for the subject-depth matte shader. Builds a synthetic packed
// frame - solid red on top, a left-to-right alpha ramp underneath with hard
// clear and opaque bands at the ends - and renders it through SubjectMatte.
// check.sh then asserts the ends came out fully clear and fully opaque and that
// the ramp survived, which catches a stale bake, a renamed uniform, halves read
// the wrong way round, or the seam bleeding one half into the other.
// Needs a real GPU: the offscreen QPA plugin cannot run ShaderEffect.
Window {
    id: win
    visible: true
    width: 256
    height: 128

    // Stands in for the VideoOutput playing a packed wallpaper: frame on top,
    // matte underneath, double height. Left in the scene rather than hidden,
    // because an item nothing renders produces no texture to sample.
    Item {
        id: packed
        width: 256
        height: 256

        Rectangle {
            width: 256
            height: 128
            color: "red"
        }

        Item {
            y: 128
            width: 256
            height: 128

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "black" }
                    GradientStop { position: 1.0; color: "white" }
                }
            }
            // The ends are flat on purpose: a shader that merely dims instead of
            // cutting still produces a ramp, but it cannot produce a fully clear
            // band next to a fully opaque one.
            Rectangle { width: 16; height: 128; color: "black" }
            Rectangle { x: 240; width: 16; height: 128; color: "white" }
        }
    }

    // Fixed size, and grabbed directly: a tiling compositor resizes the window
    // out from under this, and a grab of the window would then measure whatever
    // size it decided on.
    SubjectMatte {
        id: matte
        width: 256
        height: 128
        source: packed
    }

    Timer {
        running: true
        interval: 400
        onTriggered: {
            matte.grabToImage(function (result) {
                const ok = result.saveToFile("shader-check/subject-matte.png");
                console.warn(ok ? "saved subject-matte.png" : "FAIL: could not save");
                Qt.exit(ok ? 0 : 1);
            }, Qt.size(256, 128));
        }
    }
}
