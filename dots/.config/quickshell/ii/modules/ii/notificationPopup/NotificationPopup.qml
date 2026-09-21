import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    PanelWindow {
        id: root

        // Same outer spacing as the sidebars, the toasts and the bar popups.
        readonly property real gutter: Appearance.sizes.hyprlandGapsOut

        readonly property bool hasPopups: Notifications.popupList.length > 0

        // The surface stays mapped until the last card has finished leaving.
        // `visible` bound straight to the list unmaps it in the same frame the
        // model empties, and NotificationListView's remove transition never
        // draws. One notification at a time is the common case, so that was
        // every notification (2.5).
        //
        // A latch rather than `hasPopups || exitGrace.running`: that binding and
        // the handler that starts the timer are both connections to the same
        // change signal and nothing fixes which runs first, so the surface could
        // unmap for a frame before the grace began (2.9).
        property bool mapped: false
        onHasPopupsChanged: {
            if (!root.hasPopups) {
                exitGrace.restart();
                return;
            }
            exitGrace.stop();
            root.mapped = true;
        }

        Timer {
            id: exitGrace
            interval: Appearance.animation.elementMoveExit.duration
            onTriggered: root.mapped = false
        }

        visible: root.mapped && !GlobalStates.screenLocked

        // A monitor pinned in settings, else the focused one. A pinned monitor
        // that is not connected right now falls back to the focused one rather
        // than to whatever the compositor picks for a null screen.
        screen: {
            const focused = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null;
            const pinned = Config.options.notifications.monitor;
            if (!pinned?.enable)
                return focused;
            return Quickshell.screens.find(s => s.name === pinned.name) ?? focused;
        }

        color: "transparent"

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        // A notification never takes the keyboard off what the user is doing.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Reserve nothing, but do respect what the bar and a pinned dock
        // reserve -- that is what keeps the stack clear of both.
        exclusiveZone: 0

        // Full height on purpose, like the toasts and the pairing card: the
        // stack changes height with every notification, and changing a committed
        // layer surface's margins does not reconfigure it. The window stays put,
        // is made big enough to cover every position the stack can take, and the
        // list moves inside it. The mask keeps the slack click-through.
        anchors {
            top: true
            right: true
            bottom: true
        }

        // The stack's own box, not the full-height list: a Region over the list
        // would swallow every click down the right edge of the screen.
        mask: Region {
            item: popupBounds
        }

        Item {
            id: popupBounds
            x: listview.x
            y: listview.y
            width: listview.width
            height: Math.min(listview.contentHeight, listview.height)
        }

        // Slide inwards so a right sidebar can have the corner.
        readonly property real sidebarInset: GlobalStates.effectiveRightOpen ? Appearance.sizes.sidebarWidth : 0

        // Gutter to the screen edge, elevationMargin of slack on the far side
        // for the card shadows, plus the room the list needs to dodge a sidebar:
        // the same split the toasts and the sidebars use.
        implicitWidth: listview.width + root.gutter + Appearance.sizes.elevationMargin + Appearance.sizes.sidebarWidth

        NotificationListView {
            id: listview
            anchors {
                top: parent.top
                bottom: parent.bottom
                topMargin: root.gutter
            }

            x: root.width - width - root.gutter - root.sidebarInset
            width: Appearance.sizes.notificationPopupWidth - Appearance.sizes.elevationMargin * 2

            // Driven by a toggle and has to reverse mid-flight, so elementMove
            // rather than elementMoveEnter -- the enter spec runs to the end and
            // would queue the whole trip out and back (2.7).
            Behavior on x {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            popup: true
        }

        // Published so panels in the same corner can shift out of the way.
        // Clamped to what actually fits on screen, so a long stack cannot push
        // them off the display, and zero whenever there is no stack: all three
        // readers treat `<= 0` as "nothing there", so publishing the top margin
        // on its own through the exit grace insets them by a gutter for nothing.
        Binding {
            target: GlobalStates
            property: "notificationPopupHeight"
            value: (root.visible && listview.contentHeight > 0) ? listview.y + Math.min(listview.contentHeight, listview.height) : 0
        }
    }
}
