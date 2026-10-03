import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property string thumbnailPath: {
        if (sourcePath.length == 0) return "";
        // The md5 of the file uri exactly as GLib writes it, which is what thumbgen.py and
        // file managers name thumbnails by: encodeURIComponent, minus what GLib leaves alone.
        // Qt.resolvedUrl is no help here, it half-encodes (a % but not a space).
        const parts = FileUtils.trimFileProtocol(sourcePath).split("/")
            .map(part => encodeURIComponent(part).replace(/%(24|26|2B|2C|3D|3A|40)/g, decodeURIComponent));
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${Qt.md5(`file://${parts.join("/")}`)}.png`;
    }
    source: thumbnailPath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onSourceSizeChanged: {
        if (!root.generateThumbnail) return;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }
    Process {
        id: thumbnailGeneration
        // Arguments, never interpolated: a file name can hold ' and $(.
        command: ["bash", "-c", '[ -f "$1" ] && exit 0 || { "$2" -f "$3" -s "$4" && exit 1; }', "_",
            FileUtils.trimFileProtocol(root.thumbnailPath),
            FileUtils.trimFileProtocol(Directories.scriptPath) + "/thumbnails/generate-thumbnails-magick.sh",
            FileUtils.trimFileProtocol(root.sourcePath), root.thumbnailSizeName]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) { // Force reload if thumbnail had to be generated
                root.source = "";
                root.source = root.thumbnailPath; // Force reload
            }
        }
    }
}
