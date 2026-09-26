pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

RowLayout {
    id: root

    required property PwNode node
    property string icon: ""
    property bool monochrome: false
    spacing: 4

    WPanelIconButton {
        id: muteButton
        Layout.leftMargin: 8
        iconName: {
            if (root.icon.length > 0) return root.icon;
            return WIcons.audioAppIcon(root.node);
        }
        monochrome: root.monochrome || (root.icon.length > 0)
        onClicked: {
            if (root.node?.audio) {
                root.node.audio.muted = !root.node.audio.muted;
            }
        }

        WToolTip {
            extraVisibleCondition: muteButton.shouldShowTooltip
            text: (root.node?.audio?.muted ?? false) ? Translation.tr("Unmute") : Translation.tr("Mute")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.rightMargin: 12
        spacing: 0

        WText {
            Layout.fillWidth: true
            font.pixelSize: Looks.font.pixelSize.large
            elide: Text.ElideRight
            text: root.node?.description || Translation.tr("Unknown")
        }

        WSlider {
            Layout.fillWidth: true
            value: root.node?.audio?.volume ?? 0
            scrollable: true
            onMoved: {
                if (root.node?.audio) {
                    root.node.audio.volume = value;
                }
            }
        }
    }
}
