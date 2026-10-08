import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Connected devices battery list (1x1) options")

    ContentSection {
        title: Translation.tr("Connected devices battery list (1x1) settings")
        icon: "battery_full"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("devices_battery_list_1x1")

            PagePlaceholder {
                anchors.fill: parent
                icon: "battery_full"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Connected devices battery list (1x1) disabled")
                description: Translation.tr("Enable the Connected Devices Battery List (1x1) in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("devices_battery_list_1x1")
        }
    }
}
