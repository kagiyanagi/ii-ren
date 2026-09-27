pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

Scope {
    id: root

    property var focusedScreen: Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor?.name ?? "")) ?? Quickshell.screens[0] ?? null
    property string currentIndicator: "volume"
    property bool isStartup: true

    readonly property bool hasFullscreenWindow: {
        const mon = Hyprland.focusedMonitor;
        if (!mon) return false;
        const ws = Hyprland.workspaces.values.find(w => w.monitor && w.monitor.name === mon.name && w.active);
        return ws ? ws.toplevels.values.some(window => window.wayland?.fullscreen) : false;
    }

    property var indicators: [
        {
            id: "volume",
            sourceUrl: Qt.resolvedUrl("VolumeOSD.qml"),
            globalStateValue: "osdVolumeOpen"
        },
        {
            id: "brightness",
            sourceUrl: Qt.resolvedUrl("BrightnessOSD.qml"),
            globalStateValue: "osdBrightnessOpen"
        },
    ]

    function shouldShowIndicator(indicator: string): bool {
        if (GlobalStates.screenLocked)
            return false;
        if (!Config.osdIndicatorEnabled(indicator))
            return false;
        if (Config.ready && Config.options.osd?.hideWhenFullscreen && root.hasFullscreenWindow)
            return false;
        return true;
    }

    function triggerBrightnessOsd() {
        if (!shouldShowIndicator("brightness")) return;
        root.currentIndicator = "brightness";
        GlobalStates.osdBrightnessOpen = true;
        panelLoader.active = true;
        const win = panelLoader.item;
        const ind = win?.indicatorLoader?.item;
        if (ind?.timer) {
            ind.timer.restart();
        }
    }

    function triggerVolumeOSD() {
        if (!shouldShowIndicator("volume")) return;
        root.currentIndicator = "volume";
        GlobalStates.osdVolumeOpen = true;
        panelLoader.active = true;
        const win = panelLoader.item;
        const ind = win?.indicatorLoader?.item;
        if (ind?.timer) {
            ind.timer.restart();
        }
    }

    function trigger(indicator: string) {
        const ind = indicator || root.currentIndicator || "volume";
        if (ind === "brightness") {
            triggerBrightnessOsd();
        } else {
            triggerVolumeOSD();
        }
    }

    function toggle(indicator: string) {
        if (panelLoader.active) {
            root.close();
        } else {
            root.trigger(indicator);
        }
    }

    function close() {
        const win = panelLoader.item;
        const ind = win?.indicatorLoader?.item;
        if (ind && typeof ind.close === "function") {
            ind.close();
        } else {
            root.closeImmediate();
        }
    }

    function closeImmediate() {
        panelLoader.active = false;
        GlobalStates.osdBrightnessOpen = false;
        GlobalStates.osdVolumeOpen = false;
    }

    Component.onCompleted: startupTimer.start()

    Timer {
        id: startupTimer
        interval: 1000
        repeat: false
        onTriggered: {
            root.isStartup = false;
        }
    }

    // Listen to brightness changes
    Connections {
        target: Brightness
        function onBrightnessChanged() {
            if (root.isStartup)
                return;
            root.triggerBrightnessOsd();
        }
    }

    // Listen to volume changes
    Connections {
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready || root.isStartup)
                return;
            root.triggerVolumeOSD();
        }
        function onMutedChanged() {
            if (!Audio.ready || root.isStartup)
                return;
            root.triggerVolumeOSD();
        }
    }

    // Open/close when global state changes
    Connections {
        target: GlobalStates

        function onOsdBrightnessOpenChanged() {
            if (GlobalStates.osdBrightnessOpen)
                root.triggerBrightnessOsd();
        }
        function onOsdVolumeOpenChanged() {
            if (GlobalStates.osdVolumeOpen)
                root.triggerVolumeOSD();
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                root.closeImmediate();
        }
    }

    // The actual thing
    Loader {
        id: panelLoader
        active: false
        onActiveChanged: {
            if (active) return;
            root.indicators.forEach(i => {
                GlobalStates[i.globalStateValue] = false;
            });
        }
        sourceComponent: PanelWindow {
            id: panelWindow
            screen: root.focusedScreen

            property alias indicatorLoader: osdIndicatorLoader

            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wOnScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: !Config.options.waffles.bar.bottom
                bottom: Config.options.waffles.bar.bottom
            }
            mask: Region {
                item: osdIndicatorLoader
            }

            implicitWidth: osdIndicatorLoader.implicitWidth
            implicitHeight: osdIndicatorLoader.implicitHeight

            Loader {
                id: osdIndicatorLoader
                anchors.fill: parent
                source: root.indicators.find(i => i.id === root.currentIndicator)?.sourceUrl

                Connections {
                    target: osdIndicatorLoader.item
                    function onClosed() {
                        panelLoader.active = false;
                        root.indicators.forEach(i => {
                            GlobalStates[i.globalStateValue] = false;
                        });
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osd"

        function trigger(indicator: string) {
            root.trigger(indicator);
        }

        function open(indicator: string) {
            root.trigger(indicator);
        }

        function hide() {
            root.close();
        }

        function close() {
            root.close();
        }

        function toggle(indicator: string) {
            root.toggle(indicator);
        }
    }

    IpcHandler {
        target: "osdVolume"

        function trigger() {
            root.triggerVolumeOSD();
        }

        function hide() {
            root.close();
        }

        function close() {
            root.close();
        }

        function toggle() {
            root.toggle("volume");
        }
    }

    GlobalShortcut {
        name: "osdTrigger"
        description: "Triggers OSD display"

        onPressed: root.trigger()
    }

    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD display"

        onPressed: root.triggerVolumeOSD()
    }
}
