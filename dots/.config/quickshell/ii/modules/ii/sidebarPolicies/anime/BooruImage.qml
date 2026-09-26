import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import qs.modules.common.widgets
import QtQuick

// One tile of the grid. The image is the control: a click opens the response's
// menu at the pointer. No layer here -- BooruResponse rounds every tile with one
// mask over the whole grid, because a mask per tile inside a Repeater is the
// effect-in-a-delegate DESIGN.md 8 forbids.
MouseArea {
    id: root
    property var imageData
    property real rowHeight
    property bool manualDownload: false
    property string previewDownloadPath
    property bool menuShown: false
    // The API's own name for the file, with any `/` a decode produced flattened so
    // it cannot write outside the preview directory.
    readonly property string fileName: decodeURIComponent(imageData.file_url.substring(imageData.file_url.lastIndexOf('/') + 1)).replace(/\//g, "_")
    property int maxTagStringLineLength: 50

    signal menuRequested(real x, real y)

    width: rowHeight * imageData.aspect_ratio
    height: rowHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: mouse => root.menuRequested(mouse.x, mouse.y)

    ImageDownloaderProcess {
        running: root.manualDownload
        filePath: `${root.previewDownloadPath}/${root.fileName}`
        sourceUrl: root.imageData.preview_url ?? root.imageData.sample_url
        onDone: (path, width, height) => {
            imageObject.source = ""
            imageObject.source = path
            if (!root.imageData.width || !root.imageData.height) {
                root.imageData.width = width
                root.imageData.height = height
                root.imageData.aspect_ratio = width / height
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: !root.menuShown
        text: StringUtils.wordWrap(root.imageData.tags, root.maxTagStringLineLength)
    }

    Rectangle { // Loading: the tile at its final size until the image fades in
        anchors.fill: parent
        color: Appearance.colors.colLayer2
    }

    StyledImage {
        id: imageObject
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: root.imageData.preview_url

        // yande.re's image host resets about a third of its connections, and an
        // Image never retries on its own. Re-setting the same source is a no-op, so
        // clear it first.
        property int retries: 0
        onStatusChanged: {
            if (status !== Image.Error || retries >= 2)
                return;
            retries++;
            const url = source;
            source = "";
            source = url;
        }
    }

    StateOverlay {
        anchors.fill: parent
        hover: root.containsMouse
        press: root.pressed
        contentColor: Appearance.m3colors.m3onSurface
    }
}
