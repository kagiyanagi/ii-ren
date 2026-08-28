pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects

// Wallpaper post-processing: fluted glass -> blur -> ROM filter/adjustments.
// Each stage is a Loader, so a default config adds no render passes and the
// wallpaper keeps drawing itself.
//
// The result is a still image - it only changes when the wallpaper or a setting
// does. But a desktop widget animating repaints this window every frame, which
// would otherwise re-run the whole chain at the refresh rate; painful on an
// integrated GPU clocked down to a few hundred MHz on battery. So every texture
// in the chain freezes once things settle and the frozen copy is what reaches
// the screen, leaving one textured quad per frame however costly the chain was
// to produce. It is the same trick the ROMs use when they bake the effects into
// a Bitmap once and blit it forever after.
Item {
    id: root

    required property Item wallpaper
    readonly property var opt: Config.options.background.effects

    // The ROMs aim the effects at the home screen, the lock screen or both;
    // screenLocked is the equivalent here.
    readonly property bool targeted: root.opt.target === "both"
        || ((root.opt.target === "lock") === GlobalStates.screenLocked)

    // "glass" and "frosted" are the ROMs' two blur presets.
    readonly property int blurRadius: root.opt.blur.style === "glass" ? 50
        : root.opt.blur.style === "frosted" ? 9 : root.opt.blur.radius

    readonly property bool glassActive: root.targeted && root.opt.glass.enable
    readonly property bool blurActive: root.targeted && root.opt.blur.enable && root.blurRadius > 0
    readonly property bool filterActive: root.targeted && (root.opt.filter !== "none"
        || root.opt.saturation !== 100 || root.opt.dim > 0 || root.opt.vignette > 0 || root.opt.grain > 0)

    // The wallpaper hides itself once a stage renders it for us.
    readonly property bool takesOver: root.glassActive || root.blurActive || root.filterActive
    // What the lock screen's own blur should read.
    readonly property Item output: root.takesOver ? baked : root.wallpaper

    // Keep rendering only while something is actually changing. Walking the
    // option tree covers every knob, including ones added later, and QML tracks
    // the reads as binding dependencies.
    readonly property string digest: Config.options.background.wallpaperPath + JSON.stringify(root.opt)

    onDigestChanged: settle.restart()
    // Hiding the window (a fullscreen app, per background.hideWhenFullscreen)
    // can drop the frozen textures, so bake again on the way back.
    onVisibleChanged: if (root.visible) settle.restart()
    onTargetedChanged: settle.restart()
    onWidthChanged: settle.restart()
    onHeightChanged: settle.restart()

    Timer {
        id: settle
        // Long enough to ride out a wallpaper transition and a slider drag.
        interval: 2500
        running: true
    }

    Connections {
        // The wallpaper loads asynchronously, so bake again once it is there.
        target: root.wallpaper
        ignoreUnknownSignals: true
        function onStatusChanged() {
            settle.restart();
        }
    }

    Loader {
        id: glassLoader
        anchors.fill: parent
        active: root.glassActive
        sourceComponent: FlutedGlass {
            source: root.wallpaper
            live: settle.running
        }
    }

    // GaussianBlur reads its source through a texture of its own that is always
    // live, so hand it one that is already frozen instead of the raw stage.
    ShaderEffectSource {
        id: blurInput
        anchors.fill: parent
        visible: false
        live: settle.running
        hideSource: true
        sourceItem: root.blurActive ? (glassLoader.item ?? root.wallpaper) : null
    }

    Loader {
        id: blurLoader
        anchors.fill: parent
        active: root.blurActive
        sourceComponent: GaussianBlur {
            source: blurInput
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
            live: settle.running
        }
    }

    // The only thing that actually paints: a frozen copy of the last stage.
    ShaderEffectSource {
        id: baked
        anchors.fill: parent
        visible: root.takesOver
        live: settle.running
        hideSource: true
        sourceItem: root.takesOver
            ? (filterLoader.item ?? blurLoader.item ?? glassLoader.item)
            : null
    }
}
