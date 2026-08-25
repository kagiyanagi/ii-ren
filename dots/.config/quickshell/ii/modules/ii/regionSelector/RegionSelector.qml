pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners

    Variants {
        model: Quickshell.screens
        
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData

            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(regionSelectorLoader.modelData)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            active: GlobalStates.regionSelectorOpen && (!Config.options.regionSelector.showOnlyOnFocusedMonitor || monitorIsFocused)

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                onPreviewSnip: (command, previewPath) => root.runPreviewSnip(command, previewPath)
                action: root.action
                selectionMode: root.selectionMode
            }
        }
    }

    // Android-style preview of the shot that was just copied. The RegionSelection
    // window is destroyed the moment the region is picked, so the crop runs here
    // instead - this Scope lives for the whole session.
    property string previewPath: ""
    property bool previewShown: false

    function runPreviewSnip(command, path) {
        root.previewShown = false;
        // previewPath is deliberately not set yet. The crop does not exist until
        // the command finishes, and an Image pointed at a missing file fails once
        // and never retries - which is an empty card with no error anywhere.
        snipProc.targetPath = path;
        snipProc.running = false;
        snipProc.command = command;
        snipProc.running = true;
    }

    // previewPath is deliberately left alone: the card is still sliding out and
    // would go blank if its image source were cleared underneath it. The next
    // screenshot overwrites it.
    function dismissPreview(deleteFile) {
        if (deleteFile && root.previewPath !== "")
            Quickshell.execDetached(["rm", "-f", root.previewPath]);
        root.previewShown = false;
    }

    function savePreview() {
        const dir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath
            : `${FileUtils.trimFileProtocol(Directories.pictures)}/Screenshots`;
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p '${StringUtils.shellSingleQuoteEscape(dir)}' && `
            + `mv '${StringUtils.shellSingleQuoteEscape(root.previewPath)}' `
            + `'${StringUtils.shellSingleQuoteEscape(dir)}'/screenshot-"$(date '+%Y-%m-%d_%H.%M.%S')".png`]);
        root.dismissPreview(false);
    }

    function editPreview() {
        const annotator = Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy";
        Quickshell.execDetached([annotator, "-f", root.previewPath]);
        // The annotator owns the file now, including whether it gets saved.
        root.dismissPreview(false);
    }

    Process {
        id: snipProc
        property string targetPath: ""
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("[Region Selector] Snip failed with exit code", exitCode);
                return;
            }
            root.previewPath = snipProc.targetPath;
            root.previewShown = true;
        }
    }

    ScreenshotPreviewPopup {
        path: root.previewPath
        shown: root.previewShown
        onSave: root.savePreview()
        onEdit: root.editPreview()
        onDiscard: root.dismissPreview(true)
    }

    function screenshot() {
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        if (Config.options.search.imageSearch.useCircleSelection) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        GlobalStates.regionSelectorOpen = true
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function record() {
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        // If already open then re-trigger to stop recording
        if (GlobalStates.regionSelectorOpen) GlobalStates.regionSelectorOpen = false
        GlobalStates.regionSelectorOpen = true
    }

    function recordWithSound() {
        root.action = RegionSelection.SnipAction.RecordWithSound
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        // If already open then re-trigger to stop recording
        if (GlobalStates.regionSelectorOpen) GlobalStates.regionSelectorOpen = false
        GlobalStates.regionSelectorOpen = true
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
}
