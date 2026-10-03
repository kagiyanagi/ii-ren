import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Nothing digital clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("clock_nothing")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Nothing digital clock disabled")
                description: Translation.tr("Enable the Nothing Digital Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_nothing")

            ContentSubsectionLabel {
                text: Translation.tr("Display elements")
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Use 24-hour format")
                checked: Config.options.background.widgets.clock_nothing.use24h ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.use24h = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "label"
                text: Translation.tr("Show AM/PM chip (12-hour mode)")
                checked: Config.options.background.widgets.clock_nothing.showAmPmChip ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.showAmPmChip = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "short_text"
                text: Translation.tr("Show 'TIME' top header")
                checked: Config.options.background.widgets.clock_nothing.showTopLabel ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.showTopLabel = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "today"
                text: Translation.tr("Show date at bottom")
                checked: Config.options.background.widgets.clock_nothing.showDate ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.showDate = checked;
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Style & appearance")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Use accent color on hours")
                checked: Config.options.background.widgets.clock_nothing.useAccentColor ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.useAccentColor = checked;
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
