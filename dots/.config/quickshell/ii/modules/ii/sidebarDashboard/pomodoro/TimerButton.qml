import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// The button pair both tabs share, so switching tabs moves and restyles
// nothing under the pointer. `filled` is start/pause, the rest is neutral.
// Compact (30-32px, DESIGN.md 9): a standard 40px pill outweighed the ring.
RippleButton {
    id: root
    property string iconName
    property bool filled
    readonly property color colContent: filled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2

    implicitHeight: 32
    horizontalPadding: 16
    buttonRadius: Appearance.rounding.full
    colBackground: filled ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
    colBackgroundHover: filled ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
    colRipple: filled ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
    colStateLayer: colContent

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        RowLayout {
            id: row
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width)
            spacing: 8

            MaterialSymbol {
                text: root.iconName
                iconSize: Appearance.font.pixelSize.large
                fill: 1
                color: root.colContent
            }
            StyledText {
                Layout.fillWidth: true
                text: root.buttonText
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.colContent
            }
        }
    }
}
