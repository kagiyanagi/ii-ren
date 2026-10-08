import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Volume mute pill options")

    ContentSection {
        title: Translation.tr("Volume mute pill settings")
        // Not `music_note` like the six media pages: this is a system mute
        // toggle, not a player, and the placeholder has to name what is off.
        icon: "volume_off"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("volume_mute_pill")

            PagePlaceholder {
                anchors.fill: parent
                icon: "volume_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Volume mute pill disabled")
                description: Translation.tr("Enable the Volume Mute Pill in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("volume_mute_pill")

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
