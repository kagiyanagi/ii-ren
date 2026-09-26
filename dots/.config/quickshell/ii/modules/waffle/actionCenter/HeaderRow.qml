pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

RowLayout {
    id: root

    required property string title
    spacing: 4

    WPanelIconButton {
        id: backButton
        iconName: "arrow-left"
        onClicked: ActionCenterContext.back()

        WToolTip {
            extraVisibleCondition: backButton.shouldShowTooltip
            text: Translation.tr("Back")
        }
    }

    WText {
        id: titleText
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.title
        font.pixelSize: Looks.font.pixelSize.large
    }
}
