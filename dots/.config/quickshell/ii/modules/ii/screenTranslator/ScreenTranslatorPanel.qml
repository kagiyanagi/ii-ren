pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.widgets
import qs.services

PanelWindow {
    id: root

    // Interface
    signal dismiss
    // The request, which ScreenTranslator's Loader owns. Mapping is ours: the
    // window stays up until its fade out has played, then says so. Not
    // `closed`, which QsWindow already declares.
    property bool open: true
    signal fadedOut
    onOpenChanged: {
        // Never shown, or nothing left to fade: done now.
        if (!root.open && (!root.visible || content.opacity === 0))
            root.fadedOut();
    }

    // Window props
    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:screenTranslator"
    WlrLayershell.layer: WlrLayer.Overlay
    // On its way out the window is only something to look at, or the screen
    // under it would be dead for the length of the fade.
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: root.open ? null : passthroughRegion
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    Region { id: passthroughRegion } // Empty: every click goes to whatever is underneath

    // Config
    readonly property string screenshotDir: Directories.screenshotTemp
    readonly property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
    // What the shell reserves along the bottom edge - a pinned dock, a bottom
    // bar - which the frozen frame still shows there.
    readonly property real reservedBottom: HyprlandData.monitors.find(m => m.name === root.screen.name)?.reserved?.[3] ?? 0

    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (_, __) => root.visible = true
    }

    // Pan and zoom. Never below 1 and never off an edge: the frozen frame is
    // the whole screen, so anything else shows the window around it.
    property real zoom: 1
    property real contentX: 0
    property real contentY: 0

    function place(x, y, zoom) {
        root.zoom = zoom;
        root.contentX = Math.min(0, Math.max(root.width * (1 - zoom), x));
        root.contentY = Math.min(0, Math.max(root.height * (1 - zoom), y));
    }

    Item {
        id: content
        anchors.fill: parent

        // In on the scrim's spec (DESIGN.md 6.2), out at the fast effects one,
        // assigned inside the binding that drives the fade (2.9).
        property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
        opacity: {
            content.fadeSpec = root.open ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
            return root.visible && root.open ? 1 : 0;
        }
        Behavior on opacity {
            NumberAnimation {
                duration: content.fadeSpec.duration
                easing.type: content.fadeSpec.type
                easing.bezierCurve: content.fadeSpec.bezierCurve
            }
        }
        // The fade out is what releases the window, not the dismiss.
        onOpacityChanged: if (content.opacity === 0 && !root.open) root.fadedOut()

        MouseArea {
            anchors.fill: parent
            clip: true

            property real lastX: 0
            property real lastY: 0

            cursorShape: root.zoom > 1 ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor

            onPressed: mouse => {
                lastX = mouse.x;
                lastY = mouse.y;
            }

            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                root.place(root.contentX + mouse.x - lastX, root.contentY + mouse.y - lastY, root.zoom);
                lastX = mouse.x;
                lastY = mouse.y;
            }

            // By the delta, not per event: a notch is 120 (QWheelEvent), and a
            // touchpad sends a stream of small ones that went from 1x to 5x in a flick.
            onWheel: event => {
                const zoom = Math.min(Math.max(1, root.zoom * Math.pow(1.1, event.angleDelta.y / 120)), 5);
                // Keep the point under the cursor where it is.
                root.place(event.x - (event.x - root.contentX) * zoom / root.zoom, event.y - (event.y - root.contentY) * zoom / root.zoom, zoom);
            }

            ScreencopyView { // Freeze screen
                id: screencopy
                width: parent.width
                height: parent.height

                x: root.contentX
                y: root.contentY
                scale: root.zoom
                transformOrigin: Item.TopLeft

                live: false
                captureSource: root.screen
            }

            Loader {
                id: overlay
                width: parent.width * root.zoom
                height: parent.height * root.zoom

                x: root.contentX
                y: root.contentY

                active: root.visible
                sourceComponent: ScreenTextOverlay {
                    screenshotPath: root.screenshotPath
                    scaleFactor: root.zoom
                }
            }
        }

        // Chrome, so outside the zoom. Up until the boxes land, and for good
        // when there is nothing to show instead.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colScrim
            opacity: (overlay.item?.loading ?? true) || (overlay.item?.empty ?? false) ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveExit.numberAnimation.createObject(this)
            }

            Toolbar {
                id: status
                readonly property bool working: !(overlay.item?.error ?? false) && !(overlay.item?.empty ?? false)
                anchors.centerIn: parent
                spacing: 8

                MaterialLoadingIndicator {
                    visible: status.working
                    loading: status.working
                    implicitSize: 40
                }
                MaterialShapeWrappedMaterialSymbol {
                    visible: !status.working
                    text: status.working ? "" : overlay.item.error ? "exclamation" : "translate"
                    iconSize: 24
                    color: overlay.item?.error ? Appearance.colors.colError : Appearance.colors.colSecondaryContainer
                    colSymbol: overlay.item?.error ? Appearance.colors.colOnError : Appearance.colors.colOnSecondaryContainer
                    shape: MaterialShape.Shape.Sunny
                }
                StyledText {
                    Layout.rightMargin: 8
                    // The pill is one line tall, so a long error elides rather than
                    // running off both edges. The bound the old error text wrapped at.
                    Layout.maximumWidth: Math.min(root.width / 2, 800)
                    text: overlay.item?.status ?? ""
                    animateChange: true
                    color: Appearance.colors.colOnSurface
                }
            }
        }

        ToolbarPairedFab {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                // Rises from below the screen edge (DESIGN.md 2.6) to sit clear
                // of the band the shell reserves there: the frozen frame still
                // shows the dock in it.
                bottomMargin: root.visible ? root.reservedBottom + 8 : -height
            }
            Behavior on anchors.bottomMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            iconText: "close"
            onClicked: root.dismiss()
            focus: root.visible
            Keys.onPressed: event => { // Esc to close
                if (event.key === Qt.Key_Escape) {
                    root.dismiss();
                }
            }
            StyledToolTip {
                text: Translation.tr("Close")
            }
        }
    }
}
