import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Rectangle {
    id: root
    required property var element
    readonly property int padding: 4
    // The 44 spacer cells hold their column in the grid, so they stay in the
    // layout -- a `visible: false` here collapses the Row and the table with it.
    readonly property bool filled: root.element.type !== "empty"

    // A reference tile, not a control. It was a RippleButton with no onClicked,
    // so all 162 tiles carried a ripple and a hover film for an action that does
    // not exist -- and the spacers were transparent buttons that still
    // hit-tested and rippled under the pointer. Law 6's four states belong to
    // things that can be pressed.
    implicitWidth: 72
    implicitHeight: 72
    color: root.filled ? Appearance.colors.colLayer2 : "transparent"
    radius: Appearance.rounding.small

    Item {
        anchors.fill: parent
        visible: root.filled

        StyledText {
            anchors {
                top: parent.top
                left: parent.left
                margins: root.padding
            }
            color: Appearance.colors.colOnLayer2
            text: root.element.number
            font.pixelSize: Appearance.font.pixelSize.smallest
        }

        StyledText {
            anchors {
                top: parent.top
                right: parent.right
                margins: root.padding
            }
            color: Appearance.colors.colOnLayer2
            text: root.element.weight
            font.pixelSize: Appearance.font.pixelSize.smallest
        }

        StyledText {
            anchors.centerIn: parent
            color: Appearance.colors.colSecondary
            font.pixelSize: Appearance.font.pixelSize.huge
            text: root.element.symbol
        }

        StyledText {
            // Eight names are wider than the tile and used to paint straight
            // through its sides and over the neighbouring tiles. A width is what
            // lets StyledText elide at all (cw-primitives).
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: root.padding
            }
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer2
            text: root.element.name
        }
    }
}
