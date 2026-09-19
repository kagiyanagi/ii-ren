pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Side work: background turns, `btw` questions, and the current turn's
 * delegated children -- everything running off to the side of the main
 * conversation rather than in it.
 */
Rectangle {
    id: root

    signal requestClose

    // Opaque, for the same reason as HermesHistoryPanel: colLayer1 carries the
    // alpha the shell composites over layer 0 with, colLayer1Base is the solid
    // surface a panel actually needs.
    readonly property color panelColor: Appearance.colors.colLayer1Base

    // Set when this is hosted inside a tab that already draws the surface and
    // the header; the panel then contributes only its list.
    property bool embedded: false

    color: root.embedded ? "transparent" : root.panelColor
    radius: root.embedded ? 0 : Appearance.rounding.normal

    readonly property var sideTasks: HermesService.sideTasks ?? []
    readonly property var subagents: HermesService.subagents ?? []
    readonly property var processes: HermesService.agentProcesses ?? []
    readonly property bool hasFinishedSideTasks: root.sideTasks.some(task => task.done)

    // Per-child UI state, keyed by subagent_id rather than held on the row
    // delegate itself: subagent.list hands back a brand new array on every
    // poll, which is a wholesale model reset for a ListView bound to a plain
    // JS array -- every delegate is destroyed and recreated. Keying state on
    // root is what lets a half-typed steer or an open tail survive that.
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

    function elapsedSeconds(secs: real): string {
        const whole = Math.max(0, Math.round(secs));
        if (whole < 60)
            return Translation.tr("%1s").arg(whole);
        if (whole < 3600)
            return Translation.tr("%1m %2s").arg(Math.floor(whole / 60)).arg(whole % 60);
        return Translation.tr("%1h %2m").arg(Math.floor(whole / 3600)).arg(Math.floor((whole % 3600) / 60));
    }

    function elapsed(startedAt: real): string {
        const secs = Math.max(0, Math.round((root.nowMs - startedAt) / 1000));
        if (secs < 60)
            return Translation.tr("%1s").arg(secs);
        return Translation.tr("%1m %2s").arg(Math.floor(secs / 60)).arg(secs % 60);
    }

    /** Flat list of section headers and rows, so one ListView renders both kinds. */
    readonly property var rows: {
        let out = [];
        if (root.sideTasks.length > 0) {
            out.push({
                "kind": "tasksHeader"
            });
            root.sideTasks.forEach(task => out.push({
                "kind": "task",
                "task": task
            }));
        }
        if (root.subagents.length > 0) {
            out.push({
                "kind": "subagentsHeader"
            });
            root.subagents.forEach(subagent => out.push({
                "kind": "subagent",
                "subagent": subagent
            }));
        }
        if (root.processes.length > 0) {
            out.push({
                "kind": "processesHeader"
            });
            root.processes.forEach(process => out.push({
                "kind": "process",
                "process": process
            }));
        }
        return out;
    }

    // One shared timer for every open tail, rather than one per row: a row's
    // own Timer would be destroyed and restarted on every subagent.list
    // refresh along with the rest of the delegate.
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

    // Covers both ways this panel might come alive: freshly instantiated by a
    // Loader, or kept around and just toggled visible.
    function refreshAll(): void {
        HermesService.refreshDelegation();
        HermesService.refreshAgentProcesses();
    }

    Component.onCompleted: root.refreshAll()
    onVisibleChanged: {
        if (root.visible)
            root.refreshAll();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.embedded ? 0 : 12
        spacing: 8

        RowLayout { // Header
            Layout.fillWidth: true
            spacing: 8
            visible: !root.embedded

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Live work")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer1
            }

            PanelIconButton {
                symbol: "close"
                tooltip: Translation.tr("Close side work")
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
                spacing: 8
                model: root.rows

                delegate: Item {
                    id: rowItem
                    required property var modelData
                    width: listView.width
                    implicitHeight: loader.item?.implicitHeight ?? 0

                    Loader {
                        id: loader
                        width: rowItem.width
                        sourceComponent: {
                            switch (rowItem.modelData.kind) {
                            case "tasksHeader":
                                return tasksHeaderComponent;
                            case "task":
                                return taskCardComponent;
                            case "subagentsHeader":
                                return subagentsHeaderComponent;
                            case "processesHeader":
                                return processesHeaderComponent;
                            case "process":
                                return processRowComponent;
                            case "subagent":
                                return subagentRowComponent;
                            default:
                                return null;
                            }
                        }

                        Component {
                            id: tasksHeaderComponent
                            Item {
                                implicitHeight: tasksHeaderRow.implicitHeight + 8

                                RowLayout {
                                    id: tasksHeaderRow
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                    }
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Background & side work")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                    }

                                    PanelIconButton {
                                        visible: root.hasFinishedSideTasks
                                        symbol: "clear_all"
                                        tooltip: Translation.tr("Clear finished")
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        onReleased: HermesService.clearFinishedSideTasks()
                                    }
                                }
                            }
                        }

                        Component {
                            id: taskCardComponent
                            Rectangle {
                                id: taskCard
                                // rowItem is the delegate root one level up -- Component
                                // blocks stay inside its scope, same as HermesHistoryPanel's
                                // cardComponent reading row.modelData.session directly.
                                readonly property var task: rowItem.modelData.task
                                readonly property bool failed: taskCard.task.failed ?? false

                                width: rowItem.width
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

                                        PanelIconButton {
                                            symbol: "close"
                                            tooltip: Translation.tr("Dismiss")
                                            implicitWidth: 28
                                            implicitHeight: 28
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

                        Component {
                            id: subagentsHeaderComponent
                            Item {
                                implicitHeight: subagentsHeaderRow.implicitHeight + 8

                                RowLayout {
                                    id: subagentsHeaderRow
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                    }
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Delegated children")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                    }

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
                        }

                        Component {
                            id: processesHeaderComponent
                            Item {
                                implicitHeight: processesHeaderRow.implicitHeight + 8

                                RowLayout {
                                    id: processesHeaderRow
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                    }
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Background processes")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }

                        Component {
                            id: processRowComponent
                            Rectangle {
                                id: processCard
                                readonly property var process: rowItem.modelData.process

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

                        Component {
                            id: subagentRowComponent
                            Rectangle {
                                id: subCard
                                // See taskCard above: rowItem is reached through normal id
                                // scoping, not an injected delegate role.
                                readonly property var subagent: rowItem.modelData.subagent
                                readonly property string subId: subCard.subagent.subagent_id ?? ""
                                readonly property bool tailOpen: root.isTailExpanded(subCard.subId)
                                readonly property bool canSteer: subCard.subagent.accepting_steer === true
                                // Indent by nesting depth instead of Layout.leftMargin: this
                                // Rectangle sits in a Loader inside a ListView delegate, not
                                // inside a Layout, so a Layout attached property would be
                                // silently ignored.
                                readonly property real indent: Math.min((subCard.subagent.depth ?? 0) * 16, 64)

                                x: subCard.indent
                                width: rowItem.width - subCard.indent
                                implicitHeight: subColumn.implicitHeight + 8 * 2
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2

                                // Growing to show the tail is a size change: spatial spec,
                                // may overshoot (DESIGN.md 2.3).
                                Behavior on implicitHeight {
                                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                                }

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
                                        text: subCard.subagent.goal ?? ""
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        StyledText {
                                            text: subCard.subagent.status ?? ""
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
                                                const model = subCard.subagent.model ?? "";
                                                const tools = Translation.tr("%1 tools").arg(subCard.subagent.tool_count ?? 0);
                                                const lastTool = subCard.subagent.last_tool ?? "";
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

                                        MaterialTextField {
                                            id: steerField
                                            Layout.fillWidth: true
                                            enabled: subCard.canSteer
                                            placeholderText: Translation.tr("Steer…")
                                            text: root.steerDraftFor(subCard.subId)
                                            onTextChanged: root.setSteerDraft(subCard.subId, text)
                                            onAccepted: root.sendSteer(subCard.subId)
                                        }

                                        PanelIconButton {
                                            symbol: "send"
                                            tooltip: Translation.tr("Steer this child")
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            enabled: subCard.canSteer && steerField.text.trim().length > 0
                                            onReleased: root.sendSteer(subCard.subId)
                                        }

                                        PanelIconButton {
                                            symbol: "stop_circle"
                                            tooltip: Translation.tr("Interrupt")
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            onReleased: HermesService.interruptSubagent(subCard.subId)
                                        }

                                        PanelIconButton {
                                            symbol: "terminal"
                                            tooltip: subCard.tailOpen ? Translation.tr("Hide output") : Translation.tr("Show output")
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            iconColor: subCard.tailOpen ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                            onReleased: root.setTailExpanded(subCard.subId, !subCard.tailOpen)
                                        }
                                    }

                                    Revealer {
                                        Layout.fillWidth: true
                                        vertical: true
                                        reveal: subCard.tailOpen

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
                                                    const body = root.tailText[subCard.subId] ?? "";
                                                    if (body.length > 0)
                                                        return body;
                                                    return root.tailAvailable[subCard.subId] === false ? Translation.tr("Nothing to show yet.") : "";
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
                color: root.panelColor
                fadeSize: 28
            }
        }

        Item { // PagePlaceholder anchors itself, so it needs a plain parent in a layout
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.rows.length === 0

            PagePlaceholder {
                shown: root.rows.length === 0
                icon: "device_hub"
                title: Translation.tr("Nothing running")
                description: Translation.tr("Background turns, side questions and delegated agents show up here.")
            }
        }
    }

    /** Small square icon button, used for header and per-row actions. */
    component PanelIconButton: RippleButton {
        id: iconButton
        required property string symbol
        property string tooltip: ""
        property color iconColor: Appearance.m3colors.m3onSurface

        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: iconButton.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: iconButton.iconColor
        }

        StyledToolTip {
            text: iconButton.tooltip
            extraVisibleCondition: iconButton.tooltip.length > 0
        }
    }
}
