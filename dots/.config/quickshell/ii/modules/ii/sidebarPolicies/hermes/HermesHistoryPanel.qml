pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Stored conversations: search, open, delete.
 *
 * Rows come from the agent's own `session.list`, so this shows every Hermes
 * session -- including ones started in the terminal or the desktop app, not just
 * the ones opened here.
 */
Rectangle {
    id: root

    signal requestClose

    // Opaque. colLayer1 is NOT: it is an overlay colour carrying the alpha the
    // shell composites over layer 0 with, so transparentizing it only ever made
    // this more see-through. colLayer1Base is the solid surface underneath.
    readonly property color panelColor: Appearance.colors.colLayer1Base

    color: root.panelColor
    radius: Appearance.rounding.normal

    property string query: ""

    readonly property var sessions: HermesService.recentSessions ?? []
    readonly property string currentId: HermesService.storedSessionId

    /** Flat list of section headers and sessions, so one ListView renders both. */
    readonly property var rows: {
        const needle = root.query.trim().toLowerCase();
        const matched = needle.length === 0 ? root.sessions : root.sessions.filter(session =>
            (session.title ?? "").toLowerCase().includes(needle)
            || (session.preview ?? "").toLowerCase().includes(needle));

        let out = [];
        let group = "";
        for (const session of matched) {
            // session.list reports seconds; the grouping works in milliseconds.
            const label = root.groupFor((session.started_at ?? 0) * 1000);
            if (label !== group) {
                group = label;
                out.push({
                    "kind": "header",
                    "label": label
                });
            }
            out.push({
                "kind": "session",
                "session": session
            });
        }
        return out;
    }

    function groupFor(stamp: real): string {
        const now = new Date();
        const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const day = 86400000;
        if (stamp >= midnight)
            return Translation.tr("Today");
        if (stamp >= midnight - day)
            return Translation.tr("Yesterday");
        if (stamp >= midnight - 7 * day)
            return Translation.tr("Earlier this week");
        if (stamp >= midnight - 30 * day)
            return Translation.tr("Earlier this month");
        return Translation.tr("Older");
    }

    function focusSearch(): void {
        searchField.forceActiveFocus();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout { // Header
            Layout.fillWidth: true
            spacing: 4

            MaterialTextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search %1 conversations…").arg(root.sessions.length)
                onTextChanged: root.query = text
                // Esc backs out of the search before it backs out of the panel, so a
                // stray filter never leaves the list looking empty.
                Keys.onEscapePressed: {
                    if (text.length > 0)
                        text = "";
                    else
                        root.requestClose();
                }
            }

            HistoryIconButton {
                symbol: "add_comment"
                tooltip: Translation.tr("Start a new conversation")
                onReleased: {
                    HermesService.newSession();
                    root.requestClose();
                }
            }

            HistoryIconButton {
                symbol: "close"
                tooltip: Translation.tr("Close history")
                onReleased: root.requestClose()
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
                                topPadding: 12
                                bottomPadding: 4
                                leftPadding: 4
                                text: row.modelData.label
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                            }
                        }

                        Component {
                            id: cardComponent
                            HermesHistoryRow {
                                session: row.modelData.session
                                current: row.modelData.session.id === root.currentId
                                onOpenRequested: {
                                    HermesService.resumeSession(row.modelData.session.id);
                                    root.requestClose();
                                }
                            }
                        }
                    }
                }
            }

            // Rows dissolve into the panel at both ends instead of being sliced off
            // by the clip, which is what makes a scrolling list read as scrollable.
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
                icon: root.sessions.length === 0 ? "forum" : "search_off"
                title: root.sessions.length === 0 ? Translation.tr("No conversations yet") : Translation.tr("No matches")
                description: root.sessions.length === 0 ? Translation.tr("Chats are saved as soon as you send a message.") : Translation.tr("Nothing matching “%1”.").arg(root.query)
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
