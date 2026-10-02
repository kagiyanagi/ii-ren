pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Side work: background turns, `btw` questions, and the current turn's
 * delegated children -- everything running off to the side of the main
 * conversation rather than in it -- then the saved delegation runs, newest
 * first. The page of HermesWorkPanel, which draws the sheet and the header,
 * refreshes this when it is shown and opens a run's detail.
 */
Item {
    id: root

    readonly property var sideTasks: HermesService.sideTasks ?? []
    readonly property var subagents: HermesService.subagents ?? []
    readonly property var processes: HermesService.agentProcesses ?? []
    readonly property var runs: (HermesService.spawnTrees ?? []).slice().sort((a, b) => (b.started_at ?? 0) - (a.started_at ?? 0))
    readonly property bool hasFinishedSideTasks: root.sideTasks.some(task => task.done)

    // The run whose detail is being fetched, so its row can say so.
    property string loadingRunPath: ""
    signal runOpened(var entry)

    // Per-child UI state, keyed by subagent_id on root rather than held on the
    // row: the rows are keyed now and survive a poll, but a child that drops
    // out of subagent.list and comes back is a new delegate.
    property var expandedTail: ({})
    property var tailText: ({})
    property var tailAvailable: ({})
    property var steerDraft: ({})

    property double nowMs: Date.now()

    function isTailExpanded(id: string): bool {
        return root.expandedTail[id] === true;
    }

    function setTailExpanded(id: string, expanded: bool): void {
        root.expandedTail = Object.assign({}, root.expandedTail, {
            [id]: expanded
        });
        if (expanded)
            root._pollTail(id);
    }

    function _pollTail(id: string): void {
        HermesService.tailSubagent(id, (text, available) => {
            root.tailText = Object.assign({}, root.tailText, {
                [id]: text
            });
            root.tailAvailable = Object.assign({}, root.tailAvailable, {
                [id]: available
            });
        });
    }

    function steerDraftFor(id: string): string {
        return root.steerDraft[id] ?? "";
    }

    function setSteerDraft(id: string, text: string): void {
        root.steerDraft = Object.assign({}, root.steerDraft, {
            [id]: text
        });
    }

    function sendSteer(id: string): void {
        const text = root.steerDraftFor(id).trim();
        if (text.length === 0)
            return;
        HermesService.steerSubagent(id, text);
        root.setSteerDraft(id, "");
    }

    /** "2h 05m", "45s" -- a process's uptime and a saved run's length. */
    function elapsedSeconds(secs: real): string {
        const whole = Math.max(0, Math.round(secs ?? 0));
        if (whole < 60)
            return Translation.tr("%1s").arg(whole);
        if (whole < 3600)
            return Translation.tr("%1m %2s").arg(Math.floor(whole / 60)).arg(whole % 60);
        if (whole < 86400)
            return Translation.tr("%1h %2m").arg(Math.floor(whole / 3600)).arg(Math.floor((whole % 3600) / 60));
        return Translation.tr("%1d %2h").arg(Math.floor(whole / 86400)).arg(Math.floor((whole % 86400) / 3600));
    }

    function formatTimestamp(unixSeconds: real): string {
        const stamp = unixSeconds ?? 0;
        if (stamp <= 0)
            return Translation.tr("Unknown time");
        return Qt.formatDateTime(new Date(stamp * 1000), "MMM d, HH:mm");
    }

    function elapsed(startedAt: real): string {
        const secs = Math.max(0, Math.round((root.nowMs - startedAt) / 1000));
        if (secs < 60)
            return Translation.tr("%1s").arg(secs);
        return Translation.tr("%1m %2s").arg(Math.floor(secs / 60)).arg(secs % 60);
    }

    /**
     * Flat list of section headers and rows, so one ListView renders every
     * kind. `key` is what the ScriptModel matches a poll's fresh objects on:
     * a header by its kind, a row by its own id, and the index only where the
     * gateway gave no id.
     */
    readonly property var rows: {
        let out = [];
        if (root.sideTasks.length > 0) {
            out.push({
                "kind": "tasksHeader",
                "key": "tasksHeader"
            });
            // Running above finished; the service appends, so a new task
            // would otherwise land under the ones already done.
            root.sideTasks.map((task, i) => [task, i]).sort((a, b) => a[0].done - b[0].done).forEach(([task, i]) => out.push({
                "kind": "task",
                "key": "task:" + (task.taskId || i),
                "task": task
            }));
        }
        if (root.subagents.length > 0) {
            out.push({
                "kind": "subagentsHeader",
                "key": "subagentsHeader"
            });
            root.subagents.forEach((subagent, i) => out.push({
                "kind": "subagent",
                "key": "subagent:" + (subagent.subagent_id || i),
                "subagent": subagent
            }));
        }
        if (root.processes.length > 0) {
            out.push({
                "kind": "processesHeader",
                "key": "processesHeader"
            });
            root.processes.forEach((process, i) => out.push({
                "kind": "process",
                "key": "process:" + (process.session_id || i),
                "process": process
            }));
        }
        if (root.runs.length > 0) {
            // Saved runs under an empty live list would read as running work.
            if (out.length === 0)
                out.push({
                    "kind": "idle",
                    "key": "idle"
                });
            out.push({
                "kind": "runsHeader",
                "key": "runsHeader"
            });
            root.runs.forEach((run, i) => out.push({
                "kind": "run",
                "key": "run:" + (run.path || i),
                "run": run
            }));
        }
        return out;
    }

    // One shared timer for every open tail, rather than one per row.
    Timer {
        interval: 1500
        repeat: true
        running: root.visible && Object.values(root.expandedTail).some(open => open)
        onTriggered: Object.keys(root.expandedTail).forEach(id => {
            if (root.expandedTail[id])
                root._pollTail(id);
        })
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible && HermesService.runningSideTasks > 0
        onTriggered: root.nowMs = Date.now()
    }

    function refreshAll(): void {
        HermesService.refreshDelegation();
        HermesService.refreshAgentProcesses();
    }

    Item { // Plain parent, so the fade can anchor to the list as its sibling
        anchors.fill: parent
        visible: root.rows.length > 0

        StyledListView {
            id: listView
            anchors.fill: parent
            clip: true
            spacing: 8
            model: ScriptModel {
                objectProp: "key"
                values: root.rows
            }

            delegate: DelegateChooser {
                role: "kind"

                DelegateChoice {
                    roleValue: "tasksHeader"
                    SectionHeader {
                        text: Translation.tr("Background & side work")

                        HermesIconButton {
                            visible: root.hasFinishedSideTasks
                            symbol: "clear_all"
                            tooltip: Translation.tr("Clear finished")
                            onReleased: HermesService.clearFinishedSideTasks()
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "subagentsHeader"
                    SectionHeader {
                        text: Translation.tr("Delegated children")

                        StyledText {
                            text: Translation.tr("Pause spawning")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledSwitch {
                            checked: HermesService.spawnPaused
                            onToggled: HermesService.setSpawnPaused(checked)
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "processesHeader"
                    SectionHeader {
                        text: Translation.tr("Background processes")
                    }
                }

                DelegateChoice {
                    roleValue: "idle"
                    StyledText {
                        required property var modelData
                        width: listView.width
                        leftPadding: 4
                        text: Translation.tr("Nothing running right now")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                DelegateChoice {
                    roleValue: "runsHeader"
                    SectionHeader {
                        text: Translation.tr("Past delegation runs")
                    }
                }

                DelegateChoice {
                    roleValue: "run"
                    RippleButton {
                        id: runRow
                        required property var modelData
                        readonly property var run: runRow.modelData.run
                        readonly property bool loadingThis: root.loadingRunPath.length > 0 && root.loadingRunPath === (runRow.run.path ?? "")

                        width: listView.width
                        implicitHeight: runContent.implicitHeight + 20
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active

                        releaseAction: () => root.runOpened(runRow.run)

                        contentItem: RowLayout {
                            id: runContent
                            spacing: 10

                            MaterialSymbol {
                                Layout.leftMargin: 2
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
                                    text: (runRow.run.label ?? "").length > 0 ? runRow.run.label : root.formatTimestamp(runRow.run.started_at ?? 0)
                                    color: Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: runRow.loadingThis ? Translation.tr("Loading…") : [Translation.tr("%1 subagents").arg(runRow.run.count ?? 0), root.elapsedSeconds((runRow.run.finished_at ?? 0) - (runRow.run.started_at ?? 0))].join("  ·  ")
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "task"
                    Rectangle {
                        id: taskCard
                        required property var modelData
                        readonly property var task: taskCard.modelData.task
                        readonly property bool failed: taskCard.task.failed ?? false

                        width: listView.width
                        implicitHeight: taskColumn.implicitHeight + 8 * 2
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        ColumnLayout {
                            id: taskColumn
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: 8
                            }
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Loader {
                                    active: !taskCard.task.done
                                    sourceComponent: MaterialLoadingIndicator {
                                        // 20 is the established inline-icon size for
                                        // this widget -- see Hermes.qml's activity line.
                                        implicitSize: 20
                                        loading: true
                                    }
                                }

                                MaterialSymbol {
                                    visible: taskCard.task.done
                                    iconSize: Appearance.font.pixelSize.normal
                                    text: taskCard.failed ? "error" : "check_circle"
                                    color: taskCard.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: taskCard.task.kind === "btw" ? Translation.tr("Side question") : Translation.tr("Background task")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer2
                                }

                                StyledText {
                                    visible: !taskCard.task.done
                                    text: root.elapsed(taskCard.task.startedAt)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: Appearance.font.family.numbers
                                    color: Appearance.colors.colSubtext
                                }

                                CardIconButton {
                                    symbol: "close"
                                    tooltip: Translation.tr("Dismiss")
                                    onReleased: HermesService.dismissSideTask(taskCard.task.taskId)
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                text: taskCard.task.text ?? ""
                            }

                            TextEdit { // Selectable/copyable result
                                Layout.fillWidth: true
                                visible: taskCard.task.done && text.length > 0
                                readOnly: true
                                selectByMouse: true
                                wrapMode: Text.Wrap
                                textFormat: TextEdit.PlainText
                                renderType: Text.NativeRendering
                                font.family: Appearance.font.family.main
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: taskCard.failed ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                                selectionColor: Appearance.colors.colSecondaryContainer
                                text: taskCard.task.result ?? ""

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.NoButton
                                    hoverEnabled: true
                                    cursorShape: Qt.IBeamCursor
                                }
                            }
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "process"
                    Rectangle {
                        id: processCard
                        required property var modelData
                        readonly property var process: processCard.modelData.process

                        width: listView.width
                        implicitHeight: processColumn.implicitHeight + 12 * 2
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        ColumnLayout {
                            id: processColumn
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                                rightMargin: 12
                            }
                            spacing: 4

                            StyledText {
                                Layout.fillWidth: true
                                text: processCard.process.command ?? ""
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const status = processCard.process.status ?? "";
                                    const up = root.elapsedSeconds(processCard.process.uptime ?? 0);
                                    return status.length > 0 ? Translation.tr("%1 · up %2").arg(status).arg(up) : Translation.tr("up %1").arg(up);
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "subagent"
                    Item {
                        id: subRow
                        required property var modelData
                        readonly property var subagent: subRow.modelData.subagent
                        readonly property string subId: subRow.subagent.subagent_id ?? ""
                        readonly property bool tailOpen: root.isTailExpanded(subRow.subId)
                        readonly property bool canSteer: subRow.subagent.accepting_steer === true
                        // Indent by nesting depth. The card sits in a plain Item
                        // because a ListView owns its delegate's position.
                        readonly property real indent: Math.min((subRow.subagent.depth ?? 0) * 16, 64)

                        width: listView.width
                        implicitHeight: subCard.implicitHeight

                        Rectangle {
                            id: subCard
                            x: subRow.indent
                            width: subRow.width - subRow.indent
                            // The Revealer below animates the tail; this follows it.
                            implicitHeight: subColumn.implicitHeight + 8 * 2
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            ColumnLayout {
                                id: subColumn
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 8
                                }
                                spacing: 4

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                    text: subRow.subagent.goal ?? ""
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    StyledText {
                                        text: subRow.subagent.status ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colSubtext
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.family: Appearance.font.family.monospace
                                        color: Appearance.colors.colSubtext
                                        text: {
                                            const model = subRow.subagent.model ?? "";
                                            const tools = Translation.tr("%1 tools").arg(subRow.subagent.tool_count ?? 0);
                                            const lastTool = subRow.subagent.last_tool ?? "";
                                            const parts = [model, tools];
                                            if (lastTool.length > 0)
                                                parts.push(lastTool);
                                            return parts.filter(part => part.length > 0).join("  ·  ");
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    // Disabled together when the child stops taking
                                    // steer; interrupt stays live.
                                    MaterialTextField {
                                        id: steerField
                                        Layout.fillWidth: true
                                        enabled: subRow.canSteer
                                        opacity: enabled ? 1 : 0.4
                                        placeholderText: Translation.tr("Steer…")
                                        text: root.steerDraftFor(subRow.subId)
                                        onTextChanged: root.setSteerDraft(subRow.subId, text)
                                        onAccepted: root.sendSteer(subRow.subId)
                                    }

                                    CardIconButton {
                                        symbol: "send"
                                        tooltip: Translation.tr("Steer this child")
                                        enabled: subRow.canSteer && steerField.text.trim().length > 0
                                        onReleased: root.sendSteer(subRow.subId)
                                    }

                                    CardIconButton {
                                        symbol: "stop_circle"
                                        tooltip: Translation.tr("Interrupt")
                                        onReleased: HermesService.interruptSubagent(subRow.subId)
                                    }

                                    CardIconButton {
                                        symbol: "terminal"
                                        tooltip: subRow.tailOpen ? Translation.tr("Hide output") : Translation.tr("Show output")
                                        iconColor: subRow.tailOpen ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                        onReleased: root.setTailExpanded(subRow.subId, !subRow.tailOpen)
                                    }
                                }

                                Revealer {
                                    Layout.fillWidth: true
                                    vertical: true
                                    reveal: subRow.tailOpen

                                    Rectangle {
                                        width: subColumn.width
                                        implicitHeight: tailText.implicitHeight + 8 * 2
                                        radius: Appearance.rounding.verysmall
                                        color: Appearance.colors.colLayer3

                                        TextEdit {
                                            id: tailText
                                            anchors {
                                                left: parent.left
                                                right: parent.right
                                                top: parent.top
                                                margins: 8
                                            }
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: Text.Wrap
                                            textFormat: TextEdit.PlainText
                                            renderType: Text.NativeRendering
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnLayer3
                                            text: {
                                                const body = root.tailText[subRow.subId] ?? "";
                                                if (body.length > 0)
                                                    return body;
                                                return root.tailAvailable[subRow.subId] === false ? Translation.tr("Nothing to show yet.") : "";
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.NoButton
                                                hoverEnabled: true
                                                cursorShape: Qt.IBeamCursor
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

        // Rows dissolve into the panel at both ends instead of being sliced off
        // by the clip, which is what makes a scrolling list read as scrollable.
        ScrollEdgeFade {
            z: 1
            target: listView
            color: Appearance.colors.colLayer1Base
            fadeSize: 28
        }
    }

    Item { // PagePlaceholder anchors itself, so it needs a plain parent
        anchors.fill: parent
        visible: root.rows.length === 0

        PagePlaceholder {
            shown: root.rows.length === 0
            icon: "device_hub"
            title: Translation.tr("Nothing running")
            description: Translation.tr("Background turns, side questions and delegated agents show up here, and their runs stay afterwards.")
            descriptionHorizontalAlignment: Text.AlignHCenter
        }
    }

    /** A section's label, with whatever acts on the whole section at its end. */
    component SectionHeader: Item {
        required property var modelData
        property alias text: label.text
        default property alias actions: headerRow.data

        width: listView.width
        implicitHeight: headerRow.implicitHeight + 8

        RowLayout {
            id: headerRow
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            spacing: 8

            StyledText {
                id: label
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }
        }
    }

    /** HermesIconButton on a layer 2 card: that card's hover and ripple. */
    component CardIconButton: HermesIconButton {
        iconColor: Appearance.colors.colOnLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
    }
}
