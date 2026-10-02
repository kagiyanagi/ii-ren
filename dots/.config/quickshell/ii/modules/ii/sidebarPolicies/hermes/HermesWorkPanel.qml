pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Everything Hermes has in flight, and what it did before, on one page.
 *
 * Live and History used to be two tabs, and Live was empty nearly every time
 * the sheet opened, so the first thing it showed was a void with the saved
 * runs one click away. Now the running work leads and the saved delegation
 * runs follow it; a run opens its detail page over the list.
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

    property string loadingPath: ""
    property var loadedTree: null // { session_id, started_at, finished_at, label, subagents }
    property bool showingDetail: false

    function refresh(): void {
        // Live owns the polling that only runs while a turn is in flight;
        // this asks once and leaves that alone.
        liveTab.refreshAll();
        HermesService.refreshSpawnTrees();
    }

    // A permanent child of Hermes.qml whose visibility follows its opacity, so
    // the false -> true edge is the open.
    onVisibleChanged: if (root.visible)
        root.refresh()

    function openEntry(entry: var): void {
        if (!entry || (entry.path ?? "").length === 0)
            return;
        root.loadingPath = entry.path;
        HermesService.loadSpawnTree(entry.path, payload => {
            root.loadingPath = "";
            if (!payload)
                return;
            root.loadedTree = payload;
            root.showingDetail = true;
        });
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
                onReleased: root.refresh()
            }

            HermesIconButton {
                symbol: "close"
                tooltip: Translation.tr("Close")
                onReleased: root.requestClose()
            }
        }

        PageSwap {
            id: pageSwap
            Layout.fillWidth: true
            Layout.fillHeight: true
            page: root.showingDetail ? 1 : 0

            HermesSideTasksPanel {
                id: liveTab
                anchors.fill: parent
                visible: pageSwap.shownPage === 0
                loadingRunPath: root.loadingPath
                onRunOpened: entry => root.openEntry(entry)
            }

            ColumnLayout {
                anchors.fill: parent
                visible: pageSwap.shownPage === 1
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    HermesIconButton {
                        symbol: "arrow_back"
                        tooltip: Translation.tr("Back to runs")
                        onReleased: root.showingDetail = false
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: (root.loadedTree?.label ?? "").length > 0 ? root.loadedTree.label : liveTab.formatTimestamp(root.loadedTree?.started_at ?? 0)
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: liveTab.elapsedSeconds((root.loadedTree?.finished_at ?? 0) - (root.loadedTree?.started_at ?? 0))
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
                        model: root.subagentRowsFor(root.loadedTree)

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
