pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.waffle.looks
import "window-layout.js" as WindowLayout

Rectangle {
    id: root

    color: ColorUtils.transparentize(Looks.colors.bg1Base, 1 - 0.5 * root.openProgress)
    property bool draggingWindow: false
    property real openProgress: 0
    property Item hoveredWorkspace: null
    signal closed

    function open() {
        closeAnim.stop();
        openAnim.start();
    }

    function close() {
        openAnim.stop();
        closeAnim.start();
    }

    Component.onCompleted: {
        root.open();
    }

    PropertyAnimation {
        id: openAnim
        target: root
        property: "openProgress"
        to: 1
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
    }

    SequentialAnimation {
        id: closeAnim

        PropertyAnimation {
            target: root
            property: "openProgress"
            to: 0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Looks.transition.easing.bezierCurve.easeOut
        }
        ScriptAction {
            script: {
                root.closed();
            }
        }
    }

    // Windows
    property real maxWindowHeight: 288
    property real maxWindowWidth: 736
    property real padding: 52
    property real spacing: 24
    readonly property list<var> toplevels: (ToplevelManager.toplevels?.values ?? []).filter(t => {
        const client = HyprlandData.clientForToplevel(t);
        return client && HyprlandData.activeWorkspace && client.workspace?.id === HyprlandData.activeWorkspace.id;
    })
    readonly property list<var> arrangedToplevels: {
        const maxRowWidth = width - padding * 2;
        const count = toplevels.length;
        const resultLayout = [];

        var i = 0;
        while (i < count) {
            var row = [];
            var rowWidth = 0;
            var j = i;

            while (j < count) {
                const toplevel = toplevels[j];
                const client = HyprlandData.clientForToplevel(toplevel);
                const scaledSize = WindowLayout.scaleWindow(client, maxWindowWidth, maxWindowHeight);

                if (rowWidth + scaledSize.width <= maxRowWidth || row.length === 0) {
                    row.push(toplevel);
                    rowWidth += scaledSize.width;
                    j++;
                } else {
                    break;
                }
            }

            resultLayout.push(row);
            i = j;
        }
        return resultLayout;
    }

    MouseArea {
        z: 0
        anchors.fill: parent
        onClicked: {
            GlobalStates.overviewOpen = false;
        }
    }

    // Windows
    WListView {
        id: windowListView
        z: root.openProgress === 1 ? 2 : 1
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: Math.round((root.height - (wsBorder.height + 16) - height) / 2)
        }
        spacing: root.spacing
        topMargin: root.padding
        bottomMargin: root.padding
        leftMargin: root.padding
        rightMargin: root.padding
        height: Math.min(contentHeight + topMargin + bottomMargin, root.height - (wsBorder.height + 16))

        interactive: (height < contentHeight) && !root.draggingWindow
        clip: root.openProgress > 0.99 && !root.draggingWindow

        model: ScriptModel {
            values: root.arrangedToplevels
        }
        delegate: RowLayout {
            id: clientRow
            required property var modelData
            spacing: root.spacing
            anchors.horizontalCenter: parent?.horizontalCenter ?? undefined

            Repeater {
                model: ScriptModel {
                    values: clientRow.modelData
                }
                delegate: Item {
                    id: clientGridArea
                    required property int index
                    required property var modelData
                    implicitWidth: windowItem.openedSize.width
                    implicitHeight: windowItem.openedSize.height + windowItem.titleBarImplicitHeight

                    TaskViewWindow {
                        id: windowItem
                        z: Drag.active ? 2 : 1
                        opacity: root.openProgress

                        property int mappedX: {
                            var rootPosToThis = -(clientRow.x + clientGridArea.x + root.padding);
                            return rootPosToThis + (hyprlandClient?.at?.[0] ?? 0);
                        }
                        property int mappedY: {
                            var rootPosToThis = -(clientRow.y + windowListView.y + root.padding + windowItem.titleBarImplicitHeight);
                            return rootPosToThis + (hyprlandClient?.at?.[1] ?? 0);
                        }
                        property int openedX: 0
                        property int openedY: 0
                        scaleSize: true
                        x: mappedX + (openedX - mappedX) * root.openProgress
                        y: mappedY + (openedY - mappedY) * root.openProgress

                        droppable: root.hoveredWorkspace !== null
                        Drag.active: dragHandler.active
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2

                        DragHandler {
                            id: dragHandler
                            target: null
                            xAxis.onActiveValueChanged: {
                                windowItem.openedX = dragHandler.xAxis.activeValue;
                            }
                            yAxis.onActiveValueChanged: {
                                windowItem.openedY = dragHandler.yAxis.activeValue;
                            }
                            onActiveChanged: {
                                if (active) {
                                    root.draggingWindow = true;
                                } else {
                                    root.draggingWindow = false;
                                    const targetWs = root.hoveredWorkspace;
                                    const client = windowItem.hyprlandClient;
                                    if (targetWs && client && client.address && targetWs.workspace !== client.workspace?.id) {
                                        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${targetWs.workspace}, follow = false, window = "address:${client.address}" })`);
                                    }
                                    windowItem.openedX = 0;
                                    windowItem.openedY = 0;
                                }
                            }
                        }

                        Layout.alignment: Qt.AlignTop
                        maxHeight: root.maxWindowHeight
                        maxWidth: root.maxWindowWidth
                        toplevel: clientGridArea.modelData
                    }
                }
            }
        }
    }

    // Workspaces
    Rectangle {
        id: wsBorder
        z: root.openProgress === 1 ? 1 : 2
        property real sourceEdgeMargin: -(height + 8) + root.openProgress * (height + 16)
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 8
            rightMargin: 8
            bottomMargin: sourceEdgeMargin
        }
        border.color: Looks.colors.bg2Border
        border.width: 1
        radius: Looks.radius.large
        color: Looks.colors.bgPanelFooterBackground
        implicitHeight: 176

        WListView {
            id: workspaceListView
            anchors {
                fill: parent
                topMargin: 4
                bottomMargin: 4
                leftMargin: 4
                rightMargin: 4
            }
            flickableDirection: Flickable.HorizontalFlick
            orientation: ListView.Horizontal
            interactive: width === parent.width
            width: Math.min(contentWidth + leftMargin + rightMargin, parent.width)
            clip: true
            spacing: 4

            function reposition() {
                if (!HyprlandData.activeWorkspace) return;
                positionViewAtIndex(Math.max(0, HyprlandData.activeWorkspace.id - 1), ListView.Contain);
            }

            Connections {
                target: HyprlandData
                function onActiveWorkspaceChanged() {
                    workspaceListView.reposition();
                }
            }
            model: IndexModel {
                id: workspaceIndexModel
                count: {
                    if (!HyprlandData.workspaces || HyprlandData.workspaces.length === 0) return 2;
                    const ids = HyprlandData.workspaces.map(ws => (ws && ws.id) || 1);
                    const maxWorkspaceId = Math.max(...ids);
                    return Math.max(maxWorkspaceId, 1) + 1;
                }
            }
            delegate: TaskViewWorkspace {
                id: workspaceItem
                required property int index
                workspace: index + 1
                newWorkspace: index === workspaceIndexModel.count - 1

                droppable: root.hoveredWorkspace === workspaceItem
                DropArea {
                    anchors.fill: parent
                    onEntered: drag => {
                        root.hoveredWorkspace = workspaceItem;
                    }
                    onExited: {
                        if (root.hoveredWorkspace === workspaceItem) {
                            root.hoveredWorkspace = null;
                        }
                    }
                }

                onClicked: {
                    GlobalStates.overviewOpen = false;
                    Hyprland.dispatch(`hl.dsp.focus({workspace = ${workspaceItem.workspace}})`);
                }
            }
        }
    }
}
