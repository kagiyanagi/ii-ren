pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Notification history, Android-style: every notification the shell received
 * while `notifications.history.enable` was on, grouped by app, newest first.
 *
 * Settings is its own process, so this reads the file Notifications.qml writes
 * instead of the service (instantiating the service here would start a second
 * notification server).
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack

    property var entries: []
    property string query: ""
    property string expandedApp: ""

    readonly property var groups: {
        const q = subPageRoot.query.trim().toLowerCase();
        const byApp = {};
        for (const n of subPageRoot.entries) {
            if (q && ![n.appName, n.summary, n.body].some(s => (s ?? "").toLowerCase().includes(q)))
                continue;
            const key = n.appName || Translation.tr("Unknown app");
            (byApp[key] = byApp[key] ?? { appName: key, appIcon: n.appIcon, items: [] }).items.push(n);
        }
        return Object.values(byApp).map(g => {
            g.items.sort((a, b) => b.time - a.time);
            return g;
        }).sort((a, b) => b.items[0].time - a.items[0].time);
    }

    function plainBody(n) {
        return NotificationUtils.processNotificationBody(n.body ?? "", n.appName).replace(/<[^>]*>/g, "").trim();
    }

    FileView {
        id: historyFile
        path: Directories.notificationHistoryPath
        printErrors: false // absent until the first entry
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                subPageRoot.entries = JSON.parse(historyFile.text() || "[]");
            } catch (e) {
                subPageRoot.entries = [];
            }
        }
        onLoadFailed: subPageRoot.entries = []
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: true
        title: Translation.tr("Notification history")
        showBackButton: subPageRoot.showBackButton
        onGoBack: subPageRoot.goBack()

        ContentGroup {
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search notifications")
                    onTextChanged: subPageRoot.query = text
                }

                RippleButtonWithIcon {
                    enabled: subPageRoot.entries.length > 0
                    materialIcon: "delete_sweep"
                    mainText: Translation.tr("Clear")
                    onClicked: {
                        historyFile.setText("[]");
                        subPageRoot.entries = [];
                    }
                }
            }

            // The page's empty state, one per reason it is empty (TASTE 6.2-6.3).
            Item {
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.pagePlaceholderHeight
                visible: subPageRoot.groups.length === 0

                PagePlaceholder {
                    anchors.fill: parent
                    shape: MaterialShape.Shape.Circle
                    icon: subPageRoot.entries.length > 0 ? "search_off"
                        : Config.options.notifications.history.enable ? "notifications" : "history_toggle_off"
                    title: subPageRoot.entries.length > 0 ? Translation.tr("No matches")
                        : Config.options.notifications.history.enable ? Translation.tr("No notifications yet")
                        : Translation.tr("Notification history is off")
                    description: subPageRoot.entries.length > 0 ? Translation.tr("No notifications match your search.")
                        : Config.options.notifications.history.enable ? Translation.tr("Notifications you receive will show up here.")
                        : Translation.tr("Turn on notification history to keep a record of the notifications you receive.")
                }
            }

            Repeater {
                model: subPageRoot.groups

                delegate: Rectangle {
                    id: groupCard

                    required property var modelData
                    readonly property bool expanded: subPageRoot.expandedApp === groupCard.modelData.appName
                    readonly property var latest: groupCard.modelData.items[0]
                    // Rows are built on first open and kept, so collapsing has
                    // something to animate away; closed-and-never-opened groups
                    // with hundreds of entries cost nothing.
                    property bool everOpened: false
                    onExpandedChanged: if (expanded) everOpened = true

                    Layout.fillWidth: true
                    implicitHeight: groupColumn.implicitHeight + 8
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        id: groupColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        spacing: 0

                        RippleButton {
                            Layout.fillWidth: true
                            leftPadding: 12
                            rightPadding: 12
                            implicitHeight: headerRow.implicitHeight + 16
                            buttonRadius: Appearance.rounding.verysmall
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 1)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: subPageRoot.expandedApp = groupCard.expanded ? "" : groupCard.modelData.appName

                            contentItem: RowLayout {
                                id: headerRow
                                spacing: 12

                                NotificationAppIcon {
                                    appIcon: groupCard.modelData.appIcon ?? ""
                                    summary: groupCard.latest.summary ?? ""
                                    urgency: groupCard.latest.urgency ?? ""
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: groupCard.modelData.appName
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer2
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: groupCard.expanded ? Translation.tr("%1 notifications").arg(groupCard.modelData.items.length)
                                            : [groupCard.latest.summary, subPageRoot.plainBody(groupCard.latest)].filter(s => s).join(" · ")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                StyledText {
                                    text: NotificationUtils.getFriendlyNotifTimeString(groupCard.latest.time)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }

                                MaterialSymbol {
                                    text: groupCard.expanded ? "expand_less" : "expand_more"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }

                        Revealer {
                            Layout.fillWidth: true
                            vertical: true
                            reveal: groupCard.expanded

                            ColumnLayout {
                                width: parent.width
                                spacing: 4

                                Repeater {
                                    model: groupCard.everOpened ? groupCard.modelData.items : []

                                    delegate: ColumnLayout {
                                        id: entry

                                        required property var modelData

                                        Layout.fillWidth: true
                                        Layout.leftMargin: 12
                                        Layout.rightMargin: 12
                                        Layout.bottomMargin: 8
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: entry.modelData.summary ?? ""
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.DemiBold
                                                color: Appearance.colors.colOnLayer2
                                            }

                                            StyledText {
                                                text: Qt.formatDateTime(new Date(entry.modelData.time), "MMM d, hh:mm")
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colSubtext
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: subPageRoot.plainBody(entry.modelData)
                                            wrapMode: Text.Wrap
                                            elide: Text.ElideNone
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnLayer2
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
