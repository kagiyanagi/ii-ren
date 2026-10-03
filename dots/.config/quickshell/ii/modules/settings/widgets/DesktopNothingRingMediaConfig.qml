import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Nothing ring media options")

    ContentSection {
        title: Translation.tr("Nothing ring media settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("nothing_ring_media")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Nothing ring media disabled")
                description: Translation.tr("Enable the Nothing Ring Media in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("nothing_ring_media")

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
