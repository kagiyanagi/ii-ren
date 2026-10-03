pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    // Once the region is picked for a recording, or once the selector is on its
    // way out, the window is only something to look at. It has to stop taking
    // the pointer and the keyboard, or the screen is dead under it - and a click
    // during the fade out would start a second snip.
    readonly property bool passive: root.postPhase || !root.open
    WlrLayershell.keyboardFocus: root.passive ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
    mask: root.passive ? passthroughRegion : null
    exclusionMode: ExclusionMode.Ignore

    Region { id: passthroughRegion } // Empty: every click goes to whatever is underneath
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound, QrScan }
    enum SelectionMode { RectCorners, Circle }
    enum Phase { Select, Post }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property var phase: RegionSelection.Phase.Select
    readonly property bool postPhase: root.phase === RegionSelection.Phase.Post
    signal dismiss()

    // The request, which RegionSelector's Loader owns. Mapping is ours: the
    // window stays up until its fade out has played, then says so.
    property bool open: true
    signal fadedOut()
    onOpenChanged: {
        // Never shown, or nothing left to fade: done now.
        if (!root.open && (!root.visible || content.opacity === 0))
            root.fadedOut();
    }

    // The border belongs to the recording, so it goes when the recording does.
    // Nothing else can close it now that Escape no longer reaches this window.
    readonly property bool recordingActive: Persistent.states.screenRecord.active
    onRecordingActiveChanged: {
        if (root.postPhase && !root.recordingActive) root.dismiss();
    }
    onPostPhaseChanged: {
        if (root.postPhase) recordingStartTimeout.restart();
    }
    Timer {
        id: recordingStartTimeout
        interval: 3000
        // A recording that never started leaves no state change to react to, and
        // a border with no way to dismiss it would sit there for the session.
        onTriggered: if (root.postPhase && !root.recordingActive) root.dismiss()
    }
    // Emitted instead of running the command here when the result should get an
    // Android-style preview popup. This window is destroyed on dismiss, so the
    // process has to be owned by RegionSelector, which outlives it.
    signal previewSnip(var command, string previewPath)

    // Styles
    property string screenshotDir: Directories.screenshotTemp
    property color overlayColor: Appearance.colors.colScrim
    // The fixed roles: the same tones in light and dark, which is what a colour
    // drawn over an arbitrary frozen screen needs. Tone 90 for the selection,
    // tone 80 for the targets under it.
    property color selectionBorderColor: Appearance.m3colors.m3secondaryFixed
    property color windowBorderColor: Appearance.m3colors.m3secondaryFixedDim
    property color windowFillColor: ColorUtils.transparentize(windowBorderColor, 0.85)
    property color imageBorderColor: Appearance.m3colors.m3tertiaryFixedDim
    property color imageFillColor: ColorUtils.transparentize(imageBorderColor, 0.85)
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property real contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity

    // Vars for indicators
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        // Sort floating=true windows before others
        if (a.floating === b.floating) return 0;
        return a.floating ? -1 : 1;
    })
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.5

    // Screen & interaction vars
    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor.scale
    readonly property real monitorOffsetX: hyprlandMonitor.x
    readonly property real monitorOffsetY: hyprlandMonitor.y
    // What the shell reserves along the bottom edge - a pinned dock, a bottom
    // bar - which the frozen frame still shows there.
    readonly property real reservedBottom: HyprlandData.monitors.find(m => m.id === root.hyprlandMonitor.id)?.reserved?.[3] ?? 0
    property int activeWorkspaceId: hyprlandMonitor.activeWorkspace?.id ?? 0
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    // Latched once a press has travelled Qt's drag threshold, and only reset by
    // the next press. Until then it is a click.
    property bool draggedAway: false
    property bool dragging: false
    property list<point> points: []
    property var mouseButton: null
    property var imageRegions: []
    readonly property list<var> windowRegions: RegionFunctions.filterWindowRegionsByLayers(
        root.windows.filter(w => w.workspace.id === root.activeWorkspaceId),
        root.layerRegions
    ).map(window => {
        return {
            at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
            size: [window.size[0], window.size[1]],
            class: window.class,
            title: window.title,
        }
    })
    readonly property list<var> layerRegions: {
        // Off, or in circle mode, layers are not targets at all - and so they no
        // longer knock the windows they overlap out of the list either, which
        // they did while invisible: one 1x1 helper surface in a corner was
        // enough to make a fullscreen window unclickable.
        if (!root.enableLayerRegions) return [];
        const layersOfThisMonitor = root.layers[root.hyprlandMonitor.name]
        const topLayers = layersOfThisMonitor?.levels["2"]
        if (!topLayers) return [];
        const nonBarTopLayers = topLayers
            .filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":verticalBar") || layer.namespace.includes(":dock")))
            .map(layer => {
            return {
                at: [layer.x, layer.y],
                size: [layer.w, layer.h],
                namespace: layer.namespace,
            }
        })
        const offsetAdjustedLayers = nonBarTopLayers.map(layer => {
            return {
                at: [layer.at[0] - root.monitorOffsetX, layer.at[1] - root.monitorOffsetY],
                size: layer.size,
                namespace: layer.namespace,
            }
        });
        return offsetAdjustedLayers;
    }

    // Config
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    property bool enableWindowRegions: Config.options.regionSelector.targetRegions.windows && !isCircleSelection
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && !isCircleSelection
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content

    // Target
    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0
    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0)
    }

    function updateTargetedRegion(x, y) {
        const hit = region => region.at[0] <= x && x <= region.at[0] + region.size[0]
            && region.at[1] <= y && y <= region.at[1] + region.size[1];
        // Content first, then layers, then windows. Only what is drawn can be
        // taken: a target the config hides, or circle mode leaves out, must not
        // catch a click either.
        const target = (root.enableContentRegions ? root.imageRegions.find(hit) : undefined)
            ?? root.layerRegions.find(hit)
            ?? (root.enableWindowRegions ? root.windowRegions.find(hit) : undefined);
        root.targetedRegionX = target ? target.at[0] : -1;
        root.targetedRegionY = target ? target.at[1] : -1;
        root.targetedRegionWidth = target ? target.size[0] : 0;
        root.targetedRegionHeight = target ? target.size[1] : 0;
    }

    property real regionWidth: Math.abs(draggingX - dragStartX)
    property real regionHeight: Math.abs(draggingY - dragStartY)
    property real regionX: Math.min(dragStartX, draggingX)
    property real regionY: Math.min(dragStartY, draggingY)

    // Screenshot stuff
    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            if (root.enableContentRegions) imageDetectionProcess.running = true;
            root.preparationDone = !checkRecordingProc.running;
        }
    }
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool recordingShouldStop: false
    Process {
        id: checkRecordingProc
        running: isRecording
        command: ["pidof", "wf-recorder"]
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = !screenshotProc.running
            root.recordingShouldStop = (exitCode === 0);
        }
    }
    property bool preparationDone: false
    onPreparationDoneChanged: {
        if (!preparationDone) return;
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached([Directories.recordScriptPath, "--stop"]);
            root.dismiss();
            return;
        }
        root.visible = true;
    }

    Process {
        id: imageDetectionProcess
        command: ["bash", "-c", `${Directories.scriptPath}/images/find-regions-venv.sh `
            + `--hyprctl `
            + `--image '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' `
            + `--max-width ${Math.round(root.screen.width * root.falsePositivePreventionRatio)} `
            + `--max-height ${Math.round(root.screen.height * root.falsePositivePreventionRatio)} `]
        stdout: StdioCollector {
            id: imageDimensionCollector
            onStreamFinished: {
                let found;
                try {
                    found = JSON.parse(imageDimensionCollector.text);
                } catch (e) {
                    return; // no venv or the script failed: windows and layers still snap
                }
                imageRegions = RegionFunctions.filterImageRegions(found, root.windowRegions);
            }
        }
    }

    // Execution after selection. The region is only written here, once it is
    // known to be worth taking: for a recording it is the border that stays.
    function snip(x, y, width, height) {
        // Clamped by intersection, not by sliding it back in: a padded window
        // target at a screen edge hangs off it, and moving it would take a strip
        // of whatever is beside it.
        const x1 = Math.max(0, x);
        const y1 = Math.max(0, y);
        const w = Math.min(root.screen.width, x + width) - x1;
        const h = Math.min(root.screen.height, y + height) - y1;
        // Nothing selected, such as a drag along one axis. Stay open - the frozen
        // frame cannot be taken again - rather than hand magick a zero size,
        // which it reads as "everything from here to the corner".
        if (w <= 0 || h <= 0)
            return;
        root.regionX = x1;
        root.regionY = y1;
        root.regionWidth = w;
        root.regionHeight = h;

        // The right button annotates instead of copying. A local, not
        // root.action: that is the guide's, which would reopen its hint during
        // the fade out.
        let action = root.action;
        if (action === RegionSelection.SnipAction.Copy || action === RegionSelection.SnipAction.Edit)
            action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;

        const screenshotDir = Config.options.screenSnip.savePath;
        // SnipAction and ScreenshotAction.Action share the same order.
        // Preview only in clipboard-only mode: with a save path set the crop is
        // already on disk under a name of the user's choosing, and a popup
        // offering to save it again would just make a second copy.
        const previewPath = (action === ScreenshotAction.Action.Copy && screenshotDir === ""
            && Config.options.screenSnip.showPreview)
            ? `${root.screenshotDir}/snip-${Date.now()}.png` : "";
        const command = ScreenshotAction.getCommand(
            x1 * root.monitorScale, //
            y1 * root.monitorScale, //
            w * root.monitorScale, //
            h * root.monitorScale, //
            root.screenshotPath, //
            action, //
            screenshotDir, //
            previewPath
        )
        if (previewPath !== "") root.previewSnip(command, previewPath);
        else Quickshell.execDetached(command);
        if (root.isRecording) {
            root.phase = RegionSelection.Phase.Post
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        } else {
            root.dismiss();
        }
    }

    Item {
        id: content
        anchors.fill: parent

        // In on the scrim's spec (DESIGN.md 6.2), out at the fast effects one.
        // Assigned inside the binding that drives the fade: a Behavior bakes its
        // spec at the instant of the write, so a spec bound on its own is a frame
        // late and the exit runs on the enter's curve (2.9).
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

        ScreencopyView { // For freezing
            anchors.fill: parent
            live: false
            captureSource: root.screen
            visible: root.phase === RegionSelection.Phase.Select

            focus: root.visible
            Keys.onPressed: (event) => { // Esc to close
                if (event.key === Qt.Key_Escape) {
                    root.dismiss();
                }
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            enabled: !root.passive
            cursorShape: Qt.CrossCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true

            // Controls
            onPressed: (mouse) => {
                root.dragStartX = mouse.x;
                root.dragStartY = mouse.y;
                root.draggingX = mouse.x;
                root.draggingY = mouse.y;
                root.draggedAway = false;
                root.points = [];
                root.dragging = true;
                root.mouseButton = mouse.button;
                cursorGuide.hideDescription();
            }
            onReleased: (mouse) => {
                root.dragging = false;
                // A click takes the target under it, if there is one. On bare
                // screen it does nothing and the selector stays.
                if (!root.draggedAway) {
                    if (!root.targetedRegionValid())
                        return;
                    const padding = Config.options.regionSelector.targetRegions.selectionPadding; // Make borders not cut off n stuff
                    root.snip(root.targetedRegionX - padding, root.targetedRegionY - padding,
                        root.targetedRegionWidth + padding * 2, root.targetedRegionHeight + padding * 2);
                    return;
                }
                if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                    const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                    const xs = root.points.map(p => p.x);
                    const ys = root.points.map(p => p.y);
                    const minX = Math.min(...xs);
                    const minY = Math.min(...ys);
                    root.snip(minX - padding, minY - padding,
                        Math.max(...xs) - minX + padding * 2, Math.max(...ys) - minY + padding * 2);
                    return;
                }
                root.snip(root.regionX, root.regionY, root.regionWidth, root.regionHeight);
            }
            onPositionChanged: (mouse) => {
                root.updateTargetedRegion(mouse.x, mouse.y);
                if (!root.dragging) return;
                root.draggingX = mouse.x;
                root.draggingY = mouse.y;
                root.points.push({ x: mouse.x, y: mouse.y });
                // Qt's own drag threshold: a click that wobbles a pixel is still a
                // click, and still takes the window under it.
                const threshold = Qt.styleHints.startDragDistance;
                if (Math.abs(mouse.x - root.dragStartX) >= threshold || Math.abs(mouse.y - root.dragStartY) >= threshold)
                    root.draggedAway = true;
            }

            Loader {
                z: 2
                anchors.fill: parent
                active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
                sourceComponent: RectCornersSelectionDetails {
                    regionX: root.regionX
                    regionY: root.regionY
                    regionWidth: root.regionWidth
                    regionHeight: root.regionHeight
                    mouseX: mouseArea.mouseX
                    mouseY: mouseArea.mouseY
                    color: root.selectionBorderColor
                    overlayColor: root.overlayColor
                    showSelection: root.draggedAway || root.postPhase
                    borderOnly: root.postPhase
                }
            }

            Loader {
                z: 2
                anchors.fill: parent
                active: root.selectionMode === RegionSelection.SelectionMode.Circle
                sourceComponent: CircleSelectionDetails {
                    color: root.selectionBorderColor
                    overlayColor: root.overlayColor
                    points: root.points
                }
            }

            // The thing to the bottom-right with an icon
            CursorGuide {
                id: cursorGuide
                z: 9999
                visible: root.phase === RegionSelection.Phase.Select
                x: root.dragging ? root.regionX + root.regionWidth : mouseArea.mouseX
                y: root.dragging ? root.regionY + root.regionHeight : mouseArea.mouseY
                action: root.action
            }

            // Window regions
            Repeater {
                model: ScriptModel {
                    values: {
                        if (root.phase === RegionSelection.Phase.Select && root.enableWindowRegions) {
                            return root.windowRegions
                        } else {
                            return []
                        }
                    }
                }
                delegate: TargetRegion {
                    z: 2
                    required property var modelData
                    clientDimensions: modelData
                    showIcon: true
                    targeted: !root.draggedAway && //
                        (root.targetedRegionX === modelData.at[0]  //
                        && root.targetedRegionY === modelData.at[1] //
                        && root.targetedRegionWidth === modelData.size[0] //
                        && root.targetedRegionHeight === modelData.size[1])

                    restingOpacity: root.targetRegionOpacity
                    hidden: root.draggedAway
                    borderColor: root.windowBorderColor
                    fillColor: targeted ? root.windowFillColor : "transparent"
                    text: `${modelData.class}`
                    radius: Appearance.rounding.windowRounding
                }
            }

            // Layer regions
            Repeater {
                model: ScriptModel {
                    values: {
                        if (root.phase === RegionSelection.Phase.Select && root.enableLayerRegions) {
                            return root.layerRegions
                        } else {
                            return []
                        }
                    }
                }
                delegate: TargetRegion {
                    z: 3
                    required property var modelData
                    clientDimensions: modelData
                    targeted: !root.draggedAway &&
                        (root.targetedRegionX === modelData.at[0]
                        && root.targetedRegionY === modelData.at[1]
                        && root.targetedRegionWidth === modelData.size[0]
                        && root.targetedRegionHeight === modelData.size[1])

                    restingOpacity: root.targetRegionOpacity
                    hidden: root.draggedAway
                    borderColor: root.windowBorderColor
                    fillColor: targeted ? root.windowFillColor : "transparent"
                    text: `${modelData.namespace}`
                    radius: Appearance.rounding.windowRounding
                }
            }

            // Content regions
            Repeater {
                model: ScriptModel {
                    values: {
                        if (root.phase === RegionSelection.Phase.Select && root.enableContentRegions) {
                            return root.imageRegions
                        } else {
                            return []
                        }
                    }
                }
                delegate: TargetRegion {
                    z: 4
                    required property var modelData
                    clientDimensions: modelData
                    targeted: !root.draggedAway &&
                        (root.targetedRegionX === modelData.at[0]
                        && root.targetedRegionY === modelData.at[1]
                        && root.targetedRegionWidth === modelData.size[0]
                        && root.targetedRegionHeight === modelData.size[1])

                    restingOpacity: root.contentRegionOpacity
                    hidden: root.draggedAway
                    borderColor: root.imageBorderColor
                    fillColor: targeted ? root.imageFillColor : "transparent"
                    text: Translation.tr("Content region")
                }
            }

            // Controls
            Row {
                id: regionSelectionControls
                z: 10
                visible: root.phase === RegionSelection.Phase.Select
                spacing: 8
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    // Rises from below the screen edge (DESIGN.md 2.6) to sit clear
                    // of the band the shell reserves there: the frozen frame still
                    // shows the dock in it, and the toolbar read as part of it.
                    bottomMargin: root.visible ? root.reservedBottom + 8 : -regionSelectionControls.height
                }
                Behavior on anchors.bottomMargin {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                OptionsToolbar {
                    selectionMode: root.selectionMode
                    onSelectionModeRequested: mode => root.selectionMode = mode
                }
                ToolbarPairedFab {
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "close"
                    onClicked: root.dismiss();
                    StyledToolTip {
                        text: Translation.tr("Close")
                    }
                }
            }
        }
    }
}
