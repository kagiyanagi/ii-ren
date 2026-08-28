pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One saved conversation. Renaming and deleting happen in place rather than in a
 * dialog: the row already has the context a dialog would have to restate, and the
 * delete confirmation sits where the click landed instead of in the middle of the
 * screen.
 */
Item {
    id: root

    required property var service
    required property var chat
    property bool current: false

    signal openRequested()

    property bool renaming: false
    property bool confirming: false

    implicitHeight: body.implicitHeight + 12

    // Tracks the pointer over the row *and everything in it*. A MouseArea cannot do
    // this job here: the action buttons sit above it and take hover for themselves, so
    // its containsMouse drops the moment the pointer reaches a button — which hides the
    // button, which hands hover back, which shows it again. That oscillation is the
    // flicker. A HoverHandler sees the pointer wherever it is inside the row.
    HoverHandler {
        id: rowHover
    }

    readonly property string providerIcon: root.service?.providers[root.chat.provider]?.icon ?? "terminal"
    readonly property string providerName: root.service?.providers[root.chat.provider]?.name ?? (root.chat.provider ?? "")

    function beginRename() {
        root.confirming = false;
        root.renaming = true;
        renameField.text = root.chat.title ?? "";
        renameField.selectAll();
        renameField.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        radius: Appearance.rounding.small
        // Transparent at rest so the list is rows of text rather than a stack of slabs;
        // only the row under the pointer, and the one you are in, take a background.
        color: {
            if (root.current) return Appearance.colors.colSecondaryContainer;
            if (rowHover.hovered) return Appearance.colors.colLayer2Hover;
            return "transparent";
        }

        Behavior on color {
            ColorAnimation { duration: 100 }
        }

        MouseArea { // Sits below the content, so the action buttons win their own clicks
            id: cardArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.renaming || root.confirming) return;
                root.openRequested();
            }
        }

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            spacing: 3

            RowLayout { // Title, or the rename field standing in for it
                Layout.fillWidth: true
                // Held at the height of the action buttons, which are taller than the
                // timestamp they replace. Without it the row grew on hover and shunted
                // every row below it down.
                Layout.preferredHeight: 26
                spacing: 6

                MaterialSymbol {
                    visible: !root.renaming
                    text: root.current ? "chat_bubble" : root.providerIcon
                    iconSize: Appearance.font.pixelSize.small
                    color: root.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                }

                StyledText {
                    visible: !root.renaming
                    Layout.fillWidth: true
                    text: root.chat.title ?? "Untitled"
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: root.current ? Font.DemiBold : Font.Normal
                    color: root.current ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface
                }

                MaterialTextField {
                    id: renameField
                    visible: root.renaming
                    Layout.fillWidth: true
                    onAccepted: {
                        root.service?.renameChat(root.chat.id, text);
                        root.renaming = false;
                    }
                    Keys.onEscapePressed: root.renaming = false
                    onActiveFocusChanged: if (!activeFocus) root.renaming = false
                }

                StyledText {
                    visible: !root.renaming && !rowActions.visible
                    text: root.relativeStamp
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                RowLayout { // Revealed on hover so the row stays quiet at rest
                    id: rowActions
                    visible: !root.renaming && !root.confirming && rowHover.hovered
                    spacing: 0

                    RowAction {
                        symbol: "edit"
                        tooltip: "Rename"
                        onClicked: root.beginRename()
                    }

                    RowAction {
                        symbol: "delete"
                        tooltip: "Delete"
                        danger: true
                        onClicked: root.confirming = true
                    }
                }
            }

            StyledText { // Where the conversation got to
                visible: !root.renaming && !root.confirming && (root.chat.preview ?? "").length > 0
                Layout.fillWidth: true
                text: root.chat.preview ?? ""
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RowLayout { // Provenance: which CLI and model answered, and how long it ran
                visible: !root.renaming && !root.confirming
                Layout.fillWidth: true
                spacing: 5

                StyledText {
                    text: root.chat.model ?? ""
                    elide: Text.ElideRight
                    Layout.maximumWidth: 150
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    visible: (root.chat.count ?? 0) > 0
                    text: `· ${root.chat.count} message${root.chat.count === 1 ? "" : "s"}`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout { // Delete confirmation, in the row rather than over the screen
                visible: root.confirming
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    text: "Delete this conversation?"
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSurface
                }

                RippleButton {
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.verysmall
                    colBackground: "transparent"
                    onClicked: root.confirming = false
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        leftPadding: 8
                        rightPadding: 8
                        text: "Cancel"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSurface
                    }
                }

                RippleButton {
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.verysmall
                    colBackground: Appearance.m3colors.m3errorContainer
                    onClicked: {
                        root.confirming = false;
                        root.service?.deleteChat(root.chat.id);
                    }
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        leftPadding: 8
                        rightPadding: 8
                        text: "Delete"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onErrorContainer
                    }
                }
            }
        }
    }

    // Recomputed whenever the list is rebuilt, which is often enough for "2h".
    readonly property string relativeStamp: {
        const stamp = root.chat.updatedAt ?? 0;
        const diff = Date.now() - stamp;
        if (diff < 60000) return "now";
        if (diff < 3600000) return `${Math.floor(diff / 60000)}m`;
        if (diff < 86400000) return `${Math.floor(diff / 3600000)}h`;
        if (diff < 7 * 86400000) return `${Math.floor(diff / 86400000)}d`;
        return new Date(stamp).toLocaleDateString(Qt.locale(), "d MMM");
    }

    component RowAction: RippleButton {
        id: action
        required property string symbol
        property string tooltip: ""
        property bool danger: false

        implicitWidth: 26
        implicitHeight: 26
        buttonRadius: Appearance.rounding.verysmall
        colBackground: "transparent"

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: action.symbol
            iconSize: Appearance.font.pixelSize.normal
            color: action.danger ? Appearance.colors.colError : Appearance.colors.colSubtext
        }

        StyledToolTip {
            text: action.tooltip
            extraVisibleCondition: action.tooltip.length > 0
        }
    }
}
