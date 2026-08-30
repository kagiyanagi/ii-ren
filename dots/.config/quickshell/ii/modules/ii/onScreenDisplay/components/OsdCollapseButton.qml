import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

RippleButton {
    id: button

    property bool isExpanded: false
    property bool hasExpandableIndicator: true
    property real buttonHeight: 56
    property real expandedProgress: 0.0
    property bool showText: true

    visible: hasExpandableIndicator
    Layout.preferredWidth: buttonHeight
    Layout.preferredHeight: buttonHeight
    buttonRadius: expandedProgress > 0.01 ? Appearance.rounding.windowRounding : buttonHeight / 2
    rippleEnabled: true

    // No container: AOSP's settings slot is a bare icon with a ripple.
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    contentItem: RowLayout {
        spacing: 8 * button.expandedProgress
        anchors.fill: parent
        anchors.leftMargin: (button.showText && button.expandedProgress > 0.01) ? 16 : 0
        anchors.rightMargin: (button.showText && button.expandedProgress > 0.01) ? 16 : 0

        // AOSP's volume dialog ends in a settings/tune button, not a chevron.
        MaterialSymbol {
            id: collapseIcon
            text: "tune"
            color: Appearance.colors.colOnSecondaryContainer
            iconSize: 20
            Layout.alignment: Qt.AlignVCenter | ((button.showText && button.expandedProgress > 0.01) ? Qt.AlignLeft : Qt.AlignHCenter)
        }

        StyledText {
            text: button.isExpanded ? Translation.tr("Collapse OSD") : Translation.tr("Expand OSD")
            color: Appearance.colors.colOnSecondaryContainer
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            visible: button.showText && button.expandedProgress > 0.5
            opacity: (button.expandedProgress - 0.5) * 2
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    StyledToolTip {
        text: button.isExpanded ? Translation.tr("Collapse OSD") : Translation.tr("Expand OSD")
        extraVisibleCondition: button.hovered
    }
}
