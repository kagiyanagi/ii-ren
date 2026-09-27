import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell

/**
 * The contextual toolbar for the tile that was right-clicked. It keeps the last
 * tile it was given while it leaves, so its buttons do not change under the exit.
 */
Toolbar {
    id: imageToolbar

    readonly property bool shown: wallpaperSelectorContent.moreOptionsModelData !== null
    property var modelData: null

    // Out of the corner it is pinned to (DESIGN.md 2.6), on the ArrowPopup recipe.
    transformOrigin: Item.BottomRight
    scale: Appearance.animationCurves.arrowPopupScale
    opacity: 0
    visible: opacity > 0
    onShownChanged: shown ? motion.open() : motion.close()
    ArrowPopupMotion {
        id: motion
        target: imageToolbar
    }
    Connections {
        target: wallpaperSelectorContent
        function onMoreOptionsModelDataChanged() {
            if (wallpaperSelectorContent.moreOptionsModelData) imageToolbar.modelData = wallpaperSelectorContent.moreOptionsModelData;
        }
    }

    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        property string wallhavenId: wallpaperSelectorContent.getWallhavenId(modelData?.fileUrl) ?? ""
        visible: !!wallpaperSelectorContent.browserService && wallhavenId.length > 0
        onClicked: {
            wallpaperSelectorContent.searchForSimilarImages(wallhavenId);
        }
        text: "image_search"
        StyledToolTip {
            text: Translation.tr("Search for similar images")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: !wallpaperSelectorContent.browserMode
        onClicked: {
            wallpaperSelectorContent.toggleFavourite(modelData.filePath);
        }
        text: "favorite"
        iconFill: Persistent.states.wallpaper.favourites.includes(modelData?.filePath) ?? false
        StyledToolTip {
            text: Translation.tr("Favourite this wallpaper")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        onClicked: wallpaperSelectorContent.activate(modelData)
        text: "wallpaper"
        StyledToolTip {
            text: Translation.tr("Set as wallpaper")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: wallpaperSelectorContent.browserMode
        // Into the folder wallpapers are kept in. The URL and name come from a remote
        // API, so they are arguments, never part of the script.
        onClicked: {
            const url = modelData.fileUrl;
            Quickshell.execDetached(["bash", "-c",
                'mkdir -p "$1" && curl -fsSL "$2" -o "$1/$3" && notify-send -a Shell "$4" "$1/$3"',
                "_", FileUtils.trimFileProtocol(Wallpapers.defaultFolder.toString()), url, url.split("/").pop(), Translation.tr("Download complete")
            ]);
        }
        text: "download"
        StyledToolTip {
            text: Translation.tr("Download")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: (modelData?.fileUrl ?? "").length > 0
        onClicked: {
            Qt.openUrlExternally(modelData?.fileUrl)
        }
        text: "link"
        StyledToolTip {
            text: Translation.tr("Open file link")
        }
    }
}