import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects

// Live preview of the current wallpaper through one effect configuration, in
// the same order the desktop applies them. `filter` and `glass` are override
// maps handed to the shader wrappers; a null `glass` skips that pass, so a
// filter card previews only its filter.
Item {
    id: root

    property var filter: ({})
    property var glass: null
    property real blurRadius: 0 // in full-screen px, scaled down below
    property real thumbWidth: 360

    readonly property string wallpaper: {
        const path = Config.options.background.wallpaperPath ?? "";
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path) ? Config.options.background.thumbnailPath : path;
    }

    Image {
        id: thumb
        anchors.fill: parent
        visible: false
        source: root.wallpaper
        sourceSize.width: root.thumbWidth
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }

    Loader {
        id: glassStage
        anchors.fill: parent
        active: root.glass !== null
        sourceComponent: FlutedGlass {
            source: thumb
            preset: root.glass ?? ({})
        }
    }

    Loader {
        id: blurStage
        anchors.fill: parent
        active: root.blurRadius > 0
        sourceComponent: GaussianBlur {
            source: glassStage.item ?? thumb
            // The radius is in screen pixels, so scale it to the thumbnail or
            // every preview looks far blurrier than the real thing.
            radius: Math.max(1, Math.round(root.blurRadius * root.width / Math.max(1, Screen.width)))
            samples: radius * 2 + 1
        }
    }

    WallpaperFilter {
        anchors.fill: parent
        source: blurStage.item ?? glassStage.item ?? thumb
        preset: root.filter
    }

    // Nothing to preview until a wallpaper is set.
    StyledText {
        anchors.centerIn: parent
        visible: root.wallpaper.length === 0
        text: "wallpaper"
        color: Appearance.colors.colSubtext
    }
}
