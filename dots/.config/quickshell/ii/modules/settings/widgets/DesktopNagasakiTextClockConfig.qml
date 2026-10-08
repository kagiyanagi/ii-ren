import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Nagasaki text clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("nagasaki_text")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Nagasaki text clock disabled")
                description: Translation.tr("Enable the Nagasaki Text Clock in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("nagasaki_text")


            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Font size")
                value: Config.options.background.widgets.nagasaki_text.size ?? 200
                from: 100
                to: 400
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.nagasaki_text.size = Math.round(value);
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
