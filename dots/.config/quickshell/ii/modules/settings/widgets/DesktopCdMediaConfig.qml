import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("CD media options")

    ContentSection {
        title: Translation.tr("CD media settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("media_cd")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("CD media disabled")
                description: Translation.tr("Enable the CD Media in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("media_cd")

            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size")
                value: Config.options.background.widgets.media_cd.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.media_cd.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Colors")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Dynamic album colors")
                checked: Config.options.background.widgets.media_cd.dynamicAlbumColors ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.media_cd.dynamicAlbumColors = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable shadows")
                checked: Config.options.background.widgets.media_cd.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media_cd.enableShadows = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable inner shadows")
                checked: Config.options.background.widgets.media_cd.enableInnerShadow ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media_cd.enableInnerShadow = checked;
                }
            }
        }
    }
}
