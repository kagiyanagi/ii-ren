import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.ii.overlay
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas

Item {
    id: root
    focus: true
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true

    Keys.onPressed: (event) => { // Esc to close
        if (event.key === Qt.Key_Escape) {
            GlobalStates.overlayOpen = false;
        }
    }

    // A keybind has no origin on screen, so the canvas has nowhere to grow *out of* (5)
    // and settles onto the screen instead. Suppressed the moment anything is pinned: the
    // pinned card lives on this plane and must not drift a pixel when the overlay goes.
    readonly property real initScale: (Config.options.overlay.openingZoomAnimation && !OverlayContext.hasPinnedWidgets) ? 1.08 : 1

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Appearance.colors.colScrim
        visible: Config.options.overlay.darkenScreen && opacity > 0
        opacity: OverlayContext.shownProgress
    }

    Item {
        id: zoomPlane
        anchors.fill: parent
        // Centre, stated rather than defaulted: the surface is summoned by a keybind, so
        // there is no anchor edge and no click corner for it to grow out of (5).
        transformOrigin: Item.Center
        scale: 1 + (root.initScale - 1) * (1 - OverlayContext.openedProgress)

        WidgetCanvas {
            anchors.fill: parent
            onClicked: GlobalStates.overlayOpen = false

            OverlayTaskbar {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    // Clears the bar it is covering, rather than the 50 that happened to
                    // be the same number on the shipped config.
                    topMargin: Appearance.sizes.barHeight + Appearance.sizes.elevationMargin
                }
            }

            Repeater {
                model: ScriptModel {
                    // `.filter`, like its sibling below: an identifier no built-in widget
                    // answers to -- every extension widget, and anything left by an older
                    // config -- put `undefined` into the model, which `objectProp` then
                    // indexed.
                    values: Persistent.states.overlay.open.map(identifier => {
                        return OverlayContext.availableWidgets.find(w => w.identifier === identifier);
                    }).filter(w => w !== undefined)
                    objectProp: "identifier"
                }
                delegate: OverlayWidgetDelegateChooser {}
            }

            Repeater {
                model: ScriptModel {
                    values: Persistent.states.overlay.open.map(identifier => {
                        return OverlayContext.extensionWidgets.find(w => w.identifier === identifier);
                    }).filter(w => w !== undefined)
                    objectProp: "identifier"
                }
                delegate: ExtensionOverlayWidgetLoader {}
            }
        }
    }
}
