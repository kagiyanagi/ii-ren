import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Weather circle cookie options")

    ContentSection {
        title: Translation.tr("Weather settings")
        icon: "cloud"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("weather_circle")

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Weather circle cookie disabled")
                description: Translation.tr("Enable the Weather Circle Cookie in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("weather_circle")
        }
    }
}
