pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Rectangle {
    id: root
    required property var directory
    property bool showBreadcrumb: true
    onShowBreadcrumbChanged: {
        addressInput.text = root.directory;
    }

    signal navigateToDirectory(string path)

    property real padding: 6
    implicitWidth: mainLayout.implicitWidth + padding * 2
    implicitHeight: mainLayout.implicitHeight + padding * 2
    color: Appearance.colors.colLayer2

    function focusBreadcrumb() {
        root.showBreadcrumb = false;
        addressInput.forceActiveFocus();
    }

    RowLayout {
        id: mainLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 8

        RippleButton {
            id: parentDirButton
            downAction: () => root.navigateToDirectory(FileUtils.parentDirectory(root.directory))
            contentItem: MaterialSymbol {
                text: "drive_folder_upload"
                iconSize: Appearance.font.pixelSize.larger
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                id: directoryEntry
                visible: !root.showBreadcrumb
                anchors.fill: parent
                // 3.7: the field is opened by a button that then calls
                // forceActiveFocus on it, and nothing said so. colLayer1Active is
                // the 0.10 focus mix for this layer (3.1, mechanism 1).
                color: addressInput.activeFocus ? Appearance.colors.colLayer1Active : Appearance.colors.colLayer1
                radius: Appearance.rounding.full

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                implicitWidth: addressInput.implicitWidth
                implicitHeight: addressInput.implicitHeight

                Keys.onPressed: event => {
                    if (directoryEntry.visible && event.key === Qt.Key_Escape) {
                        root.showBreadcrumb = true;
                        event.accepted = true;
                        return;
                    }
                    event.accepted = false;
                }

                StyledTextInput {
                    id: addressInput
                    anchors.fill: parent
                    padding: 10
                    text: root.directory

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.navigateToDirectory(text);
                            root.showBreadcrumb = true;
                            event.accepted = true;
                        }
                    }
                }
            }

            Loader {
                id: breadcrumbLoader
                active: root.showBreadcrumb
                visible: root.showBreadcrumb
                anchors.fill: parent
                sourceComponent: AddressBreadcrumb {
                    directory: root.directory
                    onNavigateToDirectory: dir => {
                        root.navigateToDirectory(dir);
                    }
                }
            }
        }

        RippleButton {
            id: dirEditButton
            toggled: !root.showBreadcrumb
            downAction: () => root.showBreadcrumb = !root.showBreadcrumb
            contentItem: MaterialSymbol {
                text: "edit"
                iconSize: Appearance.font.pixelSize.larger
                color: dirEditButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }

            StyledToolTip {
                text: Translation.tr("Edit directory")
            }
        }
    }
}
