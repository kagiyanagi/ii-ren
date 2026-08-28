pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects

// Wallpaper post-processing: fluted glass -> blur -> ROM filter/adjustments.
// Each stage is a Loader, so a default config adds no render passes and the
// wallpaper keeps drawing itself.
Item {
    id: root

    required property Item wallpaper
    readonly property var opt: Config.options.background.effects

    // The ROMs aim the effects at the home screen, the lock screen or both;
    // screenLocked is the equivalent here.
    readonly property bool onTarget: root.opt.target === "both"
        || ((root.opt.target === "lock") === GlobalStates.screenLocked)

    // "glass" and "frosted" are the ROMs' two blur presets.
    readonly property int blurRadius: root.opt.blur.style === "glass" ? 50
        : root.opt.blur.style === "frosted" ? 9 : root.opt.blur.radius

    readonly property bool glassActive: root.onTarget && root.opt.glass.enable
    readonly property bool blurActive: root.onTarget && root.opt.blur.enable && root.blurRadius > 0
    readonly property bool filterActive: root.onTarget && (root.opt.filter !== "none"
        || root.opt.saturation !== 100 || root.opt.dim > 0 || root.opt.vignette > 0 || root.opt.grain > 0)

    // The wallpaper hides itself once a stage renders it for us.
    readonly property bool takesOver: root.glassActive || root.blurActive || root.filterActive
    // Last active stage, for the lock screen's own blur to sit on top of. Each
    // stage stays visible and is simply painted over by the next, so nothing
    // here depends on an invisible item still being rendered into a texture -
    // grabToImage, for one, does not do that.
    readonly property Item output: filterLoader.item ?? blurLoader.item ?? glassLoader.item ?? root.wallpaper

    Loader {
        id: glassLoader
        anchors.fill: parent
        active: root.glassActive
        sourceComponent: FlutedGlass {
            source: root.wallpaper
        }
    }

    Loader {
        id: blurLoader
        anchors.fill: parent
        active: root.blurActive
        sourceComponent: GaussianBlur {
            source: glassLoader.item ?? root.wallpaper
            radius: root.blurRadius
            samples: Math.min(1 + radius * 2, 201)
        }
    }

    Loader {
        id: filterLoader
        anchors.fill: parent
        active: root.filterActive
        sourceComponent: WallpaperFilter {
            source: blurLoader.item ?? glassLoader.item ?? root.wallpaper
        }
    }
}
