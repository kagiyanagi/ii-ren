import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Bluetooth Fill Cards Options")

    ContentSection {
        title: Translation.tr("Bluetooth Fill Cards Settings")
        icon: "bluetooth"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("bluetooth_fill_cards")

            PagePlaceholder {
                anchors.fill: parent
                icon: "bluetooth"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Bluetooth Fill Cards disabled")
                description: Translation.tr("Enable the Bluetooth Fill Cards in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("bluetooth_fill_cards")
        }
    }
}
