import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Nagasaki Clock Options")

    ContentSection {
        title: Translation.tr("Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("clock_nagasaki")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Nagasaki Clock disabled")
                description: Translation.tr("Enable the Nagasaki Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_nagasaki")

            ContentSubsectionLabel {
                text: Translation.tr("Style & Appearance")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Monochrome")
                checked: Config.options.background.widgets.clock_nagasaki.monochrome
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nagasaki.monochrome = checked;
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
