import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The box a tooltip's text sits in. Purely visual: it never fades or resizes
 * itself, because a tooltip fades and never scales (DESIGN.md 9) and the fade
 * belongs to whatever shows it -- the popup transition in StyledToolTip, the
 * contentOpacity binding in PopupToolTip. Doing it here too multiplied both into a
 * curve nobody chose, and the box used to grow out of nothing, which read as a
 * scale and animated a size on an effects spec.
 */
Item {
    id: root
    required property string text
    property real horizontalPadding: 10
    property real verticalPadding: 6
    property alias font: tooltipTextObject.font
    implicitWidth: tooltipTextObject.implicitWidth + 2 * root.horizontalPadding
    implicitHeight: tooltipTextObject.implicitHeight + 2 * root.verticalPadding

    Rectangle {
        anchors.fill: parent
        color: Appearance?.colors.colTooltip ?? "#3C4043"
        radius: Appearance?.rounding.verysmall ?? 7

        StyledText {
            id: tooltipTextObject
            anchors.centerIn: parent
            text: root.text
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 14
            font.hintingPreference: Font.PreferNoHinting // Prevent shaky text
            color: Appearance?.colors.colOnTooltip ?? "#FFFFFF"
            wrapMode: Text.Wrap
        }
    }
}
