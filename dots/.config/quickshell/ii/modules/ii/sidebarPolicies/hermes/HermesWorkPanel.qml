pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

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

    // A permanent child of Hermes.qml whose visibility follows its opacity, so
    // the false -> true edge is the open.
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

            HermesIconButton {
                symbol: "refresh"
                tooltip: Translation.tr("Refresh")
                onReleased: root.refreshActiveTab()
            }

            HermesIconButton {
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

        PageSwap {
            id: tabSwap
            Layout.fillWidth: true
            Layout.fillHeight: true
            page: tabBar.currentIndex

            HermesSideTasksPanel {
                id: liveTab
                anchors.fill: parent
                visible: tabSwap.shownPage === 0
            }
            SpawnTreesTab {
                anchors.fill: parent
                visible: tabSwap.shownPage === 1
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
            });
        }

        PageSwap {
            id: detailSwap
            anchors.fill: parent
            page: treeTab.showingDetail ? 1 : 0

            Item {
                anchors.fill: parent
                visible: detailSwap.shownPage === 0

                Item {
                    anchors.fill: parent
                    visible: treeTab.entries.length > 0

                    StyledListView {
                        id: treeList
                        anchors.fill: parent
                        clip: true
                        spacing: 8
                        // Every save replaces spawnTrees; keyed, a new run is one insert.
                        model: ScriptModel {
                            objectProp: "path"
                            values: treeTab.entries
                        }

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
                visible: detailSwap.shownPage === 1
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    HermesIconButton {
                        symbol: "arrow_back"
                        tooltip: Translation.tr("Back to runs")
                        onReleased: treeTab.showingDetail = false
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
    }

    /**
     * Fade-through between the pages of one area. The old page leaves on the
     * fast effects spec and the new one arrives on the default spatial one.
     * `page` is what was asked for and `shownPage` is what is drawn; only the
     * midpoint moves it, so neither page changes on the first frame.
     */
    component PageSwap: Item {
        id: swap
        property int page: 0
        property int shownPage: 0
        property bool forward: true

        onPageChanged: {
            swap.forward = swap.page > swap.shownPage;
            swapAnim.restart();
        }

        transform: Translate {
            id: shift
        }

        SequentialAnimation {
            id: swapAnim
            ParallelAnimation {
                NumberAnimation {
                    target: swap
                    property: "opacity"
                    to: 0
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                }
                NumberAnimation {
                    target: shift
                    property: "y"
                    to: swap.forward ? -12 : 12
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                }
            }
            ScriptAction {
                script: {
                    swap.shownPage = swap.page;
                    shift.y = swap.forward ? 12 : -12;
                }
            }
            ParallelAnimation {
                NumberAnimation {
                    target: swap
                    property: "opacity"
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
                NumberAnimation {
                    target: shift
                    property: "y"
                    to: 0
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
            }
        }
    }
}
