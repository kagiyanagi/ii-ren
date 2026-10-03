import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("PC battery cable options")

    ContentSection {
        title: Translation.tr("PC battery cable settings")
        icon: "power"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("pc_battery_cable")

            PagePlaceholder {
                anchors.fill: parent
                icon: "power"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("PC battery cable disabled")
                description: Translation.tr("Enable the PC Battery Cable in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("pc_battery_cable")
        }
    }
}
