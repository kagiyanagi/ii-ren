import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    // Declares no `screen` of its own: PanelWindow already has one, and a
    // redeclaration took `screen: modelData` for itself, so every monitor's
    // corners mapped on whichever monitor was focused.
    component CornerPanelWindow: PanelWindow {
        id: cornerPanelWindow
        property bool fullscreen
        property var corner

        readonly property bool rounded: Appearance.rounding.screenRounding > 0
            && (Config.options.appearance.fakeScreenRounding === 1
                || (Config.options.appearance.fakeScreenRounding === 2 && !fullscreen))
        readonly property bool hotCorner: Config.options.sidebar.cornerOpen.enable && !fullscreen
            && Config.options.sidebar.cornerOpen.bottom == cornerWidget.isBottom

        readonly property bool sidebarOpen: cornerWidget.isLeft ? GlobalStates.sidebarLeftOpen : GlobalStates.sidebarRightOpen
        function setSidebarOpen(open: bool) {
            if (cornerWidget.isLeft)
                GlobalStates.sidebarLeftOpen = open;
            else
                GlobalStates.sidebarRightOpen = open;
        }

        // Closing a sidebar ends its focus grab, and a pointer resting here comes
        // back as a fresh hover. That is not an arrival: without the guard, closing
        // the sidebar from the keyboard reopened it on the spot. Joining the grab
        // does not help -- the grab changing re-sends the enter either way.
        onSidebarOpenChanged: {
            if (!sidebarOpen)
                reentryGuard.restart();
        }
        Timer {
            id: reentryGuard
            // The window in which Qt already treats two presses as one gesture.
            interval: Qt.styleHints.mouseDoubleClickInterval
        }

        // The hot corner lives in this window too, so it must not wait for the
        // rounding: with rounding off or wrapped it used to have no surface at all.
        visible: rounded || hotCorner
        exclusionMode: ExclusionMode.Ignore
        mask: Region {
            item: hotCornerLoader.active ? hotCornerLoader : null
        }
        WlrLayershell.namespace: "quickshell:screenCorners"
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"

        anchors {
            top: cornerWidget.isTop
            left: cornerWidget.isLeft
            bottom: cornerWidget.isBottom
            right: cornerWidget.isRight
        }
        margins {
            right: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * -1
            bottom: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * -1
        }

        implicitWidth: Math.max(cornerWidget.implicitWidth, hotCornerLoader.implicitWidth)
        implicitHeight: Math.max(cornerWidget.implicitHeight, hotCornerLoader.implicitHeight)

        RoundCorner {
            id: cornerWidget
            anchors.fill: parent
            visible: cornerPanelWindow.rounded
            corner: cornerPanelWindow.corner
            rightVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * 1
            bottomVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * 1

            implicitSize: Appearance.rounding.screenRounding
            // The void outside the rounded screen, so M3's scrim rather than a
            // widget default nobody else wants.
            color: Appearance.m3colors.m3scrim
        }

        // A sibling of the corner, not its child, so hiding the rounding cannot
        // hide the hot corner with it.
        Loader {
            id: hotCornerLoader
            active: cornerPanelWindow.hotCorner
            anchors {
                top: cornerWidget.isTop ? parent.top : undefined
                bottom: cornerWidget.isBottom ? parent.bottom : undefined
                left: cornerWidget.isLeft ? parent.left : undefined
                right: cornerWidget.isRight ? parent.right : undefined
            }

            sourceComponent: FocusedScrollMouseArea {
                implicitWidth: Config.options.sidebar.cornerOpen.cornerRegionWidth
                implicitHeight: Config.options.sidebar.cornerOpen.cornerRegionHeight
                hoverEnabled: true

                // Against the screen's side edge, clear of the corner by the vertical
                // offset. A binding, so it fires once on arrival rather than on every
                // motion event while the pointer stays there. Hovering only ever
                // opens; the click is the toggle.
                readonly property bool atEnd: {
                    if (!containsMouse || Config.options.sidebar.cornerOpen.clickless || !Config.options.sidebar.cornerOpen.clicklessCornerEnd)
                        return false;
                    const verticalOffset = Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset;
                    const correctX = (cornerWidget.isRight && mouseX >= width - 2) || (cornerWidget.isLeft && mouseX <= 2);
                    const correctY = (cornerWidget.isTop && mouseY > verticalOffset || cornerWidget.isBottom && mouseY < height - verticalOffset);
                    return correctX && correctY;
                }
                onAtEndChanged: {
                    if (atEnd && !reentryGuard.running)
                        cornerPanelWindow.setSidebarOpen(true);
                }
                onEntered: {
                    if (Config.options.sidebar.cornerOpen.clickless && !reentryGuard.running)
                        cornerPanelWindow.setSidebarOpen(true);
                }
                onPressed: {
                    cornerPanelWindow.setSidebarOpen(!cornerPanelWindow.sidebarOpen);
                }
                onScrollDown: {
                    if (!Config.options.sidebar.cornerOpen.valueScroll)
                        return;
                    if (cornerWidget.isLeft)
                        Brightness.decreaseBrightness()
                    else {
                        Audio.decrementVolume();
                    }
                }
                onScrollUp: {
                    if (!Config.options.sidebar.cornerOpen.valueScroll)
                        return;
                    if (cornerWidget.isLeft)
                        Brightness.increaseBrightness()
                    else {
                        Audio.incrementVolume();
                    }
                }
                onMovedAway: {
                    if (!Config.options.sidebar.cornerOpen.valueScroll)
                        return;
                    if (cornerWidget.isLeft)
                        GlobalStates.osdBrightnessOpen = false;
                    else
                        GlobalStates.osdVolumeOpen = false;
                }

                Loader {
                    active: Config.options.sidebar.cornerOpen.visualize
                    anchors.fill: parent
                    sourceComponent: Rectangle {
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: monitorScope
            required property var modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

            // Hide when fullscreen. Same per-monitor check as the dock.
            readonly property bool fullscreen: Hyprland.workspaces.values.some(ws =>
                ws.active && ws.monitor?.name === monitorScope.monitor?.name
                && ws.toplevels.values.some(toplevel => toplevel.wayland?.fullscreen))

            CornerPanelWindow {
                screen: monitorScope.modelData
                corner: RoundCorner.CornerEnum.TopLeft
                fullscreen: monitorScope.fullscreen
            }
            CornerPanelWindow {
                screen: monitorScope.modelData
                corner: RoundCorner.CornerEnum.TopRight
                fullscreen: monitorScope.fullscreen
            }
            CornerPanelWindow {
                screen: monitorScope.modelData
                corner: RoundCorner.CornerEnum.BottomLeft
                fullscreen: monitorScope.fullscreen
            }
            CornerPanelWindow {
                screen: monitorScope.modelData
                corner: RoundCorner.CornerEnum.BottomRight
                fullscreen: monitorScope.fullscreen
            }
        }
    }
}
