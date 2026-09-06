pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One stored conversation. Opening is the whole row; deleting is a button that
 * arms itself first -- a sidebar is too narrow for a modal, and a dialog for
 * "are you sure" costs more attention than the action it guards.
 */
RippleButton {
    id: root

    required property var session
    property bool current: false

    signal openRequested()

    // Armed by the first press on the bin, cleared by the next press anywhere
    // else or by the timer -- so a mis-click cannot delete a conversation.
    property bool confirmingDelete: false

    implicitHeight: contentColumn.implicitHeight + 10 * 2
    buttonRadius: Appearance.rounding.small

    colBackground: root.current ? Appearance.colors.colSecondaryContainer : "transparent"
    colBackgroundHover: root.current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover

    releaseAction: () => {
        if (root.confirmingDelete) {
            root.confirmingDelete = false;
            return;
        }
        root.openRequested();
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.confirmingDelete = false
    }

    contentItem: RowLayout {
        spacing: 8

        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.leftMargin: 10
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                text: (root.session?.title ?? "").length > 0 ? root.session.title : Translation.tr("Untitled")
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: text.length > 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: {
                    const count = root.session?.message_count ?? 0;
                    const source = root.session?.source ?? "";
                    const parts = [];
                    if (count > 0)
                        parts.push(Translation.tr("%1 messages").arg(count));
                    if (source.length > 0)
                        parts.push(source);
                    return parts.join("  ·  ");
                }
            }
        }

        RippleButton {
            id: deleteButton
            Layout.rightMargin: 6
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.small
            colBackground: root.confirmingDelete ? Appearance.colors.colErrorContainer : "transparent"
            colBackgroundHover: root.confirmingDelete ? Appearance.colors.colErrorContainerHover : Appearance.colors.colLayer2Hover

            releaseAction: () => {
                if (!root.confirmingDelete) {
                    root.confirmingDelete = true;
                    disarm.restart();
                    return;
                }
                disarm.stop();
                root.confirmingDelete = false;
                HermesService.deleteSession(root.session?.id ?? "");
            }

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: Appearance.font.pixelSize.larger
                color: root.confirmingDelete ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colSubtext
                text: root.confirmingDelete ? "delete_forever" : "delete"
            }

            StyledToolTip {
                text: root.confirmingDelete ? Translation.tr("Press again to delete") : Translation.tr("Delete this chat")
            }
        }
    }
}
