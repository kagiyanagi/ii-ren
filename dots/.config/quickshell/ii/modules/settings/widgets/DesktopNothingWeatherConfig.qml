import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Nothing Weather Circle Options")

    ContentSection {
        title: Translation.tr("Weather Settings")
        icon: "cloud"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("nothing_weather_circle")

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Nothing Weather Circle disabled")
                description: Translation.tr("Enable the Nothing Weather Circle in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("nothing_weather_circle")
        }
    }
}
