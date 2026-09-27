pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.modules.waffle.screenSnip

Scope {
    id: root

    function dismiss() {
        GlobalStates.regionSelectorOpen = false;
    }

    property var mediaType: WRegionSelectionPanel.MediaType.Image
    property var imageAction: WRegionSelectionPanel.ImageAction.Copy
    property var videoAction: WRegionSelectionPanel.VideoAction.Record
    property var selectionMode: WRegionSelectionPanel.SelectionMode.Rect

    Variants {
        model: Quickshell.screens

        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData

            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(regionSelectorLoader.modelData)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
            readonly property bool wanted: GlobalStates.regionSelectorOpen && (!Config.options.regionSelector.showOnlyOnFocusedMonitor || monitorIsFocused)

            property bool rendered: false
            onWantedChanged: {
                if (!regionSelectorLoader.wanted)
                    return;
                regionSelectorLoader.rendered = false;
                regionSelectorLoader.rendered = true;
            }
            active: regionSelectorLoader.rendered

            sourceComponent: WRegionSelectionPanel {
                screen: regionSelectorLoader.modelData
                open: regionSelectorLoader.wanted
                onFadedOut: regionSelectorLoader.rendered = false
                onDismiss: root.dismiss()

                mediaType: root.mediaType
                imageAction: root.imageAction
                videoAction: root.videoAction
                selectionMode: root.selectionMode

                onMediaTypeChanged: root.mediaType = mediaType
                onImageActionChanged: root.imageAction = imageAction
                onVideoActionChanged: root.videoAction = videoAction
                onSelectionModeChanged: root.selectionMode = selectionMode
            }
        }
    }

    function screenshot() {
        root.mediaType = WRegionSelectionPanel.MediaType.Image;
        root.imageAction = WRegionSelectionPanel.ImageAction.Copy;
        GlobalStates.regionSelectorOpen = true;
    }

    function ocr() {
        root.mediaType = WRegionSelectionPanel.MediaType.Image;
        root.imageAction = WRegionSelectionPanel.ImageAction.CharRecognition;
        GlobalStates.regionSelectorOpen = true;
    }

    function qrScan() {
        root.mediaType = WRegionSelectionPanel.MediaType.Image;
        root.imageAction = WRegionSelectionPanel.ImageAction.QrScan;
        GlobalStates.regionSelectorOpen = true;
    }

    function record() {
        if (Persistent.states.screenRecord.active) {
            Quickshell.execDetached([Directories.recordScriptPath, "--stop"]);
            return;
        }
        root.mediaType = WRegionSelectionPanel.MediaType.Video;
        root.videoAction = WRegionSelectionPanel.VideoAction.Record;
        GlobalStates.regionSelectorOpen = true;
    }

    function recordWithSound() {
        if (Persistent.states.screenRecord.active) {
            Quickshell.execDetached([Directories.recordScriptPath, "--stop"]);
            return;
        }
        root.mediaType = WRegionSelectionPanel.MediaType.Video;
        root.videoAction = WRegionSelectionPanel.VideoAction.RecordWithSound;
        GlobalStates.regionSelectorOpen = true;
    }

    function search() {
        root.mediaType = WRegionSelectionPanel.MediaType.Image;
        root.imageAction = WRegionSelectionPanel.ImageAction.Search;
        GlobalStates.regionSelectorOpen = true;
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot();
        }
        function ocr() {
            root.ocr();
        }
        function qrScan() {
            root.qrScan();
        }
        function record() {
            root.record();
        }
        function recordWithSound() {
            root.recordWithSound();
        }
        function search() {
            root.search();
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
        name: "regionQrScan"
        description: "Scans a QR code in the selected region"
        onPressed: root.qrScan()
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
