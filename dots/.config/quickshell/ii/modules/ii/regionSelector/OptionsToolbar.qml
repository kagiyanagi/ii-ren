pragma ComponentBehavior: Bound
import qs.modules.common.widgets
import qs.services
import QtQuick

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        // One way in each direction, not a binding: the tab bar writes currentIndex
        // imperatively when a tab is clicked, which both fights a binding on it and
        // clears it. Each side only writes when the other actually disagrees, so
        // neither can bounce the change back.
        readonly property int modeIndex: root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1
        onModeIndexChanged: if (currentIndex !== modeIndex) setCurrentIndex(modeIndex)
        Component.onCompleted: setCurrentIndex(modeIndex)
        onCurrentIndexChanged: {
            const mode = currentIndex === 0 ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle;
            if (root.selectionMode !== mode)
                root.selectionMode = mode;
        }
    }
}
