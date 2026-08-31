import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => Config.options.notifications.forceMonitor.enable ? s.name === Config.options.notifications.forceMonitor.name : s.name === Hyprland.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        anchors {
            top: true
            right: true
            bottom: true
        }

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

        color: "transparent"

        // Slide inwards so a right sidebar can have the corner.
        // The window is made wide enough for both positions, and the list moves inside it.
        readonly property real sidebarInset: GlobalStates.effectiveRightOpen ? Appearance.sizes.sidebarWidth : 0
        implicitWidth: Appearance.sizes.notificationPopupWidth + Appearance.sizes.sidebarWidth

        NotificationListView {
            id: listview
            anchors {
                top: parent.top
                bottom: parent.bottom
                topMargin: 4
            }
            
            x: root.width - width - 4 - root.sidebarInset
            width: Appearance.sizes.notificationPopupWidth - Appearance.sizes.elevationMargin * 2
            
            Behavior on x {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
            
            popup: true
        }

        // Published so panels in the same corner can shift out of the way.
        // Clamped to what actually fits on screen, so a long stack cannot push
        // them off the display.
        Binding {
            target: GlobalStates
            property: "notificationPopupHeight"
            value: root.visible ? listview.y + Math.min(listview.contentHeight, listview.height) : 0
        }
    }
}
