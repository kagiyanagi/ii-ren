import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

pragma ComponentBehavior: Bound

Scope {
    id: dock

    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    readonly property string dockEffectivePosition: {
        const pos = Config.options?.dock.position ?? "bottom"
        if (pos !== "auto") return pos
        return (Config.options?.bar.bottom && !Config.options?.bar.vertical) ? "top" : "bottom"
    }

    readonly property bool isVertical: dockEffectivePosition === "left" || dockEffectivePosition === "right"

    function computeSizes(opts) {
        const gapsOut = opts.gapsOut
        const barConflicts = opts.barActive && (opts.isVertical !== opts.barIsVertical)
        
        const barOffset = barConflicts ? (opts.isVertical ? opts.barThickness : 0) : 0
        const barOffsetH = barConflicts ? (!opts.isVertical ? opts.barThickness : 0) : 0

        const maxW = Math.max(1, opts.availableW - gapsOut * 2 - barOffsetH)
        const maxH = Math.max(1, opts.availableH - gapsOut * 2 - barOffset)

        const unloadedW = maxW
        const unloadedH = maxH

        const contentW = opts.isLoaded ? opts.contentVisualWidth : (opts.isVertical ? 60 : unloadedW)
        const contentH = opts.isLoaded ? opts.contentVisualHeight : (opts.isVertical ? unloadedH : 60)
        // Attached to the edge: only the inner gap is left, the outer one goes.
        const crossGaps = opts.attached ? gapsOut : gapsOut * 2
        return {
            maxWidth: maxW,
            maxHeight: maxH,
            dockWidth: opts.isVertical ? contentW + crossGaps : Math.min(contentW + gapsOut * 2, maxW),
            dockHeight: opts.isVertical ? Math.min(contentH + gapsOut * 2, maxH) : contentH + crossGaps,
            dockThickness: opts.isVertical ? contentW + crossGaps : contentH + crossGaps,
            backgroundWidth:  Math.max(1, opts.isVertical ? contentW : Math.min(contentW, maxW - gapsOut * 2)),
            backgroundHeight: Math.max(1, opts.isVertical ? Math.min(contentH, maxH - gapsOut * 2) : contentH)
        }
    }

    // The folder card takes keyboard focus for its name field, which a popup on
    // the dock's own surface cannot, so it is a panel of its own out here rather
    // than a child of the dock window.
    property alias folderCard: folderCardPopup
    DockFolderPopup {
        id: folderCardPopup
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            required property var modelData
            screen: modelData
            
            visible: !GlobalStates.screenLocked && !positionChanging 
            // using a flag for positionChanging is not really necessary, but it prevents some graphical issues caused by qml when the dock is moving

            readonly property real availableW: screen?.width ?? 1920
            readonly property real availableH: screen?.height ?? 1080
            readonly property bool barActive: GlobalStates.barOpen
            readonly property bool barIsVertical: Config.options?.bar?.vertical ?? false
            readonly property real barThickness: barActive ? (barIsVertical ? (Config.options?.bar?.sizes?.width ?? Appearance.sizes.verticalBarWidth) : (Config.options?.bar?.sizes?.height ?? Appearance.sizes.barHeight)) : 0

            readonly property bool isVertical: dock.isVertical
            readonly property real dockThickness: isVertical ? dockRoot.sizing.dockWidth : dockRoot.sizing.dockHeight

            // reveal is set imperatively (not as a binding) to avoid a binding loop:
            property bool reveal: false
            property bool positionChanging: false
            readonly property bool readyToReveal: reveal && (dockLoader.item?.ready ?? false)

            // The dock is on the overlay layer, so a pinned dock would sit on top
            // of fullscreen windows - treat fullscreen as unpinned. Same
            // per-monitor check as ScreenCorners.
            readonly property var hyprMonitor: Hyprland.monitorFor(dockRoot.modelData)
            readonly property bool fullscreenActive: Hyprland.workspaces.values.some(ws =>
                ws.active && ws.monitor?.name === dockRoot.hyprMonitor?.name
                && ws.toplevels.values.some(toplevel => toplevel.wayland?.fullscreen))
            readonly property bool pinnedEffective: dock.pinned && !fullscreenActive

            onPinnedEffectiveChanged: updateReveal()

            function updateReveal() {
                var shouldReveal = dockRoot.pinnedEffective
                    || (dockMouseArea.containsMouse || graceTimer.running)
                    || (dockLoader.item?.requestDockShow ?? false)
                    || (Config.options?.dock?.revealOnEmptyWorkspace && workspaceEmpty)
                if (reveal !== shouldReveal)
                    reveal = shouldReveal
            }

            // TODO: check for multi-monitor situations
            readonly property bool workspaceEmpty: {
                const wsId = HyprlandData.activeWorkspace?.id ?? -1
                if (wsId === -1) return true
                return HyprlandData.hyprlandClientsForWorkspace(wsId).length === 0
            }

            onWorkspaceEmptyChanged: updateReveal()

            readonly property bool attachedToEdge: Config.options?.dock?.attachToEdge ?? false

            readonly property var sizing: dock.computeSizes({
                gapsOut: Appearance.sizes.hyprlandGapsOut,
                attached: dockRoot.attachedToEdge,
                isVertical: dock.isVertical,
                barActive: dockRoot.barActive,
                barIsVertical: dockRoot.barIsVertical,
                barThickness: dockRoot.barThickness,
                availableW: dockRoot.availableW,
                availableH: dockRoot.availableH,
                isLoaded: dockLoader.activeAsync,
                contentVisualWidth: dockLoader.item?.contentVisualWidth ?? 0,
                contentVisualHeight: dockLoader.item?.contentVisualHeight ?? 0
            })

            implicitWidth: Math.max(1, dockRoot.sizing.dockWidth)
            implicitHeight: Math.max(1, dockRoot.sizing.dockHeight)

            anchors {
                top: dock.dockEffectivePosition !== "bottom"
                bottom: dock.dockEffectivePosition !== "top"
                left: dock.dockEffectivePosition !== "right"
                right: dock.dockEffectivePosition !== "left"
            }

            // dockThickness already includes gapsOut on the inner side; hyprland
            // adds its own gaps_out to the reserved edge, so reserve one less.
            exclusiveZone: dockRoot.pinnedEffective ? dockThickness - Appearance.sizes.hyprlandGapsOut : 0
            WlrLayershell.namespace: "quickshell:dock"
            WlrLayershell.layer: WlrLayer.Overlay
            color: "transparent"

            mask: Region { 
                item: dockMouseArea 
            }

            Timer { 
                id: unloadTimer
                interval: Appearance.animation.elementMoveFast.duration + 100 
            }

            // Grace timer: keeps the dock revealed for 1 second after the initial
            // hover trigger, giving the user time to reach the dock as it expands.
            Timer {
                id: graceTimer
                interval: Appearance.animation.elementMoveFast.duration + 800 
                onRunningChanged: dockRoot.updateReveal()
            }

            onRevealChanged: {
                if (!reveal) unloadTimer.restart()
                else unloadTimer.stop()
            }

            // Watch dock.pinned changes to update reveal
            Connections {
                target: dock
                function onPinnedChanged() { dockRoot.updateReveal() }
                function onDockEffectivePositionChanged() {
                    dockRoot.positionChanging = true
                    positionChangeTimer.restart()
                }
            }

            Timer {
                id: positionChangeTimer
                interval: 200
                onTriggered: dockRoot.positionChanging = false
            }

            // Make the dock clickable while another panel holds a focus grab
            // (overview, sidebars) instead of the first click just dismissing them.
            Component.onCompleted: GlobalFocusGrab.addPersistent(dockRoot)
            Component.onDestruction: GlobalFocusGrab.removePersistent(dockRoot)

            HyprlandFocusGrab {
                id: dragFocusGrab
                active: dockLoader.activeAsync && (dockLoader.item?.dragState ?? "idle") !== "idle"
                windows: [dockRoot]
                onCleared: {
                    if (dockLoader.item && dockLoader.item.dragState !== "idle") {
                        dockLoader.item.endDrag()
                        dockLoader.item.endFileDrag()
                    }
                }
            }

            MouseArea {
                id: dockMouseArea
                hoverEnabled: true

                // When the mouse enters the hover strip and the dock is hidden,
                // start the grace timer so the dock stays open for 1 second while
                // it animates and the user moves the cursor onto it.
                onContainsMouseChanged: {
                    if (containsMouse && !dockRoot.reveal && !dockRoot.pinnedEffective) {
                        graceTimer.restart()
                    }
                    // Update reveal imperatively to avoid binding loop
                    dockRoot.updateReveal()
                }

                property real hiddenOffset: dockRoot.dockThickness - (Config.options?.dock.hoverRegionHeight ?? 2)
                property real currentOffset: dockRoot.readyToReveal ? 0 : hiddenOffset

                width: dock.isVertical ? dockRoot.dockThickness : dockRoot.sizing.dockWidth
                height: dock.isVertical ? dockRoot.sizing.dockHeight : dockRoot.dockThickness

                state: dock.dockEffectivePosition

                states: [
                    State {
                        name: "top"
                        AnchorChanges { target: dockMouseArea; anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter }
                        PropertyChanges { target: dockMouseArea; anchors.topMargin: -currentOffset }
                    },
                    State {
                        name: "bottom"
                        AnchorChanges { target: dockMouseArea; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter }
                        PropertyChanges { target: dockMouseArea; anchors.bottomMargin: -currentOffset }
                    },
                    State {
                        name: "left"
                        AnchorChanges { target: dockMouseArea; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                        PropertyChanges { target: dockMouseArea; anchors.leftMargin: -currentOffset }
                    },
                    State {
                        name: "right"
                        AnchorChanges { target: dockMouseArea; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
                        PropertyChanges { target: dockMouseArea; anchors.rightMargin: -currentOffset }
                    }
                ]

                Behavior on anchors.topMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockMouseArea) }
                Behavior on anchors.bottomMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockMouseArea) }
                Behavior on anchors.leftMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockMouseArea) }
                Behavior on anchors.rightMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockMouseArea) }

                Item {
                    id: dockContentHost
                    anchors.fill: parent

                    LazyLoader {
                        id: dockLoader
                        loading: true
                        active: dockRoot.reveal || unloadTimer.running

                        Item {
                            id: wrapper
                            parent: dockContentHost
                            anchors.fill: parent

                            readonly property real contentVisualWidth: content.visualWidth
                            readonly property real contentVisualHeight: content.visualHeight
                            readonly property string dragState: content.dragState
                            readonly property bool requestDockShow: content.requestDockShow
                            readonly property bool ready: content.ready

                            function endDrag() { content.endDrag() }
                            function endFileDrag() { content.endFileDrag() }
                            function mimeIconFromPath(p) { return content.mimeIconFromPath(p) }

                            // When requestDockShow changes inside the loaded content, update reveal
                            onRequestDockShowChanged: dockRoot.updateReveal()

                            // Only show once DockContent itself is ready 
                            readonly property bool contentReady: content.ready && !dockRoot.positionChanging
                            opacity: contentReady ? 1.0 : 0.0

                            StyledRectangularShadow { 
                                target: visualBackground
                            }

                            Rectangle {
                                id: visualBackground

                                // Which screen edge the dock is glued to, if any.
                                readonly property string flushEdge: dockRoot.attachedToEdge ? dock.dockEffectivePosition : ""
                                readonly property real edgeShift: Appearance.sizes.hyprlandGapsOut / 2
                                // Run past the edge so the 1px border - and any
                                // rounding slop - lands off screen, not as a seam.
                                readonly property real edgeBleed: flushEdge === "" ? 0 : border.width + 1
                                readonly property real totalShift: edgeShift + edgeBleed / 2
                                readonly property bool flushVertically: flushEdge === "top" || flushEdge === "bottom"

                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: flushEdge === "bottom" ? totalShift : (flushEdge === "top" ? -totalShift : 0)
                                anchors.horizontalCenterOffset: flushEdge === "right" ? totalShift : (flushEdge === "left" ? -totalShift : 0)
                                width: dockRoot.sizing.backgroundWidth + (flushVertically ? 0 : edgeBleed)
                                height: dockRoot.sizing.backgroundHeight + (flushVertically ? edgeBleed : 0)
                                color: Appearance.colors.colLayer0
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                                radius: Config.options?.dock?.cornerRadius >= 0 ? Config.options.dock.cornerRadius : Appearance.rounding.large
                                topLeftRadius: (flushEdge === "top" || flushEdge === "left") ? 0 : radius
                                topRightRadius: (flushEdge === "top" || flushEdge === "right") ? 0 : radius
                                bottomLeftRadius: (flushEdge === "bottom" || flushEdge === "left") ? 0 : radius
                                bottomRightRadius: (flushEdge === "bottom" || flushEdge === "right") ? 0 : radius

                                DropArea {
                                    id: fileDropArea
                                    anchors.fill: parent
                                    keys: ["text/uri-list"]
                                    enabled: content.dragActive === false

                                    onEntered: (drag) => {
                                        if (!drag.hasUrls) return
                                        const url = drag.urls[0]?.toString() ?? ""
                                        content.externalDragIcon = content.mimeIconFromPath(url)
                                        content.externalDragOver = true
                                    }
                                    onExited: {
                                        content.externalDragIcon = ""
                                        content.externalDragOver = false
                                    }
                                    onDropped: (drop) => {
                                        if (!drop.hasUrls) return
                                        for (let i = 0; i < drop.urls.length; i++)
                                            TaskbarApps.addPinnedFile(drop.urls[i])
                                        drop.accept(Qt.CopyAction)
                                        content.externalDragIcon = ""
                                        content.externalDragOver = false
                                    }
                                }

                                DockContent {
                                    id: content
                                    anchors.fill: parent
                                    // Keep the content where it was - only the
                                    // background grows into the bleed.
                                    anchors.topMargin: (visualBackground.flushEdge === "top" ? visualBackground.edgeBleed : 0) + (Config.options?.dock?.paddingVertical ?? 0)
                                    anchors.bottomMargin: (visualBackground.flushEdge === "bottom" ? visualBackground.edgeBleed : 0) + (Config.options?.dock?.paddingVertical ?? 0)
                                    anchors.leftMargin: (visualBackground.flushEdge === "left" ? visualBackground.edgeBleed : 0) + (Config.options?.dock?.paddingHorizontal ?? 0)
                                    anchors.rightMargin: (visualBackground.flushEdge === "right" ? visualBackground.edgeBleed : 0) + (Config.options?.dock?.paddingHorizontal ?? 0)
                                    isPinned: dock.pinned
                                    currentScreen: dockRoot.screen
                                    workspaceEmpty: dockRoot.workspaceEmpty
                                    onTogglePinRequested: dock.pinned = !dock.pinned
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
