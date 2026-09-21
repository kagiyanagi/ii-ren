pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The Bohr picture: one ring per shell, the electrons in it spaced around it,
 * and the occupancy written on the ring. It is the one part of a configuration
 * that is faster to read as a picture than as "2, 8, 18, 1".
 *
 * A Canvas would be one repaint per frame for a static drawing, so the rings are
 * Rectangles at `radius: full` and the electrons are positioned with sin/cos --
 * no layer, no shader, nothing in the effect budget (law 8).
 */
Item {
    id: root
    required property var shells
    required property color accent

    readonly property int size: 168
    readonly property real nucleusSize: 16
    readonly property real ringGap: root.shells.length > 0
        ? (root.size / 2 - root.nucleusSize - 6) / Math.max(1, root.shells.length)
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
            // Past this many, dots stop being countable and become a texture, so
            // the number on the ring is what carries the value.
            readonly property bool drawDots: modelData <= 18

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
                    readonly property real angle: (dot.index / shell.modelData) * 2 * Math.PI - Math.PI / 2
                    implicitWidth: 6
                    implicitHeight: 6
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
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colSubtext
                text: shell.modelData
                visible: !shell.drawDots
            }
        }
    }
}
