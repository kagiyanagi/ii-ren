import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property Component regionComponent: Component {
        Region {}
    }
    
    Loader {
        id: overlayLoader
        // Mapping, never intent. `active` must not read `GlobalStates.overlayOpen`, not
        // even as one half of an `||`: that binding and the animation that starts the
        // exit hang off the same change signal in an undefined order, the binding wins,
        // and the surface is gone before anything can play (`ii-onScreenKeyboard`,
        // `ii-mediaControls`, `ii-osd`). `OverlayContext.rendered` is cleared by the exit
        // reaching 0 and by nothing else.
        active: OverlayContext.rendered || OverlayContext.hasPinnedWidgets
        sourceComponent: PanelWindow {
            id: overlayWindow
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            // Use OnDemand for pinned widgets to allow focus switching with mouse clicks
            WlrLayershell.keyboardFocus: GlobalStates.overlayOpen ? WlrKeyboardFocus.Exclusive : (OverlayContext.clickableWidgets.length > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
            visible: true
            color: "transparent"

            // `overlayContent` carries no transform of its own -- the zoom lives on a
            // child of it. A Region computes its input region from the item's rect *with
            // the transform applied* and refreshes it only on a geometry change, so an
            // item that rests at a scale bakes that scale in for good, with nothing on
            // screen to show for it (`tools/check-mask-regions.py`).
            mask: Region {
                item: GlobalStates.overlayOpen ? overlayContent : null
                regions: OverlayContext.clickableWidgets.map((widget) => regionComponent.createObject(this, {
                    item: widget
                }));
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            HyprlandFocusGrab {
                id: grab
                windows: [overlayWindow]
                active: false
                onCleared: () => {
                    if (!active) GlobalStates.overlayOpen = false;
                }
            }

            Connections {
                target: GlobalStates
                function onOverlayOpenChanged() {
                    delayedGrabTimer.restart();
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Appearance.animation.elementMoveFast.duration
                onTriggered: {
                    grab.active = GlobalStates.overlayOpen;
                }
            }

            OverlayContent {
                id: overlayContent
                anchors.fill: parent
            }
        }
    }

    IpcHandler {
        target: "overlay"

        function toggle(): void {
            GlobalStates.overlayOpen = !GlobalStates.overlayOpen;
        }

        function assist(): void {
            OverlayContext.summon("assist");
        }
    }

    GlobalShortcut {
        name: "overlayToggle"
        description: "Toggles overlay on press"

        onPressed: {
            GlobalStates.overlayOpen = !GlobalStates.overlayOpen;
        }
    }

    GlobalShortcut {
        name: "assistToggle"
        description: "Opens the overlay on the assistant, ready to type"

        onPressed: {
            if (GlobalStates.overlayOpen) GlobalStates.overlayOpen = false;
            else OverlayContext.summon("assist");
        }
    }
}
