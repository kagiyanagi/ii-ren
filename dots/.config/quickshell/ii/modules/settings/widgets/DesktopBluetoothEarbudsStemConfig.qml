import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Bluetooth earbuds stem options")

    ContentSection {
        title: Translation.tr("Bluetooth earbuds stem settings")
        icon: "earbuds"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("bluetooth_earbuds_stem")

            PagePlaceholder {
                anchors.fill: parent
                icon: "earbuds"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Bluetooth earbuds stem disabled")
                description: Translation.tr("Enable the Bluetooth Earbuds Stem in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("bluetooth_earbuds_stem")
        }
    }
}
