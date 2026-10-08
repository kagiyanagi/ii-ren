import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.utils

ContentPage {
    id: root
    forceWidth: true

    property string configEntryName: "photo"
    property string widgetIdName: "photo"
    title: Translation.tr("Photo widget options")

    FilePickerProcess {
        id: pickImageProc
        label: "Images"
        patterns: ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.bmp", "*.svg", "*.PNG", "*.JPG", "*.JPEG", "*.GIF", "*.WEBP", "*.BMP", "*.SVG"]
        onPicked: path => {
            let entry = Config.options.background.widgets[root.configEntryName];
            if (entry) {
                entry.imagePath = path;
            } else {
                Config.options.background.widgets.photo.imagePath = path;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Photo widget settings")
        icon: "image"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive(root.widgetIdName)

            PagePlaceholder {
                anchors.fill: parent
                icon: "image"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Photo widget disabled")
                description: Translation.tr("Enable the Photo Widget in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive(root.widgetIdName)

            // One card: the file in use as the summary, its two actions under it.
            ConfigLabeledRow {
                buttonIcon: "image"
                text: Translation.tr("Photo")
                summary: (Config.options.background.widgets[root.configEntryName]?.imagePath ?? "") || Translation.tr("No photo chosen")

                RowLayout {
                    spacing: 4
                    RippleButtonWithIcon {
                        materialIcon: "folder_open"
                        mainText: Translation.tr("Choose image")
                        onClicked: pickImageProc.pick()
                    }
                    RippleButtonWithIcon {
                        visible: (Config.options.background.widgets[root.configEntryName]?.imagePath ?? "").length > 0
                        materialIcon: "delete"
                        mainText: Translation.tr("Remove image")
                        onClicked: { const entry = Config.options.background.widgets[root.configEntryName]; if (entry) entry.imagePath = ""; }
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "subtitles"
                text: Translation.tr("Show info overlay/badge")
                visible: root.configEntryName !== "photo"
                checked: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.showOverlay !== undefined ? entry.showOverlay : true;
                }
                onCheckedChanged: {
                    if (root.configEntryName === "photo") return;
                    let entry = Config.options.background.widgets[root.configEntryName];
                    if (entry && entry.showOverlay !== undefined) {
                        entry.showOverlay = checked;
                    }
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
