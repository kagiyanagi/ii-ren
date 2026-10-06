import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * A widget in the Material bar style (bar.barGroupStyle 3): one container
 * pill, its key value on an accent inset 4 in from one end -- a pill, or a
 * circle for a lone icon -- and a second value as plain text beside it. The
 * clock, weather and battery draw themselves this way; everything else stays
 * a plain group pill. Children go on the accent and centre themselves on it.
 */
Rectangle {
    id: root

    property bool accentFirst: true
    property bool accentIsCircle: false
    property string text: ""
    property bool hover: false
    property bool press: false
    default property alias accentContent: accent.data
    // Tonal, not filled: a light primary accent put dark content in a bar of
    // light content, and nothing drawn for the dark bar (the weather
    // illustrations, the battery meter) sat right on it. Content on it takes
    // colOnPrimaryContainer.
    readonly property color colAccent: Appearance.colors.colPrimaryContainer

    // 4 between the accent and the pill's edge, as BarGroup insets its pill
    // from the bar; 12 at the text end so the label sits off the curve.
    readonly property real textMargin: label.visible ? 12 : 4

    implicitHeight: Appearance.sizes.baseBarHeight - 8
    implicitWidth: row.implicitWidth + 4 + textMargin
    radius: Appearance.rounding.full
    // The same layer as every other group pill (BarComponent), so the bar
    // reads as one row of pills and only the primary accent stands out.
    color: Appearance.colors.colLayer2

    StateOverlay {
        anchors.fill: parent
        radius: root.radius
        contentColor: Appearance.colors.colOnLayer2
        hover: root.hover
        press: root.press
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.accentFirst ? 4 : root.textMargin
        layoutDirection: root.accentFirst ? Qt.LeftToRight : Qt.RightToLeft
        spacing: 8

        Rectangle {
            id: accent
            height: root.height - 8
            width: root.accentIsCircle ? height : (accent.children[0]?.implicitWidth ?? 0) + 16
            radius: Appearance.rounding.full
            color: root.colAccent
        }

        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text.length > 0
            text: root.text
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
