pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // One hyprctl query. Asked again while running, it runs once more when done, so the
    // answer is never older than the last event; running = true on a running Process was
    // a no-op, and an event landing mid-query left the stale reply standing. A reply
    // identical to the last one is dropped, so a title change elsewhere does not re-run
    // every binding on the window list, and one cut short (a reload) keeps the old data.
    component Query: Process {
        id: query
        property bool again: false
        property string last: ""
        signal reply(var data)

        // Hyprland sends most events twice (activewindow and activewindowv2, ...), back to
        // back: one run answers both.
        function refresh() {
            Qt.callLater(query.start);
        }

        function start() {
            if (query.running)
                query.again = true;
            else
                query.running = true;
        }

        stdout: StdioCollector {
            id: out
            onStreamFinished: {
                if (out.text === query.last)
                    return;
                let data;
                try {
                    data = JSON.parse(out.text);
                } catch (e) {
                    return;
                }
                query.last = out.text;
                query.reply(data);
            }
        }
        onRunningChanged: {
            if (query.running || !query.again)
                return;
            query.again = false;
            query.refresh();
        }
    }

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    // Internals

    function updateWindowList() {
        getClients.refresh();
    }

    function updateLayers() {
        getLayers.refresh();
    }

    function updateMonitors() {
        getMonitors.refresh();
    }

    function updateWorkspaces() {
        getWorkspaces.refresh();
        getActiveWorkspace.refresh();
    }

    function updateAll() {
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        updateAll();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            // "custom" is FloatingMode's watcher, up to once a frame: nothing here changes with it.
            if (["openlayer", "closelayer", "screencast", "custom"].includes(event.name)) return;
            // A title changes the window list and nothing anyone here reads - and it is the
            // event that streams: a terminal or a tab retitling itself.
            if (event.name === "windowtitle" || event.name === "windowtitlev2") {
                root.updateWindowList();
                return;
            }
            root.updateAll();
        }
    }

    Query {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        onReply: data => {
            root.windowList = data
            let tempWinByAddress = {};
            for (var i = 0; i < root.windowList.length; ++i) {
                var win = root.windowList[i];
                tempWinByAddress[win.address] = win;
            }
            root.windowByAddress = tempWinByAddress;
            root.addresses = root.windowList.map(win => win.address);
        }
    }

    Query {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        onReply: data => {
            root.monitors = data;
        }
    }

    Query {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        onReply: data => {
            root.layers = data;
        }
    }

    Query {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        onReply: data => {
            var rawWorkspaces = data;
            // Filter out invalid workspace ids (e.g. lock-screen temp workspace 2147483647 - N)
            root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
            let tempWorkspaceById = {};
            for (var i = 0; i < root.workspaces.length; ++i) {
                var ws = root.workspaces[i];
                tempWorkspaceById[ws.id] = ws;
            }
            root.workspaceById = tempWorkspaceById;
            root.workspaceIds = root.workspaces.map(ws => ws.id);
        }
    }

    Query {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        onReply: data => {
            root.activeWorkspace = data;
        }
    }
}
