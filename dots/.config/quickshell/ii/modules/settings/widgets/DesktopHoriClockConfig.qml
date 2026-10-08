import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Hori clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("clock_hori")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Hori clock disabled")
                description: Translation.tr("Enable the Hori Clock in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("clock_hori")


            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size (%)")
                value: Config.options.background.widgets.clock_hori.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.clock_hori.widgetSize = value;
                }
            }


            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Use card background colors")
                checked: Config.options.background.widgets.clock_hori.useAltColors ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.clock_hori.useAltColors = checked;
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
