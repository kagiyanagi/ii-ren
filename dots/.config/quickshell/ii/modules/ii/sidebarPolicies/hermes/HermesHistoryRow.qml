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
    property bool showSource: true

    signal openRequested()

    // Armed by the first press on the bin, cleared by the next press anywhere
    // else or by the timer -- so a mis-click cannot delete a conversation.
    property bool confirmingDelete: false

    /*
     * When it was started. The list's own headers only group by day, so inside
     * "Earlier this month" or "Older" every row read the same.
     *
     * A time for the last week, where the header already gives the day; a date
     * beyond that, where it does not.
     */
    readonly property string startedText: {
        const stamp = (root.session?.started_at ?? 0) * 1000;
        if (stamp <= 0)
            return "";
        const now = new Date();
        const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const recent = stamp >= midnight - 6 * 86400000;
        return Qt.formatDateTime(new Date(stamp), recent ? "HH:mm" : "MMM d");
    }

    implicitHeight: contentColumn.implicitHeight + 10 * 2
    buttonRadius: Appearance.rounding.small

    // A drawer row: bare on the layer 1 sheet, so its films are layer 1's, and
    // tonal only for the conversation that is open.
    colBackground: root.current ? Appearance.colors.colSecondaryContainer : "transparent"
    colBackgroundHover: root.current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: root.current ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer1Active

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
                    if (root.startedText.length > 0)
                        parts.push(root.startedText);
                    if (count > 0)
                        parts.push(Translation.tr("%1 messages").arg(count));
                    if (root.showSource && source.length > 0)
                        parts.push(source);
                    return parts.join("  ·  ");
                }
            }
        }

        HermesIconButton {
            id: deleteButton
            Layout.rightMargin: 6
            // A bin on every row was the loudest thing on the sheet, ten times
            // over. It shows for the row under the pointer or the keyboard, and
            // keeps its slot meanwhile so the title never re-elides under it.
            readonly property bool shown: root.hovered || deleteButton.hovered || root.activeFocus || deleteButton.activeFocus || root.confirmingDelete
            property AnimSpec opacitySpec: Appearance.animation.elementMoveFast
            opacity: {
                deleteButton.opacitySpec = deleteButton.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                return shown ? 1 : 0;
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: deleteButton.opacitySpec.duration
                    easing.type: deleteButton.opacitySpec.type
                    easing.bezierCurve: deleteButton.opacitySpec.bezierCurve
                }
            }
            symbol: root.confirmingDelete ? "delete_forever" : "delete"
            tooltip: root.confirmingDelete ? Translation.tr("Press again to delete") : Translation.tr("Delete this chat")
            iconColor: root.confirmingDelete ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colSubtext
            colBackground: root.confirmingDelete ? Appearance.colors.colErrorContainer : "transparent"
            // Unarmed, its hover is a film: the row under it is already at
            // colLayer1Hover, so a replacement colour would match it exactly.
            colBackgroundHover: root.confirmingDelete ? Appearance.colors.colErrorContainerHover : "transparent"
            colRipple: root.confirmingDelete ? Appearance.colors.colErrorContainerActive : Appearance.colors.colLayer1Active

            StateOverlay {
                anchors.fill: parent
                radius: deleteButton.buttonRadius
                hover: deleteButton.hovered && !root.confirmingDelete
                contentColor: Appearance.colors.colOnLayer1
            }

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
        }
    }
}
