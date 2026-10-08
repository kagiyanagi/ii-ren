import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Compact media options")

    ContentSection {
        title: Translation.tr("Compact media settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("compact_media")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Compact media disabled")
                description: Translation.tr("Enable the Compact Media in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("compact_media")


            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size (%)")
                value: Config.options.background.widgets.compact_media.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.compact_media.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }


            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Dynamic album colors")
                checked: Config.options.background.widgets.compact_media.dynamicAlbumColors ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.compact_media.dynamicAlbumColors = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }


            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable shadows")
                checked: Config.options.background.widgets.compact_media.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.compact_media.enableShadows = checked;
                }
            }
        }
    }
}
