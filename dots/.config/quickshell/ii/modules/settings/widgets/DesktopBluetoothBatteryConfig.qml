import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Bluetooth Device Battery Options")

    ContentSection {
        title: Translation.tr("Bluetooth Device Battery Settings")
        icon: "earbuds"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("bluetooth_battery")

            PagePlaceholder {
                anchors.fill: parent
                icon: "earbuds"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Bluetooth Device Battery disabled")
                description: Translation.tr("Enable the Bluetooth Device Battery in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("bluetooth_battery")
        }
    }
}
