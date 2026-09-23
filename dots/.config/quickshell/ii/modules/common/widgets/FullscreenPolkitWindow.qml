pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property Component contentComponent

    // Content with an exit sets this and calls `release()` once it has left. The
    // flow is deleted on the frame it completes, so a Loader bound to
    // `PolkitService.active` unmapped the surface on that frame and no success or
    // cancel ever animated. Content without an exit is let go on the same edge.
    property bool holdForExit: false

    // Set on the edge, never bound: `active` must not read `PolkitService.active`,
    // not even as one half of an `||`, or the binding and the handler below race on
    // one change signal (OnScreenKeyboard.qml's `rendered` measured that race).
    property bool rendered: false

    function release() {
        if (!PolkitService.active)
            root.rendered = false;
    }

    Component.onCompleted: root.rendered = PolkitService.active

    Connections {
        target: PolkitService
        function onActiveChanged() {
            if (PolkitService.active || !root.holdForExit)
                root.rendered = PolkitService.active;
        }
    }

    Loader {
        active: root.rendered
        sourceComponent: Variants {
            model: Quickshell.screens
            delegate: PanelWindow {
                id: panelWindow
                required property var modelData
                screen: modelData

                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                color: "transparent"
                WlrLayershell.namespace: "quickshell:polkit"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                WlrLayershell.layer: WlrLayer.Overlay
                exclusionMode: ExclusionMode.Ignore

                Loader {
                    anchors.fill: parent
                    sourceComponent: root.contentComponent
                }
            }
        }
    }
}
