pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common

/**
 * The one cover art cache. ColorQuantizer and the blurs need a local file, so every
 * player's remote art is fetched once, in the background, into Directories.coverArt.
 * Widgets only look it up: one download per track instead of one per widget, and no
 * widget can read a file another is still writing.
 */
Singleton {
    id: root

    // remote url -> file:// url on disk, or "" if the fetch failed
    property var files: ({})

    // "" until remote art is on disk; local art passes through, bare paths as file urls.
    function source(url): string {
        if (!url) return "";
        if (root.isRemote(url)) return root.files[url] ?? "";
        return url.startsWith("/") ? `file://${url}` : url;
    }

    function isRemote(url): bool {
        return /^https?:\/\//.test(url);
    }

    readonly property list<string> wanted: Mpris.players.values
        .map(player => MprisController.artUrlFor(player))
        .filter(url => root.isRemote(url))
    onWantedChanged: {
        // A failed fetch gets another try on the next track change, never a retry loop.
        if (Object.values(root.files).includes(""))
            root.files = Object.fromEntries(Object.entries(root.files).filter(([, file]) => file));
        root.next();
    }

    function next() {
        if (fetcher.running) return;
        const url = root.wanted.find(url => !(url in root.files));
        if (!url) return;
        fetcher.url = url;
        fetcher.path = `${Directories.coverArt}/${Qt.md5(url)}`;
        fetcher.running = true;
    }

    Process {
        id: fetcher
        property string url
        property string path
        // Arguments, never interpolated: art urls come from web pages through MPRIS.
        command: ["sh", "-c", '[ -s "$1" ] || { mkdir -p "${1%/*}" && curl -4 -fsSL --proto =http,https --max-time 20 -o "$1.tmp" --url "$2" && mv -f "$1.tmp" "$1"; }',
            "sh", path, url]
        onExited: exitCode => {
            root.files = Object.assign({}, root.files, { [fetcher.url]: exitCode === 0 ? `file://${fetcher.path}` : "" });
            root.next();
        }
    }
}
