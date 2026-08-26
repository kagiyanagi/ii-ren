pragma Singleton

import qs
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

// A holding pen for dragged files, so a drag can be built up over several trips
// instead of having to be one uninterrupted gesture. Ported from end4-pC.
Singleton {
    id: root

    // Absolute paths, in the order they were dropped.
    property list<string> items: []
    readonly property int maxItems: 30

    // True while a tile is being dragged out. Every mutation below refuses to run
    // during one: destroying the tile that owns an in-flight drag frees mime data
    // the compositor is still reading, which segfaults the shell.
    property bool dragActive: false

    function addItems(urls): void {
        if (root.dragActive)
            return;
        let arr = [...root.items];
        for (const url of urls) {
            const asString = url.toString();
            const path = FileUtils.trimFileProtocol(asString);
            // A remote drag - an image straight off a web page - is not a local
            // file, so there is nothing here to hand back out again.
            if (path === asString)
                continue;
            if (!arr.includes(path) && arr.length < root.maxItems)
                arr.push(path);
        }
        root.items = arr;
    }

    function removeItem(path): void {
        if (root.dragActive)
            return;
        root.items = root.items.filter(item => item !== path);
        if (root.items.length === 0)
            root.hide();
    }

    function show(urls, x, y): void {
        root.addItems(urls);
        GlobalStates.dropShelfX = x;
        GlobalStates.dropShelfY = y;
        GlobalStates.dropShelfOpen = true;
    }

    function copyAll(): void {
        if (root.items.length === 0)
            return;
        copyProc.payload = root.items.map(path => `file://${path}`).join("\n");
        copyProc.running = true;
    }

    function clear(): void {
        if (root.dragActive)
            return;
        root.items = [];
        root.hide();
    }

    function hide(): void {
        if (root.dragActive)
            return;
        GlobalStates.dropShelfOpen = false;
    }

    Process {
        id: copyProc
        property string payload: ""
        // uri-list is what file managers paste from; wl-copy holds the selection
        // itself, so the shell does not have to stay a clipboard owner.
        command: ["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(copyProc.payload)}' | wl-copy --type text/uri-list`]
    }
}
