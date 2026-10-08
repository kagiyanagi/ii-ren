import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Triple ring clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("triple_ring_clock")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Triple ring clock disabled")
                description: Translation.tr("Enable the Triple Ring Clock in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("triple_ring_clock")


            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size (%)")
                value: Config.options.background.widgets.triple_ring_clock.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: Config.options.background.widgets.triple_ring_clock.widgetSize = value
            }

            ContentSubsectionLabel {
                text: Translation.tr("Style & appearance")
            }

            ConfigSwitch {
                buttonIcon: "format_bold"
                text: Translation.tr("Bold font")
                checked: Config.options.background.widgets.triple_ring_clock.boldFont ?? true
                onCheckedChanged: Config.options.background.widgets.triple_ring_clock.boldFont = checked
            }

            ConfigSwitch {
                buttonIcon: "contrast"
                text: Translation.tr("Black background")
                checked: Config.options.background.widgets.triple_ring_clock.useBlackBg ?? true
                onCheckedChanged: Config.options.background.widgets.triple_ring_clock.useBlackBg = checked
            }

            ConfigSwitch {
                buttonIcon: "wb_twilight"
                text: Translation.tr("Glass reflection")
                checked: Config.options.background.widgets.triple_ring_clock.enableGlassReflection ?? false
                onCheckedChanged: Config.options.background.widgets.triple_ring_clock.enableGlassReflection = checked
            }
        }
    }
}
