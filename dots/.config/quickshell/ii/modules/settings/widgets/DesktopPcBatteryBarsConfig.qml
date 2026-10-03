import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("PC battery bars options")

    ContentSection {
        title: Translation.tr("PC battery bars settings")
        icon: "battery_charging_full"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("pc_battery_bars")

            PagePlaceholder {
                anchors.fill: parent
                icon: "battery_charging_full"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("PC battery bars disabled")
                description: Translation.tr("Enable the PC Battery Bars in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("pc_battery_bars")
        }
    }
}
