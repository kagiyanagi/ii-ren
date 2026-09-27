pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.notificationCenter

Scope {
    id: notificationPopup

    PanelWindow {
        id: root

        readonly property real gutter: 12
        readonly property bool barAtBottom: Config.options.waffles.bar.bottom
        readonly property bool hasPopups: (Notifications.popupList?.length ?? 0) > 0

        // The surface stays mapped until the last card has finished leaving.
        // Direct binding to popupList unmaps the layer surface in the same frame the
        // model empties, cutting off WNotificationDismissAnim / removal transitions.
        // A latch rather than `hasPopups || exitGrace.running` prevents an ordering
        // race between the property change signal and the timer start handler.
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

        // A monitor pinned in settings, else falling back to the focused monitor.
        screen: {
            const focused = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null;
            const pinned = Config.options.notifications.monitor;
            if (!pinned?.enable)
                return focused;
            return Quickshell.screens.find(s => s.name === pinned.name) ?? focused;
        }

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0

        anchors {
            top: true
            right: true
            bottom: true
        }

        mask: Region {
            item: popupBounds
        }

        // Bounded to the active notification stack rather than the full-height window,
        // so slack remains completely click-through. Reports 0 when no popups are shown.
        Item {
            id: popupBounds
            x: listview.x
            y: listview.y
            width: listview.width
            height: (root.hasPopups && listview.count > 0 && listview.contentHeight > 0)
                ? Math.min(listview.contentHeight + listview.topMargin + listview.bottomMargin, root.height)
                : 0
        }

        color: "transparent"
        implicitWidth: listview.implicitWidth

        WListView {
            id: listview
            anchors {
                right: parent.right
                left: parent.left
                bottom: root.barAtBottom ? parent.bottom : undefined
                top: !root.barAtBottom ? parent.top : undefined
            }
            leftMargin: root.gutter
            rightMargin: root.gutter
            topMargin: root.gutter
            bottomMargin: root.gutter

            height: (root.hasPopups && count > 0 && contentHeight > 0)
                ? Math.min(contentHeight + topMargin + bottomMargin, parent.height)
                : 0

            // 360dp card width + 12dp left margin + 12dp right margin = 384dp on 4dp grid
            implicitWidth: 384
            spacing: 12

            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
                }
            }

            model: ScriptModel {
                values: Notifications.popupList ?? []
            }

            delegate: WSingleNotification {
                required property var modelData
                notification: modelData
                width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
            }
        }

        // Published so panels in the same corner (when top-anchored) can shift out of the way.
        // Clamped to what fits on screen, and 0 whenever there is no stack or when notifications
        // are bottom-anchored (so top-right readers do not inset needlessly).
        Binding {
            target: GlobalStates
            property: "notificationPopupHeight"
            value: (root.visible && !root.barAtBottom && listview.count > 0 && listview.contentHeight > 0)
                ? listview.y + Math.min(listview.contentHeight + listview.topMargin + listview.bottomMargin, listview.height)
                : 0
        }
    }
}
