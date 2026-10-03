import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell.Io
import Quickshell.Widgets

IconImage {
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

    Process {
        id: faviconDownloadProcess
        running: false
        // Arguments, never interpolated into the script.
        command: ["sh", "-c", '[ -f "$1" ] || curl -sfL --proto =https -A "$3" -o "$1" --url "$2"',
            "sh", root.faviconFilePath, root.faviconUrl, root.downloadUserAgent]
        onExited: (exitCode, exitStatus) => {
            root.urlToLoad = root.faviconFilePath
        }
    }

    Component.onCompleted: {
        faviconDownloadProcess.running = true
    }

    source: Qt.resolvedUrl(root.urlToLoad)
    implicitSize: root.size

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.implicitSize
            height: root.implicitSize
            radius: Appearance.rounding.full
        }
    }
}