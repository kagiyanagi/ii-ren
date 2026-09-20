import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Resource Fill Cards Options")

    ContentSection {
        title: Translation.tr("Resource Fill Cards Settings")
        icon: "donut_large"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("resource_fill_cards")

            PagePlaceholder {
                anchors.fill: parent
                icon: "donut_large"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Resource Fill Cards disabled")
                description: Translation.tr("Enable the Resource Fill Cards in Desktop Widgets settings to use this page.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Shape")
            visible: Config.isWidgetActive("resource_fill_cards")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.resource_fill_cards.orientation ?? "horizontal"
                onSelected: value => Config.options.background.widgets.resource_fill_cards.orientation = value
                options: [
                    { displayName: Translation.tr("Horizontal"), icon: "view_column", value: "horizontal" },
                    { displayName: Translation.tr("Vertical"), icon: "view_stream", value: "vertical" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Size")
            visible: Config.isWidgetActive("resource_fill_cards")

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget scale")
                value: Config.options.background.widgets.resource_fill_cards.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.resource_fill_cards.widgetSize = value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Resources")
            visible: Config.isWidgetActive("resource_fill_cards")

            ConfigSwitch {
                buttonIcon: "memory"
                text: Translation.tr("CPU usage card")
                checked: Config.options.background.widgets.resource_fill_cards.enableCpu ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.resource_fill_cards.enableCpu = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "memory_alt"
                text: Translation.tr("RAM memory card")
                checked: Config.options.background.widgets.resource_fill_cards.enableRam ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.resource_fill_cards.enableRam = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "hard_drive"
                text: Translation.tr("Disk storage card")
                checked: Config.options.background.widgets.resource_fill_cards.enableDisk ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.resource_fill_cards.enableDisk = checked;
                }
            }
        }

        // Last, because the shadow toggles are global rather than this widget's.
        // Present here and not on the three pill pages for one reason: this
        // widget reads `enableShadows`, and CpuPillWidget/RamPillWidget/
        // DiskPillWidget never do.
        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("resource_fill_cards")
        }
    }
}
