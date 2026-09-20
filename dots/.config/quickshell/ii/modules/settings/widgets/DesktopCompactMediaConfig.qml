import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Compact Media Options")

    ContentSection {
        title: Translation.tr("Compact Media Settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("compact_media")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Compact Media disabled")
                description: Translation.tr("Enable the Compact Media in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("compact_media")

            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: Config.options.background.widgets.compact_media.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.compact_media.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Colors")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Dynamic album colors")
                checked: Config.options.background.widgets.compact_media.dynamicAlbumColors ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.compact_media.dynamicAlbumColors = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.compact_media.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.compact_media.enableShadows = checked;
                }
            }
        }
    }
}
