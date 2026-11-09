pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import qs.modules.common

/**
 * Plain lyrics from Genius for one track, through scripts/lyrics/genius_lyrics.py, while
 * `enabled`. `lyrics` is "" while a fetch is out and when Genius has nothing for the track.
 */
Item {
    id: root
    visible: false

    property string artist: ""
    property string title: ""
    property string lyrics: ""

    readonly property string apiKey: KeyringStorage.keyringData?.apiKeys?.genius ?? ""
    // Both names are required: a browser tab playing a web page has a title and no
    // artist, and Genius's search answers any title at all with some song.
    readonly property string fetchKey: root.enabled && root.apiKey && root.artist && root.title
        ? JSON.stringify([root.artist, root.title]) : ""

    onFetchKeyChanged: {
        root.lyrics = "";
        if (root.fetchKey)
            fetchDebounce.restart();
        else
            fetchDebounce.stop();
    }

    // Players send a new track's title and artist as separate changes; one fetch for both.
    Timer {
        id: fetchDebounce
        interval: 250
        onTriggered: fetcher.refresh()
    }

    RefreshProcess {
        id: fetcher
        command: ["python3", Directories.geniusLyricsScriptPath, root.artist, root.title]
        // Not an argument: every account on the machine can read a command line.
        environment: ({ "GENIUS_API_KEY": root.apiKey })
        stdout: StdioCollector {
            onStreamFinished: {
                let answer;
                try {
                    answer = JSON.parse(this.text);
                } catch (e) {
                    return; // the script said why on stderr
                }
                // A fetch for the track before this one can still land after it.
                if (JSON.stringify([answer.artist, answer.title]) === root.fetchKey)
                    root.lyrics = answer.lyrics ?? "";
            }
        }
    }
}
