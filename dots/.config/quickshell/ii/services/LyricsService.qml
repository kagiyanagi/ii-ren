pragma Singleton

import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.utils
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property bool lyricsEnabled: Config.options.lyricsService.enable
    readonly property bool geniusEnabled: Config.options.lyricsService.enableGenius
    readonly property bool lrclibEnabled: Config.options.lyricsService.enableLrclib
    
    property bool isInitialized: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    readonly property bool effectiveLrclibEnabled: lyricsEnabled && lrclibEnabled && isInitialized && (root.activePlayer?.trackTitle?.length > 0) && (root.activePlayer?.trackArtist?.length > 0)
    readonly property bool effectiveGeniusEnabled: lyricsEnabled && geniusEnabled && isInitialized

    // Off means off: the cache would otherwise keep serving the songs already fetched
    readonly property var syncedLines: lyricsEnabled && lrclibEnabled ? lrclib.lines : []
    readonly property alias currentIndex: lrclib.currentIndex
    readonly property string statusText: lrclib.displayText
    readonly property bool hasSyncedLines: syncedLines.length > 0

    readonly property bool geniusHasLyrics: effectiveGeniusEnabled && genius.lyrics !== ""
    readonly property string plainLyrics: geniusHasLyrics ? genius.lyrics : ""

    // Function to initialize the lyrics service, to prevent unnecessary API calls when no lyrics UI is being use
    // Its being called in LyricsStatic and LyricsScroller files
    function initiliazeLyrics() {
        root.isInitialized = true
    }

    // https://quickshell.org/docs/master/types/Quickshell.Services.Mpris/MprisPlayer/#position
    Timer {
        running: root.activePlayer?.playbackState == MprisPlaybackState.Playing && root.hasSyncedLines && root.isInitialized
        interval: 250
        repeat: true
        onTriggered: root.activePlayer.positionChanged()
    }

    LrclibLyrics {
        id: lrclib
        enabled: effectiveLrclibEnabled
        title: root.activePlayer?.trackTitle ?? ""
        artist: root.activePlayer?.trackArtist ?? ""
        duration: root.activePlayer?.length ?? 0
        position: root.activePlayer?.position ?? 0
    }

    // Fetches once per track, and only for one that names an artist: see GeniusLyrics
    GeniusLyrics {
        id: genius
        enabled: root.effectiveGeniusEnabled
        artist: root.activePlayer?.trackArtist ?? ""
        title: root.activePlayer?.trackTitle ?? ""
    }
}
