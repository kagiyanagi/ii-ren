pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Scope {
    id: wrappedFrame

    readonly property bool active: Config.options.appearance.fakeScreenRounding === 3
    readonly property int frameThickness: Config.options.appearance.wrappedFrameThickness
    readonly property bool barVertical: Config.options.bar.vertical
    readonly property bool barBottom: Config.options.bar.bottom

    readonly property bool barAtTop: !barVertical && !barBottom
    readonly property bool barAtBottom: !barVertical && barBottom
    readonly property bool barAtLeft: barVertical && !barBottom
    readonly property bool barAtRight: barVertical && barBottom

    // A frame strip pinned to one screen edge, stretched along the other axis.
    component EdgeFrame: PanelWindow {
        id: edgeFrameWindow
        required property string edge // "top" | "bottom" | "left" | "right"
        property bool showBackground: true
        readonly property bool horizontal: edge === "top" || edge === "bottom"

        WlrLayershell.namespace: "quickshell:wrappedFrame"
        WlrLayershell.layer: WlrLayer.Overlay
        mask: Region {}

        color: edgeFrameWindow.showBackground ? Appearance.colors.colLayer0 : "transparent"
        implicitWidth: wrappedFrame.frameThickness
        implicitHeight: wrappedFrame.frameThickness

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        anchors {
            left: edgeFrameWindow.horizontal || edgeFrameWindow.edge === "left"
            right: edgeFrameWindow.horizontal || edgeFrameWindow.edge === "right"
            top: !edgeFrameWindow.horizontal || edgeFrameWindow.edge === "top"
            bottom: !edgeFrameWindow.horizontal || edgeFrameWindow.edge === "bottom"
        }

        margins {
            right: (Config.options.interactions.deadPixelWorkaround.enable && edgeFrameWindow.anchors.right) * -1
            bottom: (Config.options.interactions.deadPixelWorkaround.enable && edgeFrameWindow.anchors.bottom) * -1
        }
    }

    // A concave corner fillet matching the frame color to curve the screen corners.
    component ScreenCorner: PanelWindow {
        id: screenCornerWindow
        required property var corner // RoundCorner.CornerEnum
        property bool showBackground: true

        readonly property bool isLeft: corner === RoundCorner.CornerEnum.TopLeft || corner === RoundCorner.CornerEnum.BottomLeft
        readonly property bool isBottom: corner === RoundCorner.CornerEnum.BottomLeft || corner === RoundCorner.CornerEnum.BottomRight

        WlrLayershell.namespace: "quickshell:wrappedFrame"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}

        color: "transparent"
        implicitWidth: Appearance.rounding.screenRounding
        implicitHeight: Appearance.rounding.screenRounding

        anchors {
            left: screenCornerWindow.isLeft
            right: !screenCornerWindow.isLeft
            top: !screenCornerWindow.isBottom
            bottom: screenCornerWindow.isBottom
        }

        margins {
            right: (Config.options.interactions.deadPixelWorkaround.enable && screenCornerWindow.anchors.right) * -1
            bottom: (Config.options.interactions.deadPixelWorkaround.enable && screenCornerWindow.anchors.bottom) * -1
        }

        RoundCorner {
            id: cornerShape
            anchors.fill: parent
            corner: screenCornerWindow.corner
            rightVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && screenCornerWindow.anchors.right) * 1
            bottomVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && screenCornerWindow.anchors.bottom) * 1
            implicitSize: Appearance.rounding.screenRounding
            color: screenCornerWindow.showBackground ? Appearance.colors.colLayer0 : "transparent"

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    Variants {
        model: wrappedFrame.active ? Quickshell.screens : []

        Scope {
            id: monitorScope
            required property ShellScreen modelData

            property bool hasActiveWindows: false
            readonly property bool showBarBackground: (monitorScope.hasActiveWindows && Config.options.bar.barBackgroundStyle === 2)
                || Config.options.bar.barBackgroundStyle === 1

            function updateActiveWindows() {
                if (Config.options.bar.barBackgroundStyle !== 2) return;
                const monitor = HyprlandData.monitors.find(m => m.name === monitorScope.modelData.name);
                const wsId = monitor?.activeWorkspace?.id;
                monitorScope.hasActiveWindows = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;
            }

            Component.onCompleted: updateActiveWindows()

            Connections {
                enabled: Config.options.bar.barBackgroundStyle === 2
                target: HyprlandData
                function onWindowListChanged() {
                    monitorScope.updateActiveWindows();
                }
                function onMonitorsChanged() {
                    monitorScope.updateActiveWindows();
                }
            }

            Connections {
                target: Config.options.bar
                function onBarBackgroundStyleChanged() {
                    monitorScope.updateActiveWindows();
                }
            }

            // SCREEN CORNERS
            Loader {
                active: !(wrappedFrame.barAtTop || wrappedFrame.barAtLeft)
                sourceComponent: ScreenCorner {
                    corner: RoundCorner.CornerEnum.TopLeft
                    screen: monitorScope.modelData
                    showBackground: monitorScope.showBarBackground
                }
            }
            Loader {
                active: !(wrappedFrame.barAtTop || wrappedFrame.barAtRight)
                sourceComponent: ScreenCorner {
                    corner: RoundCorner.CornerEnum.TopRight
                    screen: monitorScope.modelData
                    showBackground: monitorScope.showBarBackground
                }
            }
            Loader {
                active: !(wrappedFrame.barAtBottom || wrappedFrame.barAtLeft)
                sourceComponent: ScreenCorner {
                    corner: RoundCorner.CornerEnum.BottomLeft
                    screen: monitorScope.modelData
                    showBackground: monitorScope.showBarBackground
                }
            }
            Loader {
                active: !(wrappedFrame.barAtBottom || wrappedFrame.barAtRight)
                sourceComponent: ScreenCorner {
                    corner: RoundCorner.CornerEnum.BottomRight
                    screen: monitorScope.modelData
                    showBackground: monitorScope.showBarBackground
                }
            }

            // FRAMES
            Loader {
                active: !wrappedFrame.barAtBottom
                sourceComponent: EdgeFrame {
                    edge: "bottom"
                    screen: monitorScope.modelData
                    showBackground: monitorScope.showBarBackground
                }
            }
            Loader {
                active: !wrappedFrame.barAtTop
                sourceComponent: EdgeFrame {
                    edge: "top"
                    screen: monitorScope.modelData
                    showBackground: monitorScope.showBarBackground
                }
            }
            Loader {
                active: !wrappedFrame.barAtRight
                sourceComponent: EdgeFrame {
                    edge: "right"
                    screen: monitorScope.modelData
                    showBackground: monitorScope.showBarBackground
                }
            }
            Loader {
                active: !wrappedFrame.barAtLeft
                sourceComponent: EdgeFrame {
                    edge: "left"
                    screen: monitorScope.modelData
                    showBackground: monitorScope.showBarBackground
                }
            }
        }
    }
}
