import qs.modules.common
import QtQuick

// A keycap. Static: it labels a shortcut, nothing clicks it, so it carries no
// interaction states.
Rectangle {
    id: root
    property string key

    property real horizontalPadding: 6
    property real verticalPadding: 1
    property real borderWidth: 1
    property real extraBottomBorderWidth: 2
    property color borderColor: Appearance.colors.colOnLayer0
    // 4.1: a literal radius ignores the sharp-mode scale, and this one left
    // every keycap rounded on a shell that had squared everything else.
    property real borderRadius: Appearance.rounding.unsharpenmore
    property real pixelSize: Appearance.font.pixelSize.smaller
    property color keyColor: Appearance.m3colors.m3surfaceContainerLow
    implicitWidth: keyFace.implicitWidth + root.borderWidth * 2
    implicitHeight: keyFace.implicitHeight + root.borderWidth * 2 + root.extraBottomBorderWidth
    radius: root.borderRadius
    color: root.borderColor

    Rectangle {
        id: keyFace
        anchors {
            fill: parent
            topMargin: root.borderWidth
            leftMargin: root.borderWidth
            rightMargin: root.borderWidth
            bottomMargin: root.extraBottomBorderWidth + root.borderWidth
        }
        implicitWidth: keyText.implicitWidth + root.horizontalPadding * 2
        implicitHeight: keyText.implicitHeight + root.verticalPadding * 2
        color: root.keyColor
        // 4.2: inside the cap, so smaller -- and never negative once sharp mode
        // takes the outer radius to 0.
        radius: Math.max(0, root.borderRadius - root.borderWidth)

        StyledText {
            id: keyText
            anchors.centerIn: parent
            font.family: Appearance.font.family.monospace
            font.pixelSize: root.pixelSize
            text: root.key
        }
    }
}
