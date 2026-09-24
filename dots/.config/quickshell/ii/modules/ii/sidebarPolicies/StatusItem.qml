import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One reading in the pill above a transcript -- an icon, an optional value and
 * a tooltip saying what it is, in the strip above the Hermes transcript.
 */
MouseArea {
    id: root
    property string icon
    property string statusText
    property string description

    hoverEnabled: true
    implicitHeight: rowLayout.implicitHeight
    implicitWidth: rowLayout.implicitWidth

    RowLayout {
        id: rowLayout
        spacing: 0

        MaterialSymbol {
            text: root.icon
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colSubtext
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            text: root.statusText
            color: Appearance.colors.colSubtext
            animateChange: true
        }
    }

    StyledToolTip {
        text: root.description
        extraVisibleCondition: false
        alternativeVisibleCondition: root.containsMouse
    }
}
