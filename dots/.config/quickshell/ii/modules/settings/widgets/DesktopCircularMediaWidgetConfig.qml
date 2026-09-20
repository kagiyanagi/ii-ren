import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Circular Media (Watch) Options")

    ContentSection {
        title: Translation.tr("Circular Media (Watch) Settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("circular_media")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Circular Media (Watch) disabled")
                description: Translation.tr("Enable the Circular Media (Watch) in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("circular_media")

            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: Config.options.background.widgets.circular_media.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.circular_media.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Colors")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Use album colors")
                checked: Config.options.background.widgets.circular_media.useAlbumColors ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.useAlbumColors = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Style")
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable Glass Reflection")
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
