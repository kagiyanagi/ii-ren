import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Disk resource pill options")

    ContentSection {
        title: Translation.tr("Disk resource pill settings")
        icon: "hard_drive"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("resource_disk_pill")

            PagePlaceholder {
                anchors.fill: parent
                icon: "hard_drive"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Disk resource pill disabled")
                description: Translation.tr("Enable the Disk Resource Pill in Desktop Widgets settings to use this page.")
            }
        }

        ConfigSelectionRow {
            buttonIcon: "interests"
            text: Translation.tr("Shape")
            visible: Config.isWidgetActive("resource_disk_pill")
            currentValue: Config.options.background.widgets.resource_disk_pill.aspectRatio ?? "2x0.5"
            onSelected: value => Config.options.background.widgets.resource_disk_pill.aspectRatio = value
            options: [
                { displayName: Translation.tr("1x0.5 (compact pill)"), icon: "crop_landscape", value: "1x0.5" },
                { displayName: Translation.tr("2x0.5 (standard pill)"), icon: "crop_16_9", value: "2x0.5" }
            ]
        }

        ConfigSlider {
            visible: Config.isWidgetActive("resource_disk_pill")
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Widget scale (%)")
            value: Config.options.background.widgets.resource_disk_pill.widgetSize ?? 100
            from: 50
            to: 200
            stepSize: 10
            onValueChanged: {
                Config.options.background.widgets.resource_disk_pill.widgetSize = value;
            }
        }

        ConfigSwitch {
            visible: Config.isWidgetActive("resource_disk_pill")
            buttonIcon: "info"
            text: Translation.tr("Show GB used and total")
            checked: Config.options.background.widgets.resource_disk_pill.showDetails ?? true
            onCheckedChanged: {
                Config.options.background.widgets.resource_disk_pill.showDetails = checked;
            }
        }
    }
}
