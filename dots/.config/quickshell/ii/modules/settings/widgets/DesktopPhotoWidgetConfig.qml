import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.utils

ContentPage {
    id: root
    forceWidth: false

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

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive(root.widgetIdName)

            ContentSubsectionLabel {
                text: Translation.tr("Photo file")
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "folder_open"
                mainText: Translation.tr("Choose image")
                onClicked: {
                    pickImageProc.pick();
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.imagePath && entry.imagePath !== "";
                }
                text: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    let path = entry ? entry.imagePath : "";
                    return Translation.tr("Current image: %1").arg(path);
                }
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                visible: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.imagePath && entry.imagePath !== "";
                }
                materialIcon: "delete"
                mainText: Translation.tr("Remove image")
                onClicked: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    if (entry) entry.imagePath = "";
                }
            }

            ContentSubsectionLabel {
                visible: root.configEntryName !== "photo"
                text: Translation.tr("Overlay")
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
