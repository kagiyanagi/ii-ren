import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Circular media (watch) options")

    ContentSection {
        title: Translation.tr("Circular media (watch) settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("circular_media")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Circular media (watch) disabled")
                description: Translation.tr("Enable the Circular Media (Watch) in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("circular_media")


            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size (%)")
                value: Config.options.background.widgets.circular_media.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.circular_media.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }


            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Use album colors")
                checked: Config.options.background.widgets.circular_media.useAlbumColors ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.useAlbumColors = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }


            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable glass reflection")
                checked: Config.options.background.widgets.circular_media.enableGlassReflection ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.enableGlassReflection = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
