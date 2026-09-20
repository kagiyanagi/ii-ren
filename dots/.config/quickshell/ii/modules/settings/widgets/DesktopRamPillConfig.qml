import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("RAM Resource Pill Options")

    ContentSection {
        title: Translation.tr("RAM Resource Pill Settings")
        icon: "memory_alt"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("resource_ram_pill")

            PagePlaceholder {
                anchors.fill: parent
                icon: "memory_alt"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("RAM Resource Pill disabled")
                description: Translation.tr("Enable the RAM Resource Pill in Desktop Widgets settings to use this page.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Shape")
            visible: Config.isWidgetActive("resource_ram_pill")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.resource_ram_pill.aspectRatio ?? "2x0.5"
                onSelected: value => Config.options.background.widgets.resource_ram_pill.aspectRatio = value
                options: [
                    { displayName: Translation.tr("1x0.5 (Compact Pill)"), icon: "crop_landscape", value: "1x0.5" },
                    { displayName: Translation.tr("2x0.5 (Standard Pill)"), icon: "crop_16_9", value: "2x0.5" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Size")
            visible: Config.isWidgetActive("resource_ram_pill")

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget scale")
                value: Config.options.background.widgets.resource_ram_pill.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.resource_ram_pill.widgetSize = value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Details")
            visible: Config.isWidgetActive("resource_ram_pill")

            ConfigSwitch {
                buttonIcon: "info"
                text: Translation.tr("Show GB used and total")
                checked: Config.options.background.widgets.resource_ram_pill.showDetails ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.resource_ram_pill.showDetails = checked;
                }
            }
        }
    }
}
