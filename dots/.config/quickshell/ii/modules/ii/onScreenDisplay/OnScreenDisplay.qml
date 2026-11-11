import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property string protectionMessage: ""
    property var focusedScreen: Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")) || Quickshell.screens[0] || null

    property bool isStartup: true
    Timer {
        running: true
        interval: 2000
        onTriggered: root.isStartup = false
    }

    property string currentIndicator: "volume"
    property bool hovered: osdLoader.item?.hovered ?? false
    onHoveredChanged: root.updateTimeout()
    // The player whose volume the playerVolume pill shows. Held rather than read from
    // activePlayer, which can move to another player while the pill is up.
    property MprisPlayer volumePlayer: null
    property var indicators: [
        {
            id: "volume",
            sourceUrl: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            sourceUrl: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "playerVolume",
            sourceUrl: "indicators/PlayerVolumeIndicator.qml"
        },
        {
            id: "gamma",
            sourceUrl: "indicators/GammaIndicator.qml"
        },
        {
            id: "keyboardBrightness",
            sourceUrl: "indicators/KeyboardBrightnessIndicator.qml"
        },
    ]

    // Only a fullscreen window on the screen the OSD opens on hides it -- the same
    // per-monitor check as the dock and the Waffle OSD.
    function fullscreenOnOsdScreen() {
        const name = root.focusedScreen?.name;
        if (!name)
            return false;
        return Hyprland.workspaces.values.some(ws => ws.active && ws.monitor?.name === name
            && ws.toplevels.values.some(toplevel => toplevel.wayland?.fullscreen));
    }

    function triggerOsd() {
        if (!root.currentIndicator)
            root.currentIndicator = "volume";
        if (!Config.osdIndicatorEnabled(root.currentIndicator))
            return;
        if (Config.ready && Config.options.osd && Config.options.osd.hideWhenFullscreen && root.fullscreenOnOsdScreen())
            return;
        GlobalStates.osdVolumeOpen = true;
        root.updateTimeout();
    }

    function updateTimeout() {
        if (root.hovered || !GlobalStates.osdVolumeOpen) {
            osdTimeout.stop();
            return;
        }
        osdTimeout.restart();
    }

    Timer {
        id: osdTimeout
        interval: Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            GlobalStates.osdVolumeOpen = false;
            root.protectionMessage = "";
        }
    }

    Connections {
        target: GlobalStates
        ignoreUnknownSignals: true
        function onOsdInteraction() {
            root.triggerOsd();
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.protectionMessage = "";
            root.currentIndicator = "brightness";
            root.triggerOsd();
        }
    }

    Connections {
        target: Hyprsunset
        function onGammaChangeAttempt() {
            root.protectionMessage = "";
            root.currentIndicator = "gamma";
            root.triggerOsd();
        }
    }

    Connections {
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready || root.isStartup)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onMutedChanged() {
            if (!Audio.ready || root.isStartup)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        target: Audio
        function onSinkProtectionTriggered(reason) {
            root.protectionMessage = reason;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        id: playerVolumeConnections
        target: MprisController.activePlayer ?? null
        function onVolumeChanged() {
            if (MprisController.canChangeVolume) {
                root.volumePlayer = playerVolumeConnections.target;
                root.currentIndicator = "playerVolume";
                root.triggerOsd();
            }
        }
    }

    Connections {
        target: KeyboardBacklight
        function onCurrentValueChanged() {
            if (root.isStartup)
                return;
            root.currentIndicator = "keyboardBrightness";
            root.triggerOsd();
        }
    }

    // The surface has to outlive the request or there is nothing left to play the exit
    // on -- `active` bound straight to `osdVolumeOpen` destroys it on the frame the flag
    // clears, which is why this OSD has never had an animation of any kind.
    property bool isClosing: false

    Loader {
        id: osdLoader
        active: GlobalStates.osdVolumeOpen || root.isClosing

        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"
            readonly property bool hovered: osdHover.hovered

            // 0 parked behind the bar, 1 resting. Enter decelerating on the default
            // spatial spec, exit accelerating on fast effects at half that duration
            // (DESIGN.md 2.5). The spec is picked inside the binding that writes the
            // property, because a Behavior cannot read its own direction (2.9).
            property real openedProgress: 0
            property AnimSpec openSpec: Appearance.animation.elementMoveEnter

            Behavior on openedProgress {
                NumberAnimation {
                    duration: osdRoot.openSpec.duration
                    easing.type: osdRoot.openSpec.type
                    easing.bezierCurve: osdRoot.openSpec.bezierCurve
                }
            }

            onOpenedProgressChanged: {
                if (openedProgress === 0)
                    root.isClosing = false;
            }

            Connections {
                target: GlobalStates
                function onOsdVolumeOpenChanged() {
                    if (GlobalStates.osdVolumeOpen) {
                        root.isClosing = false;
                        osdRoot.openSpec = Appearance.animation.elementMoveEnter;
                        osdRoot.openedProgress = 1;
                    } else {
                        root.isClosing = true;
                        osdRoot.openSpec = Appearance.animation.elementMoveExit;
                        osdRoot.openedProgress = 0;
                    }
                }
            }

            onVisibleChanged: {
                // From Component.onCompleted most of the slide plays before the first
                // frame is on screen.
                if (visible && GlobalStates.osdVolumeOpen) {
                    osdRoot.openSpec = Appearance.animation.elementMoveEnter;
                    osdRoot.openedProgress = 1;
                }
            }

            Connections {
                target: root
                function onFocusedScreenChanged() {
                    osdRoot.screen = root.focusedScreen;
                }
            }

            WlrLayershell.namespace: "quickshell:onScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: !Config.options.bar.bottom
                bottom: Config.options.bar.bottom
            }
            mask: Region {
                item: osdValuesWrapper
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            margins {
                top: Appearance.sizes.barHeight
                bottom: Appearance.sizes.barHeight
            }

            implicitWidth: osdValuesWrapper.implicitWidth
            implicitHeight: osdValuesWrapper.implicitHeight
            visible: Quickshell.screens.length > 0

            // Grows out of the bar it sits under, by the anchor margin rather than a
            // transform -- `mask` recomputes its region from this item's *geometry*,
            // and a transform on a masked item freezes the input region (see
            // tools/check-mask-regions.py).
            Item {
                id: osdValuesWrapper
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: Config.options.bar.bottom ? undefined : parent.top
                anchors.bottom: Config.options.bar.bottom ? parent.bottom : undefined
                anchors.topMargin: Config.options.bar.bottom ? 0 : -height * (1 - osdRoot.openedProgress)
                anchors.bottomMargin: Config.options.bar.bottom ? -height * (1 - osdRoot.openedProgress) : 0
                implicitHeight: contentColumnLayout.implicitHeight
                implicitWidth: contentColumnLayout.implicitWidth
                // Spatial progress may overshoot; opacity must not.
                opacity: Math.min(1, osdRoot.openedProgress)
                clip: true

                // The OSD is an acknowledgement. Pause its dismissal under the
                // pointer and give it a full timeout when the pointer leaves.
                HoverHandler {
                    id: osdHover
                }

                Column {
                    id: contentColumnLayout
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    spacing: 0

                    Loader {
                        id: osdIndicatorLoader
                        source: root.indicators.find(i => i.id === root.currentIndicator)?.sourceUrl
                        onLoaded: {
                            if (root.currentIndicator === "playerVolume")
                                osdIndicatorLoader.item.player = Qt.binding(() => root.volumePlayer);
                        }
                    }

                    Item {
                        id: protectionMessageWrapper
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitHeight: protectionMessageBackground.implicitHeight
                        implicitWidth: protectionMessageBackground.implicitWidth

                        // Without `visible`, an empty message still reserved its card's
                        // height in the column and pushed the indicator up the screen.
                        property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
                        opacity: {
                            const shown = root.protectionMessage !== "";
                            protectionMessageWrapper.fadeSpec = shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                            return shown ? 1 : 0;
                        }
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: protectionMessageWrapper.fadeSpec.duration
                                easing.type: protectionMessageWrapper.fadeSpec.type
                                easing.bezierCurve: protectionMessageWrapper.fadeSpec.bezierCurve
                            }
                        }

                        StyledRectangularShadow {
                            target: protectionMessageBackground
                        }
                        Rectangle {
                            id: protectionMessageBackground
                            anchors.centerIn: parent
                            color: Appearance.colors.colError
                            property real padding: 10
                            implicitHeight: protectionMessageRowLayout.implicitHeight + padding * 2
                            implicitWidth: protectionMessageRowLayout.implicitWidth + padding * 2
                            radius: Appearance.rounding.normal

                            RowLayout {
                                id: protectionMessageRowLayout
                                anchors.centerIn: parent
                                MaterialSymbol {
                                    id: protectionMessageIcon
                                    text: "dangerous"
                                    iconSize: Appearance.font.pixelSize.hugeass
                                    color: Appearance.colors.colOnError
                                }
                                StyledText {
                                    id: protectionMessageTextWidget
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Appearance.colors.colOnError
                                    wrapMode: Text.Wrap
                                    text: root.protectionMessage
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osdVolume"

        function trigger() {
            root.triggerOsd();
        }

        function hide() {
            GlobalStates.osdVolumeOpen = false;
        }

        function toggle() {
            GlobalStates.osdVolumeOpen = !GlobalStates.osdVolumeOpen;
        }
    }
    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed: {
            root.triggerOsd();
        }
    }
    GlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed: {
            GlobalStates.osdVolumeOpen = false;
        }
    }
}
