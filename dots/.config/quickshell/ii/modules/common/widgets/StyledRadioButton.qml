import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RadioButton {
    id: root
    padding: 4
    implicitHeight: contentItem.implicitHeight + padding * 2
    property string description
    property color activeColor: Appearance?.colors.colPrimary ?? "#685496"
    property color inactiveColor: Appearance?.m3colors.m3onSurfaceVariant ?? "#45464F"

    opacity: root.enabled ? 1 : 0.4 // 3.1: disabled is the whole control
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    PointingHandInteraction {}

    indicator: Item {}

    contentItem: RowLayout {
        id: contentItem
        Layout.fillWidth: true
        spacing: 12

        Rectangle {
            id: radio
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignVCenter
            // implicit, not width/height: a layout owns those and qmllint calls
            // setting them undefined behaviour.
            implicitWidth: 20
            implicitHeight: 20
            radius: Appearance.rounding.full
            border.color: root.checked ? root.activeColor : root.inactiveColor
            border.width: 2
            color: "transparent"

            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            // Checked indicator
            Rectangle {
                anchors.centerIn: parent
                width: root.checked ? 10 : 4
                height: root.checked ? 10 : 4
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                opacity: root.checked ? 1 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on width {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }
            }

            // RadioButtonTokens.StateLayerSize (40dp), overhanging the 20dp ring
            // the way M3 draws it. This was a hand-mixed 0.1 film on hover only:
            // the wrong token for hover, and nothing at all for focus, which is
            // the state a radio group is navigated by (3.1).
            StateOverlay {
                anchors.centerIn: parent
                width: 40
                height: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                contentColor: root.checked ? root.activeColor : Appearance.m3colors.m3onSurface
                hover: root.hovered
                focused: root.visualFocus
                press: root.down
            }
        }

        StyledText {
            text: root.description
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
            color: Appearance.m3colors.m3onSurface
        }
    }
}
