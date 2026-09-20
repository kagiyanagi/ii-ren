import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Connected Devices Battery List (2x1) Options")

    ContentSection {
        title: Translation.tr("Connected Devices Battery List (2x1) Settings")
        icon: "battery_full"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("devices_battery_list")

            PagePlaceholder {
                anchors.fill: parent
                icon: "battery_full"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Connected Devices Battery List (2x1) disabled")
                description: Translation.tr("Enable the Connected Devices Battery List (2x1) in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("devices_battery_list")
        }
    }
}
