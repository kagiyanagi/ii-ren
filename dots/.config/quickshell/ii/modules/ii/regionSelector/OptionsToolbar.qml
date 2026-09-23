pragma ComponentBehavior: Bound
import qs.modules.common.widgets
import qs.services
import QtQuick

// Rect or circle. The action is whichever keybind opened the selector.
Toolbar {
    id: root

    property var selectionMode
    // Asked for rather than written: the selection owns its mode. A pair of
    // two-way Synchronizers here logged a binding loop on every open.
    signal selectionModeRequested(var mode)

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        // Told only when the mode disagrees, never bound: the tab bar writes
        // currentIndex imperatively when a tab is clicked, which would clear a
        // binding on it.
        readonly property int modeIndex: root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1
        onModeIndexChanged: if (currentIndex !== modeIndex) setCurrentIndex(modeIndex)
        Component.onCompleted: setCurrentIndex(modeIndex)
        onCurrentIndexChanged: root.selectionModeRequested(currentIndex === 0
            ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle)
    }
}
