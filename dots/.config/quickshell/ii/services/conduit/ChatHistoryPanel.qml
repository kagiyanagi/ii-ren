pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Saved conversations: search, open, rename, delete.
 *
 * Rows come from the service's index rather than from the conversation files, so
 * opening the list never touches disk. Renaming and deleting happen in the row
 * itself: a sidebar is too narrow for a modal, and a dialog for "are you sure"
 * costs more attention than the action it guards.
 */
Rectangle {
    id: root

    required property var service
    signal requestClose()

    // Opaque. Note colLayer1 is NOT: it is an overlay colour carrying the alpha the
    // shell composites over layer 0 with, so transparentizing it only ever made this
    // more see-through. colLayer1Base is the solid surface underneath, which is what
    // the shell itself reaches for when something must actually cover what is behind.
    readonly property color panelColor: Appearance.colors.colLayer1Base

    color: root.panelColor
    radius: Appearance.rounding.normal

    property string query: ""

    readonly property var chats: root.service?.chats ?? []
    readonly property string currentId: root.service?.currentChatId ?? ""

    /** Flat list of section headers and chats, so one ListView renders both. */
    readonly property var rows: {
        const needle = root.query.trim().toLowerCase();
        const matched = needle.length === 0 ? root.chats : root.chats.filter(chat =>
            (chat.title ?? "").toLowerCase().includes(needle)
            || (chat.preview ?? "").toLowerCase().includes(needle));

        let out = [];
        let group = "";
        for (const chat of matched) {
            const label = root.groupFor(chat.updatedAt ?? 0);
            if (label !== group) {
                group = label;
                out.push({ "kind": "header", "label": label });
            }
            out.push({ "kind": "chat", "chat": chat });
        }
        return out;
    }

    function groupFor(stamp) {
        const now = new Date();
        const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const day = 86400000;
        if (stamp >= midnight) return "Today";
        if (stamp >= midnight - day) return "Yesterday";
        if (stamp >= midnight - 7 * day) return "Earlier this week";
        if (stamp >= midnight - 30 * day) return "Earlier this month";
        return "Older";
    }

    function focusSearch() {
        searchField.forceActiveFocus();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout { // Header
            Layout.fillWidth: true
            spacing: 6

            MaterialTextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: `Search ${root.chats.length} conversation${root.chats.length === 1 ? "" : "s"}…`
                onTextChanged: root.query = text
                // Esc backs out of the search before it backs out of the panel, so a
                // stray filter never leaves the list looking empty.
                Keys.onEscapePressed: {
                    if (text.length > 0) text = "";
                    else root.requestClose();
                }
            }

            HistoryIconButton {
                symbol: "add_comment"
                tooltip: "Start a new conversation"
                onClicked: {
                    root.service?.newChat();
                    root.requestClose();
                }
            }

            HistoryIconButton {
                symbol: "close"
                tooltip: "Close history"
                onClicked: root.requestClose()
            }
        }

        Item { // Plain parent, so the fade can anchor to the list as its sibling
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.rows.length > 0

            StyledListView {
                id: listView
                anchors.fill: parent
                clip: true
                spacing: 2
                model: root.rows

                delegate: Item {
                    id: row
                    required property var modelData
                    width: listView.width
                    implicitHeight: loader.item?.implicitHeight ?? 0

                    Loader {
                        id: loader
                        width: row.width
                        sourceComponent: row.modelData.kind === "header" ? headerComponent : cardComponent

                        Component {
                            id: headerComponent
                            StyledText {
                                topPadding: 10
                                bottomPadding: 2
                                leftPadding: 4
                                text: row.modelData.label
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                            }
                        }

                        Component {
                            id: cardComponent
                            ChatHistoryRow {
                                service: root.service
                                chat: row.modelData.chat
                                current: row.modelData.chat.id === root.currentId
                                onOpenRequested: {
                                    root.service?.openChat(row.modelData.chat.id);
                                    root.requestClose();
                                }
                            }
                        }
                    }
                }
            }

            // Rows dissolve into the panel at both ends instead of being sliced off by
            // the clip, which is what makes a scrolling list read as scrollable.
            ScrollEdgeFade {
                z: 1
                target: listView
                color: root.panelColor
                fadeSize: 28
            }
        }

        Item { // PagePlaceholder anchors itself, so it needs a plain parent in a layout
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.rows.length === 0

            PagePlaceholder { // Nothing to show, for one of two quite different reasons
                shown: root.rows.length === 0
                icon: root.chats.length === 0 ? "forum" : "search_off"
                title: root.chats.length === 0 ? "No conversations yet" : "No matches"
                description: root.chats.length === 0
                    ? "Chats are saved here as soon as you send a message."
                    : `Nothing matching “${root.query}”.`
            }
        }
    }

    /** Small square icon button, used for the header actions. */
    component HistoryIconButton: RippleButton {
        id: iconButton
        required property string symbol
        property string tooltip: ""

        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: iconButton.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.m3colors.m3onSurface
        }

        StyledToolTip {
            text: iconButton.tooltip
            extraVisibleCondition: iconButton.tooltip.length > 0
        }
    }
}
