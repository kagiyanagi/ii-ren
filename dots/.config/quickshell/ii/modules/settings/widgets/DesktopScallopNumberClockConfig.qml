import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Scallop number clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("scallop_number_clock")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Scallop number clock disabled")
                description: Translation.tr("Enable the Scallop Number Clock in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("scallop_number_clock")


            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size (%)")
                value: Config.options.background.widgets.scallop_number_clock.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: Config.options.background.widgets.scallop_number_clock.widgetSize = value
            }

            ContentSubsectionLabel {
                text: Translation.tr("Display elements")
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Hour bubble")
                checked: Config.options.background.widgets.scallop_number_clock.showHourHand ?? true
                onCheckedChanged: Config.options.background.widgets.scallop_number_clock.showHourHand = checked
            }

            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Minute bubble")
                checked: Config.options.background.widgets.scallop_number_clock.showMinuteBubble ?? true
                onCheckedChanged: Config.options.background.widgets.scallop_number_clock.showMinuteBubble = checked
            }

            ConfigSwitch {
                buttonIcon: "tag"
                text: Translation.tr("Background numbers")
                checked: Config.options.background.widgets.scallop_number_clock.showDots ?? true
                onCheckedChanged: Config.options.background.widgets.scallop_number_clock.showDots = checked
            }

            ContentSubsectionLabel {
                text: Translation.tr("Style & appearance")
            }

            ConfigSwitch {
                buttonIcon: "format_bold"
                text: Translation.tr("Bold font")
                checked: Config.options.background.widgets.scallop_number_clock.boldFont ?? true
                onCheckedChanged: Config.options.background.widgets.scallop_number_clock.boldFont = checked
            }

            ConfigSwitch {
                buttonIcon: "contrast"
                text: Translation.tr("Black background")
                checked: Config.options.background.widgets.scallop_number_clock.useBlackBg ?? true
                onCheckedChanged: Config.options.background.widgets.scallop_number_clock.useBlackBg = checked
            }

            ConfigSwitch {
                buttonIcon: "wb_twilight"
                text: Translation.tr("Glass reflection")
                checked: Config.options.background.widgets.scallop_number_clock.enableGlassReflection ?? false
                onCheckedChanged: Config.options.background.widgets.scallop_number_clock.enableGlassReflection = checked
            }
        }
    }
}
