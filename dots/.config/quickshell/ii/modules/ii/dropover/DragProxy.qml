import qs.services
import QtQuick

// The single owner of every outgoing shelf drag. It outlives the delegates, so
// destroying one mid-drag cannot free the mime data out from under the
// compositor. Invisible: the cursor image is a grab taken off the tile.
Item {
    id: proxy

    property string path: ""
    property bool dragging: false

    width: 1
    height: 1
    visible: false

    // Drag.Automatic hands the drag to the compositor, which is what lets it land
    // in another application rather than only inside this shell.
    Drag.active: proxy.dragging && proxy.path.length > 0
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.mimeData: ({
        "text/uri-list": `file://${proxy.path}`
    })

    // The shelf must not change shape while a drag is in flight - see the note in
    // DropShelfItem. Tracking Drag.active rather than the request to drag means
    // this clears itself even when the drop swallows the mouse release.
    Binding {
        target: DropShelf
        property: "dragActive"
        value: proxy.Drag.active
    }

    function arm(path, sourceItem): void {
        proxy.path = path;
        // Without a grabbed image the compositor has nothing to render under the
        // cursor, so the drag looks like nothing is happening.
        sourceItem.grabToImage(result => proxy.Drag.imageSource = result.url);
    }

    function disarm(): void {
        proxy.dragging = false;
        proxy.path = "";
        proxy.x = 0;
        proxy.y = 0;
    }
}
