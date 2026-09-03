import QtQuick
import qs.modules.common
import qs.modules.common.widgets

MouseArea {
    id: root

    readonly property bool isWidgetCanvas: true
    property real snapLineX: -1
    property real snapLineY: -1
    property bool draggingActive: false
    property bool gridOverlayEnabled: false
    property int alignmentGridStep: 10
    onAlignmentGridStepChanged: dotGrid.item?.requestPaint()

    // Loaded only while it is actually on screen. It is a full-screen Canvas,
    // and this item animates its own width and height every time the screen
    // locks or unlocks - a Canvas reallocates and repaints its whole backing
    // image on every size change, so an invisible grid was repainting ~20k
    // dots on the GUI thread on every frame of the lock animation. That was
    // 100-200ms of blocked main thread and about twenty dropped frames per
    // lock, whether or not anything was being dragged.
    FadeLoader {
        id: dotGrid
        anchors.fill: parent
        z: -1
        shown: root.draggingActive && root.gridOverlayEnabled
        // The grid's own weight, not a full-strength fade; FadeLoader supplies
        // the elementMoveFast curve this had before.
        opacity: shown ? 0.55 : 0

        sourceComponent: Canvas {
            readonly property real dotSize: 1.5
            readonly property color dotColor: Appearance.colors.colPrimary

            // Uniform on purpose. A radial falloff around the dragged widget was
            // tried and reverted: it repainted this full-screen canvas on every
            // pointer frame with a per-dot alpha, which is ~20k Qt.rgba allocations
            // and fillStyle switches per frame — the grid could not keep up and
            // read as simply missing. Painted once per size/step change, it costs
            // nothing while you drag.
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = dotColor;

                const offset = dotSize / 2;
                const step = Math.max(1, root.alignmentGridStep);
                for (let y = 0; y <= height; y += step) {
                    for (let x = 0; x <= width; x += step) {
                        ctx.fillRect(x - offset, y - offset, dotSize, dotSize);
                    }
                }
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onDotColorChanged: requestPaint()
            Component.onCompleted: requestPaint()
        }
    }

    // Snap guides. They used to be toggled by `visible`, which made them blink
    // in and out at full strength; they now fade, and carry a soft bloom so the
    // line reads as a guide rather than as a 1.5px scratch on the wallpaper.
    Item {
        id: snapLineV
        visible: opacity > 0.001
        opacity: root.snapLineX >= 0 ? 1 : 0
        x: root.snapLineX
        width: 1.5
        height: root.height
        z: 999
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(snapLineV)
        }
        Rectangle {
            anchors.centerIn: parent
            width: 9
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.28) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colPrimary
        }
    }
    Item {
        id: snapLineH
        visible: opacity > 0.001
        opacity: root.snapLineY >= 0 ? 1 : 0
        y: root.snapLineY
        width: root.width
        height: 1.5
        z: 999
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(snapLineH)
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 9
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.28) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colPrimary
        }
    }
}
