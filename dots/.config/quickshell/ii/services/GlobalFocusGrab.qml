pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars
 */ 
Singleton {
    id: root

    signal dismissed()

    property list<var> persistent: []
    property list<var> dismissable: []

    function dismiss() {
        root.dismissable = [];
        root.dismissed();
    }

    Component.onCompleted: {
        console.log("[GlobalFocusGrab] Initialized");
    }

    function _addTo(list, window) {
        if (list.indexOf(window) === -1) list.push(window);
    }

    function _removeFrom(list, window) {
        const index = list.indexOf(window);
        if (index !== -1) list.splice(index, 1);
    }

    function addPersistent(window) { root._addTo(root.persistent, window) }
    function removePersistent(window) { root._removeFrom(root.persistent, window) }
    function addDismissable(window) { root._addTo(root.dismissable, window) }
    function removeDismissable(window) { root._removeFrom(root.dismissable, window) }

    function hasActive(element) {
        return element?.activeFocus || Array.from(
            element?.children
        ).some(
            (child) => hasActive(child)
        );
    }

    HyprlandFocusGrab {
        id: grab
        windows: root.dismissable.every(w => !w?.focusable) || root.dismissable.some(w => hasActive(w?.contentItem)) ? [...root.dismissable, ...root.persistent] : [...root.dismissable]
        active: root.dismissable.length > 0
        onCleared: () => {
            root.dismiss();
        }
    }

}
