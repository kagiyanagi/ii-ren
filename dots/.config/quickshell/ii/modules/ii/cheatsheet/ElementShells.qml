pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The Bohr picture: one ring per shell, the electrons in it spaced around it.
 * It is the one part of a configuration that is faster to read as a picture
 * than as "2, 8, 18, 1".
 *
 * A Canvas would be one repaint per frame for a static drawing, so the rings are
 * Rectangles at `radius: full` and the electrons are positioned with sin/cos --
 * no layer, no shader, nothing in the effect budget (law 8).
 */
Item {
    id: root
    required property var shells
    required property color accent
    property int size: 168
    // 0 -> 1 as the card opens: every shell's electrons start together at the
    // top of their ring and fan out to their places, so the shells read as
    // filling. Driven from outside on a decelerating curve that never passes 1;
    // an electron that overshoots its slot lands on its neighbour's.
    property real progress: 1

    readonly property real nucleusSize: 16
    readonly property real dotSize: 6
    readonly property real ringGap: root.shells.length > 0
        ? (root.size / 2 - root.nucleusSize - root.dotSize) / Math.max(1, root.shells.length)
        : 0

    implicitWidth: root.size
    implicitHeight: root.size

    Rectangle { // nucleus
        anchors.centerIn: parent
        implicitWidth: root.nucleusSize
        implicitHeight: root.nucleusSize
        radius: Appearance.rounding.full
        color: root.accent
    }

    Repeater {
        model: root.shells
        delegate: Item {
            id: shell
            required property int index
            required property int modelData
            readonly property real ringRadius: root.nucleusSize + root.ringGap * (shell.index + 1)
            // Dots are drawn while there is room for them -- a full 32-electron
            // shell is a ring of beads, which says "full" faster than the number.
            // Only where neighbours would touch, with less than a third of a dot
            // between them, does the count take over.
            readonly property bool drawDots: 2 * Math.PI * shell.ringRadius / Math.max(1, shell.modelData) >= root.dotSize * 4 / 3

            anchors.centerIn: parent
            width: shell.ringRadius * 2
            height: shell.ringRadius * 2

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.full
                color: "transparent"
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
            }

            Repeater {
                model: shell.drawDots ? shell.modelData : 0
                delegate: Rectangle {
                    id: dot
                    required property int index
                    readonly property real angle: (dot.index / shell.modelData) * 2 * Math.PI * root.progress - Math.PI / 2
                    implicitWidth: root.dotSize
                    implicitHeight: root.dotSize
                    radius: Appearance.rounding.full
                    color: root.accent
                    x: shell.ringRadius + Math.cos(dot.angle) * shell.ringRadius - dot.width / 2
                    y: shell.ringRadius + Math.sin(dot.angle) * shell.ringRadius - dot.height / 2
                }
            }

            StyledText { // the occupancy, on the ring's right-hand side
                x: shell.ringRadius * 2 - implicitWidth / 2
                y: shell.ringRadius - implicitHeight / 2
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
                color: Appearance.colors.colOnSurfaceVariant
                text: shell.modelData
                visible: !shell.drawDots
            }
        }
    }
}
