import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("RAM resource pill options")

    ContentSection {
        title: Translation.tr("RAM resource pill settings")
        icon: "memory_alt"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("resource_ram_pill")

            PagePlaceholder {
                anchors.fill: parent
                icon: "memory_alt"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("RAM resource pill disabled")
                description: Translation.tr("Enable the RAM Resource Pill in Desktop Widgets settings to use this page.")
            }
        }

        ConfigSelectionRow {
            buttonIcon: "interests"
            text: Translation.tr("Shape")
            visible: Config.isWidgetActive("resource_ram_pill")
            currentValue: Config.options.background.widgets.resource_ram_pill.aspectRatio ?? "2x0.5"
            onSelected: value => Config.options.background.widgets.resource_ram_pill.aspectRatio = value
            options: [
                { displayName: Translation.tr("1x0.5 (compact pill)"), icon: "crop_landscape", value: "1x0.5" },
                { displayName: Translation.tr("2x0.5 (standard pill)"), icon: "crop_16_9", value: "2x0.5" }
            ]
        }

        ConfigSlider {
            visible: Config.isWidgetActive("resource_ram_pill")
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Widget scale (%)")
            value: Config.options.background.widgets.resource_ram_pill.widgetSize ?? 100
            from: 50
            to: 200
            stepSize: 10
            onValueChanged: {
                Config.options.background.widgets.resource_ram_pill.widgetSize = value;
            }
        }

        ConfigSwitch {
            visible: Config.isWidgetActive("resource_ram_pill")
            buttonIcon: "info"
            text: Translation.tr("Show GB used and total")
            checked: Config.options.background.widgets.resource_ram_pill.showDetails ?? true
            onCheckedChanged: {
                Config.options.background.widgets.resource_ram_pill.showDetails = checked;
            }
        }
    }
}
