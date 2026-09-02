pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.utils //FIXME. remove
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.media

Scope {
    id: backgroundScope

    // Shared desktop-widget state: one instance model for every screen.
    WidgetStateManager {
        id: widgetState
    }
    readonly property alias widgetStateManager: widgetState
    readonly property alias widgetSyncVersion: widgetState.syncVersion

// Left at its original indentation on purpose: re-indenting the whole file would
// turn every future upstream merge of Background.qml into a conflict.
Variants {
    id: root
    model: Quickshell.screens
    
    PanelWindow {
        id: bgRoot

        required property var modelData

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

        readonly property int activeWorkspaceId: monitor?.activeWorkspace?.id ?? -1

        readonly property bool isCovered: {
            if (activeWorkspaceId === -1 || !monitor) return false;
            return HyprlandData.windowList.some(w => w.workspace?.id === activeWorkspaceId && w.monitor === monitor.id && !w.floating);
        }

        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10

        // Wallpaper
        property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
        // Subject depth on a video means we play it here, packed with its matte,
        // instead of letting mpvpaper have it.
        readonly property bool depthVideo: WallpaperSubject.packedVideo.length > 0
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        property real wallpaperToScreenRatio: Math.min(wallpaperWidth / screen.width, wallpaperHeight / screen.height)
        property real preferredWallpaperScale: Config.options.background.parallax.workspaceZoom
        property real effectiveWallpaperScale: 1 // Some reasonable init value, to be updated
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.width) / 2
        property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.height) / 2

        readonly property bool parallaxEnabled: Config.options.background.parallax.enableWorkspace
            || Config.options.background.parallax.enableSidebar
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Colors
        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"

        property var zoomLevels: {  // has to be reverted compared to background
            "in": { default: 1.04, zoomed: 1 },
            "out": { default: 1, zoomed: 1.04 }
        }

        property real defaultRatio: zoomInStyle ? zoomLevels.in.default : zoomLevels.out.default
        property real zoomedRatio: zoomInStyle ? zoomLevels.in.zoomed : zoomLevels.out.zoomed

        readonly property bool zoomInStyle: Config.options.overview.scrollingStyle.zoomStyle === "in"
        readonly property bool showOpeningAnimation: Config.options.overview.showOpeningAnimation

        property bool overviewOpen: GlobalStates.overviewOpen

        // How far the desktop plane pushes in behind the launcher. The scrolling
        // overview's own zoom is gated behind that layout, so every other layout
        // had no reaction to the launcher at all.
        readonly property real launcherZoom: 1.06

        property real scaleAnimated: GlobalStates.overviewOpen && showOpeningAnimation ? zoomedRatio : defaultRatio
        Behavior on scaleAnimated {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Top : WlrLayer.Bottom
        // WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onParallaxEnabledChanged: bgRoot.updateZoomScale()
        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }

        // Wallpaper zoom scale
        function updateZoomScale() {
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-format", "%w %h", path]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    const [screenWidth, screenHeight] = [bgRoot.screen.width, bgRoot.screen.height];
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;

                    let scale;
                    if (width <= screenWidth || height <= screenHeight) {
                        // Undersized/perfectly sized wallpapers
                        scale = Math.max(screenWidth / width, screenHeight / height);
                    } else {
                        // Oversized = can be zoomed for parallax, yay
                        scale = Math.min(bgRoot.preferredWallpaperScale, width / screenWidth, height / screenHeight);
                    }

                    // Parallax pans the wallpaper about inside the screen, so it
                    // needs a wallpaper bigger than the screen to pan. One that
                    // matches the screen exactly covers it and leaves nothing to
                    // move, and parallax then does nothing at all with no hint
                    // as to why - which is every 1920x1080 wallpaper on a
                    // 1920x1080 panel, and most video wallpapers, since they are
                    // usually cut to the panel. Give those the same zoom an
                    // oversized wallpaper gets; anything that already has room
                    // keeps the room it has.
                    bgRoot.effectiveWallpaperScale = (bgRoot.parallaxEnabled && scale <= 1)
                        ? bgRoot.preferredWallpaperScale : scale;
                }
            }
        }

        property bool mediaModeOpen: mediaModeLoader.active && MprisController.activePlayer
        onMediaModeOpenChanged: {
            if (!mediaModeOpen && Config.options.appearance.palette.type.startsWith("scheme")) {
                Wallpapers.apply(Config.options.background.wallpaperPath)
                LyricsService.shellColorChanged = false
            }
        }

        property var _extensionBgWidgetEntries: []
        property var _pendingWidgetSaves: ({})

        Timer {
            id: bgWidgetSaveTimer
            interval: 300
            repeat: false
            onTriggered: {
                for (let key in bgRoot._pendingWidgetSaves) {
                    let p = bgRoot._pendingWidgetSaves[key]
                    ExtensionManager.saveExtensionWidgetConfig(p.extId, p.wid, p.config)
                }
                bgRoot._pendingWidgetSaves = {}
            }
        }

        function refreshExtensionBgWidgets() {
            // Destroy all existing extension widget objects
            for (let i = 0; i < _extensionBgWidgetEntries.length; i++) {
                let entry = _extensionBgWidgetEntries[i]
                if (entry) {
                    if (entry.cfg) entry.cfg.destroy()
                    if (entry.widget) entry.widget.destroy()
                }
            }
            _extensionBgWidgetEntries = []

            let list = ExtensionManager.getContributionPoint("backgroundWidgets")

            for (let wi = 0; wi < list.length; wi++) {
                let entry = list[wi]
                let fullPath = entry.fullPath
                let extId = entry.extensionId
                let wid = entry.identifier
                let x = entry.x
                let y = entry.y
                let strat = entry.placementStrategy || "free"

                let comp = ExtensionManager.loadExtensionQmlComponent(fullPath)

                let createWidget = (comp, entry, fullPath, extId, wid, x, y, strat) => {
                    let savedWidgetConfig = ExtensionManager.getExtensionWidgetConfig(extId, wid)
                    let savedX = savedWidgetConfig ? savedWidgetConfig.x : x
                    let savedY = savedWidgetConfig ? savedWidgetConfig.y : y
                    let qml = 'import QtQml; QtObject { property bool enable: true; property real x: ' + savedX + '; property real y: ' + savedY + '; property string placementStrategy: "' + strat + '" }'
                    let cfg = Qt.createQmlObject(qml,bgRoot)

                    let onPosChanged = () => {
                        bgRoot._pendingWidgetSaves[extId + "/" + wid] = {
                            extId: extId,
                            wid: wid,
                            config: { enable: cfg.enable, x: cfg.x, y: cfg.y }
                        }
                        bgWidgetSaveTimer.restart()
                    }
                    cfg.xChanged.connect(onPosChanged)
                    cfg.yChanged.connect(onPosChanged)

                    let widget = comp.createObject(widgetCanvas, {
                        configEntry: cfg,
                        screenWidth: bgRoot.screen.width,
                        screenHeight: bgRoot.screen.height,
                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale,
                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale,
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                    })

                    if (widget && extId) {
                        if ("extensionId" in widget) {
                            widget.extensionId = extId
                        } else {
                            Object.defineProperty(widget, "extensionId", {
                                value: extId,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            })
                        }
                        let entries = _extensionBgWidgetEntries.slice()
                        entries.push({ widget: widget, cfg: cfg })
                        _extensionBgWidgetEntries = entries
                    }
                }

                if (comp.status === Component.Ready) {
                    createWidget(comp, entry, fullPath, extId, wid, x, y, strat)
                } else if (comp.status === Component.Error) {
                    console.warn("Background: failed to load extension widget component for", extId, wid, ":", comp.errorString())
                } else {
                    comp.statusChanged.connect(() => {
                        if (comp.status === Component.Ready) {
                            createWidget(comp, entry, fullPath, extId, wid, x, y, strat)
                        } else if (comp.status === Component.Error) {
                            console.warn("Background: async component error for", extId, wid, ":", comp.errorString())
                        }
                    })
                }
            }

        }

        Component.onCompleted: {
            refreshExtensionBgWidgets()
            if (!mediaModeOpen && Config.options.appearance.palette.type.startsWith("scheme")) {
                Wallpapers.apply(Config.options.background.wallpaperPath)
            }
        }

        Connections {
            target: ExtensionManager
            function onRefreshExtensions() { refreshExtensionBgWidgets() }
        }

        // Right-click the empty desktop for a context menu. Declared before
        // wallpaperItem for the same reason as the drop area below: a widget that
        // wants its own right-click still wins wherever it sits.
        MouseArea {
            id: desktopMenuArea
            anchors.fill: parent
            enabled: Config.options.background.rightClickMenu
            acceptedButtons: Qt.RightButton

            // Press, not click: waiting for the button to come back up is what
            // makes a context menu feel like it responded late. The menu's own
            // dismiss handler takes a full click, so the release that follows
            // this press cannot immediately close it again.
            onPressed: mouse => {
                GlobalStates.desktopMenuWidgetId = null;
                GlobalStates.desktopMenuScreen = bgRoot.screen;
                GlobalStates.desktopMenuX = mouse.x;
                GlobalStates.desktopMenuY = mouse.y;
                GlobalStates.desktopMenuOpen = true;
            }
        }

        // Drop an image (or video) anywhere on the desktop to set it as the
        // wallpaper. Declared before wallpaperItem so it sits underneath the
        // widget canvas - a widget that takes its own drops (AtAGlanceWidget)
        // still wins wherever it sits.
        DropArea {
            id: wallpaperDrop
            anchors.fill: parent
            keys: ["text/uri-list"]
            // Disabled rather than unloaded so the drop falls through to
            // whatever is underneath instead of being swallowed.
            enabled: Config.options.background.dropToSetWallpaper || Config.options.background.dropToShelf

            // Non-empty only while the drag is carrying something apply() can use.
            property string pendingPath: ""
            // How many local files the drag is carrying, when the shelf is what
            // would take them.
            property int pendingShelfCount: 0

            function localPaths(urls) {
                const paths = [];
                for (const url of urls) {
                    const asString = url.toString();
                    const path = CF.FileUtils.trimFileProtocol(asString);
                    // A remote drag - an image straight off a web page - comes
                    // back unchanged here and would have to be downloaded first,
                    // so it is left for the drag source to handle.
                    if (path === asString)
                        continue;
                    paths.push(path);
                }
                return paths;
            }

            function wallpaperPathFrom(paths) {
                if (!Config.options.background.dropToSetWallpaper || paths.length !== 1)
                    return "";
                const path = paths[0];
                return Wallpapers.extensions.some(ext => path.toLowerCase().endsWith(`.${ext}`)) ? path : "";
            }

            onEntered: drag => {
                const paths = drag.hasUrls ? wallpaperDrop.localPaths(drag.urls) : [];
                wallpaperDrop.pendingPath = wallpaperDrop.wallpaperPathFrom(paths);
                // A single image sets the wallpaper; anything else the shelf can
                // hold onto goes there instead.
                wallpaperDrop.pendingShelfCount = (wallpaperDrop.pendingPath.length > 0 || !Config.options.background.dropToShelf) ? 0 : paths.length;
                // Refusing here means no onDropped, so a drag neither of them can
                // use falls through instead of being swallowed.
                if (wallpaperDrop.pendingPath.length === 0 && wallpaperDrop.pendingShelfCount === 0)
                    drag.accepted = false;
            }

            onExited: {
                wallpaperDrop.pendingPath = "";
                wallpaperDrop.pendingShelfCount = 0;
            }

            onDropped: drop => {
                if (wallpaperDrop.pendingPath.length > 0) {
                    // Same call the wallpaper selector makes, so the colour
                    // scheme is regenerated too.
                    Wallpapers.apply(wallpaperDrop.pendingPath);
                    drop.acceptProposedAction();
                } else if (wallpaperDrop.pendingShelfCount > 0) {
                    // Global coordinates: the shelf is its own layer surface, so
                    // the drop point has to leave this window's space.
                    const globalPos = wallpaperDrop.mapToGlobal(drop.x, drop.y);
                    DropShelf.show(drop.urls, globalPos.x, globalPos.y);
                    drop.acceptProposedAction();
                }
                wallpaperDrop.pendingPath = "";
                wallpaperDrop.pendingShelfCount = 0;
            }

            Rectangle {
                anchors.centerIn: parent
                implicitWidth: dropHintRow.implicitWidth + 40
                implicitHeight: dropHintRow.implicitHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                border.width: 2
                border.color: Appearance.colors.colPrimary
                visible: opacity > 0
                opacity: (wallpaperDrop.containsDrag && (wallpaperDrop.pendingPath.length > 0 || wallpaperDrop.pendingShelfCount > 0)) ? 1 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: dropHintRow
                    anchors.centerIn: parent
                    spacing: 12

                    MaterialSymbol {
                        text: wallpaperDrop.pendingPath.length > 0 ? "wallpaper" : "stacks"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        spacing: 0

                        StyledText {
                            text: wallpaperDrop.pendingPath.length > 0
                                ? Translation.tr("Set as wallpaper")
                                : Translation.tr("Hold on the shelf")
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            Layout.maximumWidth: 320
                            text: wallpaperDrop.pendingPath.length > 0
                                ? wallpaperDrop.pendingPath.split("/").pop()
                                : Translation.tr("%1 files").arg(wallpaperDrop.pendingShelfCount)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }
        }

        Item {
            id: wallpaperItem
            anchors.fill: parent
            clip: true
            scale: {
                if (!showOpeningAnimation)
                    return defaultRatio;
                if (bgRoot.isScrollingLayout)
                    return overviewOpen ? zoomedRatio : defaultRatio;
                // Scales the whole plane, widgets included, rather than the
                // wallpaper alone - widgets holding still while the image moved
                // under them reads as a glitch, not an effect.
                return overviewOpen ? defaultRatio * bgRoot.launcherZoom : defaultRatio;
            }
            opacity: mediaModeOpen ? 0 : 1
            
            Behavior on opacity {
                NumberAnimation { duration: 300; easing.type: Easing.InOutQuad }
            }

            Behavior on scale {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }

            Rectangle {
                anchors.fill: parent
                visible: Config.options.background.shape.enable
                color: {
                    let c = Config.options.background.shape.backgroundColor;
                    if (c && c.startsWith("@")) {
                        let prop = c.substring(1);
                        if (Appearance.colors[prop]) return Appearance.colors[prop];
                    }
                    return c || "transparent";
                }
            }

            Item {
                id: wallpaperVisuals
                anchors.fill: parent
                layer.enabled: Config.options.background.shape.enable
                layer.effect: OpacityMask {
                    maskSource: Item {
                        width: wallpaperVisuals.width
                        height: wallpaperVisuals.height
                        MaterialShape {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) * (Config.options.background.shape.size ?? 0.95)
                            height: width
                            shapeString: Config.options.background.shape.style
                        }
                    }
                }

                // Wallpaper
                Item {
                    id: wallpaper
                    visible: !blurLoader.active
                // The packed video is double height, and the bottom half is the
                // matte. Without this it paints over the lower desktop.
                clip: bgRoot.depthVideo
                opacity: (bgRoot.wallpaperIsVideo && !bgRoot.depthVideo && !wallpaperEffects.takesOver && !blurLoader.active) ? 0 : 1
                // Range = groups that workspaces span on
                property int chunkSize: Config?.options.bar.workspaces.shown ?? 10
                property int lower: Math.floor(bgRoot.firstWorkspaceId / chunkSize) * chunkSize
                property int upper: Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize
                property int range: upper - lower
                property real valueX: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);

                    }
                    return result;
                }
                property real sidebarOffsetX: {
                    if (!Config.options.background.parallax.enableSidebar) return 0;
                    return (0.15 * GlobalStates.effectiveRightOpen - 0.15 * GlobalStates.effectiveLeftOpen);

                }
                property real valueY: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                    }
                    return result;
                }
                property real effectiveValueX: Math.max(0, Math.min(1, valueX)) + sidebarOffsetX
                property real effectiveValueY: Math.max(0, Math.min(1, valueY))
                x: -(bgRoot.movableXSpace) - (effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                y: -(bgRoot.movableYSpace) - (effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace

                Behavior on x {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on width {
                    NumberAnimation {
                        duration: 800
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on height {
                    NumberAnimation {
                        duration: 800
                        easing.type: Easing.OutCubic
                    }
                }
                width: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                height: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale

                TransitionImage {
                    anchors.fill: parent
                    visible: !bgRoot.wallpaperIsVideo
                    imageSource: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                    animated: true
                    fillMode: Image.PreserveAspectCrop
                }

                MediaPlayer {
                    id: videoPlayer
                    source: {
                        if (bgRoot.wallpaperSafetyTriggered)
                            return "";
                        // The packed copy stands in for the original wholesale:
                        // its top half is the same frames, so everything
                        // downstream - effects, lock blur - sees a wallpaper.
                        if (bgRoot.depthVideo)
                            return WallpaperSubject.packedVideo;
                        if (bgRoot.wallpaperIsVideo && (wallpaperEffects.takesOver || blurLoader.active))
                            return "file://" + CF.FileUtils.trimFileProtocol(Config.options.background.wallpaperPath);
                        return "";
                    }
                    audioOutput: AudioOutput { muted: true }
                    videoOutput: vidOutput
                    loops: MediaPlayer.Infinite
                    autoPlay: true
                }

                VideoOutput {
                    id: vidOutput
                    // Anchored on three sides with an explicit height, never a
                    // fourth anchor: the packed video is twice as tall as the
                    // wallpaper, and only its top half belongs on screen.
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: bgRoot.depthVideo ? parent.height * 2 : parent.height
                    visible: bgRoot.wallpaperIsVideo
                    fillMode: VideoOutput.PreserveAspectCrop
                }
            }

            Loader {
                id: blurLoader
                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                anchors.fill: wallpaper
                scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                // radius 100 means a 201-tap two-pass fullscreen Gaussian, and it
                // re-ran on every frame the desktop widgets repainted - which is
                // every frame of the lock animation, then once a second forever
                // after for the clock. The result is a still image, so bake it
                // once and let extraZoom scale the frozen copy, the same trick
                // WallpaperEffects uses for its own chain.
                sourceComponent: Item {
                    GaussianBlur {
                        id: lockBlur
                        anchors.fill: parent
                        source: wallpaperEffects.output
                        radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                        samples: radius * 2 + 1
                    }
                    ShaderEffectSource {
                        anchors.fill: parent
                        // Live again on the way out so the blur unwinds to 0 with
                        // the zoom instead of popping sharp at the end; radius 0
                        // is a one-tap pass, so that costs nothing.
                        live: lockBlurSettle.running || !GlobalStates.screenLocked
                        hideSource: true
                        sourceItem: lockBlur
                    }
                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                    // Long enough for the wallpaper chain underneath to be there.
                    Timer {
                        id: lockBlurSettle
                        interval: 400
                        running: true
                    }
                }
            }

            WallpaperEffects {
                id: wallpaperEffects
                anchors.fill: wallpaper
                wallpaper: wallpaper
                isVideo: bgRoot.wallpaperIsVideo
                // The lock screen runs its own blur; don't stack the two.
                visible: !blurLoader.active
            }
            }

            WidgetCanvas {
                id: widgetCanvas
                gridOverlayEnabled: Config.options.background.widgets.enableGrid ?? false
                scale: 1 - (defaultRatio - 1)
                Behavior on scale {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                // Positioned, not anchored to the wallpaper. Anchoring four sides
                // to a sibling that animates makes every parallax frame re-run
                // the anchor solver over this whole subtree on the main thread,
                // which is most of what a sidebar slide costs; left+right plus
                // an explicit width made it worse by over-constraining it.
                readonly property real parallaxFactor: Config.options.background.parallax.widgetsFactor
                x: -(wallpaper.effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                    - (wallpaper.effectiveValueX * 2 * bgRoot.movableXSpace) * (parallaxFactor - 1)
                y: -(wallpaper.effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
                    - (wallpaper.effectiveValueY * 2 * bgRoot.movableYSpace) * (parallaxFactor - 1)
                Behavior on x {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                width: wallpaper.width
                height: wallpaper.height
                states: State {
                    name: "centered"
                    when: GlobalStates.screenLocked || bgRoot.wallpaperSafetyTriggered
                    PropertyChanges {
                        target: widgetCanvas
                        width: widgetCanvas.parent.width
                        height: widgetCanvas.parent.height
                        x: 0
                        y: 0
                    }
                }

                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height,x,y"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                // Subject depth. The wallpaper's foreground subject, drawn back
                // over the widget plane so a clock can sit behind a shoulder -
                // the effect Iconify and the depth-wallpaper ROMs build on ML
                // Kit's subject segmentation.
                //
                // It lives inside the widget canvas so that one `z` per widget
                // decides which side of the subject that widget lands on. But
                // the canvas parallaxes at its own rate and squares up when the
                // screen locks, while the cutout has to stay welded to the
                // pixels it was cut from - so the canvas transform is undone
                // here and the layer tracks `wallpaper` exactly instead.
                Item {
                    id: subjectLayer
                    z: 1

                    // The maths below assumes both this item and the canvas
                    // scale about their centres, which is the default. Setting
                    // transformOrigin here silently slides the subject off the
                    // wallpaper.
                    readonly property real canvasScale: widgetCanvas.scale
                    width: wallpaper.width
                    height: wallpaper.height
                    scale: 1 / canvasScale
                    x: (wallpaper.x - widgetCanvas.x + (width - widgetCanvas.width) / 2) / canvasScale
                        + (widgetCanvas.width - width) / 2
                    y: (wallpaper.y - widgetCanvas.y + (height - widgetCanvas.height) / 2) / canvasScale
                        + (widgetCanvas.height - height) / 2

                    // A still cutout waits on its pixels; a video waits on the
                    // first frame reaching the output. Either way the fade runs
                    // over something real rather than over an empty item, which
                    // is why this is not the usual FadeLoader.
                    readonly property bool showing: bgRoot.depthVideo
                        ? (videoPlayer.playbackState === MediaPlayer.PlayingState && videoPlayer.hasVideo)
                        : (stillCutout.status === Image.Ready)

                    // Opacity is an effect, so both directions take the effects
                    // curve and neither may overshoot. They are not the same
                    // speed: this is a screen-sized surface arriving, which is
                    // slow effects, against fast effects on the way out.
                    visible: opacity > 0
                    opacity: showing ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: subjectLayer.showing
                                ? Appearance.animationCurves.expressiveSlowEffectsDuration
                                : Appearance.animation.elementMoveExit.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                        }
                    }

                    Image {
                        id: stillCutout
                        anchors.fill: parent
                        visible: !bgRoot.depthVideo
                        source: bgRoot.wallpaperSafetyTriggered ? "" : WallpaperSubject.source
                        // Same rect, same aspect and same fill rule as the
                        // wallpaper underneath: that is what registers the
                        // subject to the pixels it was cut from.
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // Read from disk every time the path is set. The cutout
                        // is rewritten in place whenever it is regenerated, and
                        // a cached pixmap would keep showing the previous
                        // wallpaper's subject forever.
                        cache: false
                        mipmap: false
                    }

                    // The video subject comes out of the same decoder as the
                    // wallpaper below it, so it is registered by construction -
                    // there is no clock for it to drift against.
                    Loader {
                        anchors.fill: parent
                        active: bgRoot.depthVideo
                        sourceComponent: SubjectMatte {
                            source: vidOutput
                        }
                    }
                }

                // Desktop widgets, placed from the registry.
                // Instances live in Config.options.background.activeWidgets.
                Repeater {
                    model: backgroundScope.widgetStateManager.model
                    delegate: WidgetDelegate {
                        // Behind the subject unless the widget's own menu says
                        // otherwise. Behind is the point of the effect.
                        z: aboveSubject ? 2 : 0
                        widgetListModel: backgroundScope.widgetStateManager.model
                        widgetSizes: backgroundScope.widgetStateManager.widgetSizes
                        widgetSizesVersion: backgroundScope.widgetStateManager.widgetSizesVersion
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                        lockAnimationActive: GlobalStates.lockAnimationActive
                    }
                }
            }
        }

        GlobalShortcut {
            name: "mediaModeToggle"
            description: "Toggles media mode on press"

            onPressed: {
                if (!monitor.focused && Config.options.background.mediaMode.togglePerMonitor) return
                mediaModeLoader.active = !mediaModeLoader.active
                LyricsService.mediaModeOpenCount += mediaModeLoader.active ? 1 : -1
            }
        }
        
        Loader {
            id: mediaModeLoader
            anchors.fill: parent
            active: false
            asynchronous: true
            sourceComponent: MediaMode {}
            opacity: status === Loader.Ready ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
}
