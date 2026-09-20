pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Everything Hermes has in flight, and what it did before.
 *
 * Live holds the three kinds of work that outlive a message -- background
 * turns, side questions, delegated children and anything the agent left
 * running -- and History holds saved delegation runs. Account and vault used
 * to be a third tab here; they are settings, and live in the settings app now.
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

    readonly property var tabs: [
        {
            icon: "play_circle",
            name: Translation.tr("Live")
        },
        {
            icon: "history",
            name: Translation.tr("History")
        }
    ]

    function refreshActiveTab(): void {
        // Live refreshes itself -- it owns the polling that only runs while a
        // turn is in flight, which this button must not bypass.
        if (tabBar.currentIndex === 0) {
            liveTab.refreshAll();
            return;
        }
        HermesService.refreshSpawnTrees();
    }

    // Covers both ways this panel tends to get mounted: a Loader that
    // constructs it fresh each open (onCompleted), and a permanent child
    // whose visibility is toggled by opacity, same as HermesHistoryPanel
    // (onVisibleChanged catches the false -> true edge).
    Component.onCompleted: root.refreshActiveTab()
    onVisibleChanged: if (root.visible)
        root.refreshActiveTab()

    /** "2h 05m", "45s" -- a process's uptime and a spawn tree's run length are
     * the same kind of number, so both go through this. */
    function formatDuration(seconds: real): string {
        const total = Math.max(0, Math.floor(seconds ?? 0));
        const days = Math.floor(total / 86400);
        const hours = Math.floor((total % 86400) / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const secs = total % 60;
        if (days > 0)
            return Translation.tr("%1d %2h").arg(days).arg(hours);
        if (hours > 0)
            return Translation.tr("%1h %2m").arg(hours).arg(minutes);
        if (minutes > 0)
            return Translation.tr("%1m %2s").arg(minutes).arg(secs);
        return Translation.tr("%1s").arg(secs);
    }

    function formatTimestamp(unixSeconds: real): string {
        const stamp = unixSeconds ?? 0;
        if (stamp <= 0)
            return Translation.tr("Unknown time");
        return Qt.formatDateTime(new Date(stamp * 1000), "MMM d, HH:mm");
    }

    /**
     * Normalizes a loaded spawn tree's subagents for the indented list. Rows
     * with no goal are skipped -- there is nothing meaningful to show for
     * them, and printing "undefined" is worse than leaving them out.
     */
    function subagentRowsFor(tree: var): var {
        const list = tree?.subagents ?? [];
        const out = [];
        for (const entry of list) {
            const goal = (entry?.goal ?? "").toString().trim();
            if (goal.length === 0)
                continue;
            const meta = [(entry.model ?? "").toString(), (entry.status ?? "").toString(), (entry.tool_count ?? null) !== null ? Translation.tr("%1 tool calls").arg(entry.tool_count) : "", (entry.last_tool ?? "").toString()].filter(part => part.length > 0).join("  ·  ");
            out.push({
                depth: Math.max(0, entry.depth ?? 0),
                goal: goal,
                meta: meta
            });
        }
        return out;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout { // Header
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Hermes work")
                color: Appearance.colors.colOnLayer1
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.large
                    variableAxes: Appearance.font.variableAxes.title
                }
            }

            PanelIconButton {
                symbol: "refresh"
                tooltip: Translation.tr("Refresh")
                onReleased: root.refreshActiveTab()
            }

            PanelIconButton {
                symbol: "close"
                tooltip: Translation.tr("Close")
                onReleased: root.requestClose()
            }
        }

        SecondaryTabBar {
            id: tabBar
            onCurrentIndexChanged: root.refreshActiveTab()

            Repeater {
                model: root.tabs
                delegate: SecondaryTabButton {
                    required property var modelData
                    buttonIcon: modelData.icon
                    buttonText: modelData.name
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            HermesSideTasksPanel {
                id: liveTab
                anchors.fill: parent
                embedded: true
                visible: tabBar.currentIndex === 0
            }
            SpawnTreesTab {
                anchors.fill: parent
                visible: tabBar.currentIndex === 1
            }
        }
    }

    // ── Tab 2: saved delegation runs ────────────────────────────────────

    component SpawnTreesTab: Item {
        id: treeTab

        readonly property var entries: {
            const list = (HermesService.spawnTrees ?? []).slice();
            list.sort((a, b) => (b.started_at ?? 0) - (a.started_at ?? 0));
            return list;
        }

        property string loadingPath: ""
        property var loadedTree: null // { session_id, started_at, finished_at, label, subagents }
        property bool showingDetail: false

        // Crossfade-and-shift page swap between the run list and a loaded
        // tree -- the same recipe Continuity.qml uses for its notification
        // drill-in: fade+shift out on fast effects/accel, swap the content at
        // the midpoint, fade+shift back in on default spatial/effects.
        property real swapOpacity: 1
        property real swapShift: 0

        function openEntry(entry: var): void {
            if (!entry || (entry.path ?? "").length === 0)
                return;
            treeTab.loadingPath = entry.path;
            HermesService.loadSpawnTree(entry.path, payload => {
                treeTab.loadingPath = "";
                if (!payload)
                    return;
                treeTab.loadedTree = payload;
                treeTab.showingDetail = true;
                swapAnim.restart();
            });
        }

        function closeDetail(): void {
            treeTab.showingDetail = false;
            swapAnim.restart();
        }

        SequentialAnimation {
            id: swapAnim
            ParallelAnimation {
                NumberAnimation {
                    target: treeTab
                    property: "swapOpacity"
                    to: 0
                    duration: Appearance.animationCurves.expressiveFastEffectsDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                }
                NumberAnimation {
                    target: treeTab
                    property: "swapShift"
                    to: treeTab.showingDetail ? -12 : 12
                    duration: Appearance.animationCurves.expressiveFastEffectsDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                }
            }
            ScriptAction {
                script: treeTab.swapShift = treeTab.showingDetail ? 12 : -12
            }
            ParallelAnimation {
                NumberAnimation {
                    target: treeTab
                    property: "swapOpacity"
                    to: 1
                    duration: Appearance.animationCurves.expressiveEffectsDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                }
                NumberAnimation {
                    target: treeTab
                    property: "swapShift"
                    to: 0
                    duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: !treeTab.showingDetail
            opacity: treeTab.swapOpacity
            transform: Translate {
                y: treeTab.swapShift
            }

            Item {
                anchors.fill: parent
                visible: treeTab.entries.length > 0

                StyledListView {
                    id: treeList
                    anchors.fill: parent
                    clip: true
                    spacing: 8
                    model: treeTab.entries

                    delegate: RippleButton {
                        id: treeRow
                        required property var modelData
                        width: treeList.width
                        implicitHeight: treeContent.implicitHeight + 20
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover

                        readonly property bool loadingThis: treeTab.loadingPath.length > 0 && treeTab.loadingPath === (treeRow.modelData.path ?? "")

                        releaseAction: () => treeTab.openEntry(treeRow.modelData)

                        contentItem: RowLayout {
                            id: treeContent
                            spacing: 10

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "account_tree"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer2
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: (treeRow.modelData.label ?? "").length > 0 ? treeRow.modelData.label : root.formatTimestamp(treeRow.modelData.started_at ?? 0)
                                    color: Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: treeRow.loadingThis ? Translation.tr("Loading…") : [Translation.tr("%1 subagents").arg(treeRow.modelData.count ?? 0), root.formatDuration((treeRow.modelData.finished_at ?? 0) - (treeRow.modelData.started_at ?? 0))].join("  ·  ")
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: treeTab.entries.length === 0

                PagePlaceholder {
                    shown: treeTab.entries.length === 0
                    icon: "account_tree"
                    title: Translation.tr("No delegation runs yet")
                    description: Translation.tr("Runs are saved here once the agent spawns subagents.")
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            visible: treeTab.showingDetail
            opacity: treeTab.swapOpacity
            transform: Translate {
                y: treeTab.swapShift
            }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                PanelIconButton {
                    symbol: "arrow_back"
                    tooltip: Translation.tr("Back to runs")
                    onReleased: treeTab.closeDetail()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: (treeTab.loadedTree?.label ?? "").length > 0 ? treeTab.loadedTree.label : root.formatTimestamp(treeTab.loadedTree?.started_at ?? 0)
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.formatDuration((treeTab.loadedTree?.finished_at ?? 0) - (treeTab.loadedTree?.started_at ?? 0))
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledListView {
                    id: subList
                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: root.subagentRowsFor(treeTab.loadedTree)

                    delegate: RowLayout {
                        id: subRow
                        required property var modelData
                        width: subList.width
                        spacing: 6

                        Item {
                            Layout.preferredWidth: subRow.modelData.depth * 16
                        }
                        MaterialSymbol {
                            visible: subRow.modelData.depth > 0
                            text: "subdirectory_arrow_right"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                wrapMode: Text.Wrap
                                text: subRow.modelData.goal
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                visible: text.length > 0
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: subRow.modelData.meta
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }

    component PanelIconButton: RippleButton {
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
