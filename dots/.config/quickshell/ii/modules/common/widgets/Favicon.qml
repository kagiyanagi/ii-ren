import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import QtQuick
import Quickshell.Io
import Quickshell.Widgets

// Search results draw one per link, so this sits inside a delegate: rounded with
// the scene graph's clip (ClippingRectangle), not a layer and an OpacityMask pass
// per icon (DESIGN.md effect budget, law 8).
ClippingRectangle {
    id: root
    property string url
    property string displayText

    property real size: 32
    property string downloadUserAgent: Config.options?.networking.userAgent ?? ""
    property string faviconDownloadPath: Directories.favicons
    // Search results and model-written citation titles pick this, and it ends up in a
    // url and a file name: keep it to hostname characters.
    property string domainName: ((url.includes("vertexaisearch") ? displayText : StringUtils.getDomain(url)) ?? "").replace(/[^\w.-]/g, "")
    property string faviconUrl: `https://www.google.com/s2/favicons?domain=${domainName}&sz=32`
    property string fileName: `${domainName}.ico`
    property string faviconFilePath: `${faviconDownloadPath}/${fileName}`
    property string urlToLoad

    implicitWidth: root.size
    implicitHeight: root.size
    radius: Appearance.rounding.full
    color: "transparent"

    // A cached icon is used as is. Every icon used to start a shell to test for the
    // file, and a failed download left a path to a file that was never written.
    FileView {
        path: root.domainName.length > 0 ? root.faviconFilePath : ""
        printErrors: false
        onLoaded: root.urlToLoad = root.faviconFilePath
        onLoadFailed: faviconDownloadProcess.running = true
    }

    Process {
        id: faviconDownloadProcess
        // Arguments, never interpolated into the script.
        command: ["sh", "-c", 'curl -sfL --proto =https -A "$3" -o "$1" --url "$2"',
            "sh", root.faviconFilePath, root.faviconUrl, root.downloadUserAgent]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.urlToLoad = root.faviconFilePath;
        }
    }

    IconImage {
        id: icon
        anchors.fill: parent
        implicitSize: root.size
        source: root.urlToLoad.length > 0 ? Qt.resolvedUrl(root.urlToLoad) : ""
        visible: status === Image.Ready
    }

    // Offline, or a site with no icon.
    MaterialSymbol {
        anchors.centerIn: parent
        visible: icon.status !== Image.Ready
        text: "public"
        iconSize: root.size * 0.8
        color: Appearance.colors.colSubtext
    }
}
