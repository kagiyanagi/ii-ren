pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects

// Wallpaper post-processing: blur -> fluted glass -> ROM filter/adjustments.
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
    // Desktop and lock screen each pick their own group of settings; fluted
    // glass targets separately from the blur/filter/adjustments group, same
    // split as the settings page.
    readonly property var opt: GlobalStates.screenLocked
        ? (Config.options.background.effects.lock.sync
            ? Config.options.background.effects.desktop : Config.options.background.effects.lock)
        : Config.options.background.effects.desktop
    readonly property var glassOpt: GlobalStates.screenLocked
        ? (Config.options.background.effects.glass.lock.sync
            ? Config.options.background.effects.glass.desktop : Config.options.background.effects.glass.lock)
        : Config.options.background.effects.glass.desktop
    property bool isVideo: false

    // "glass" and "frosted" are the ROMs' two blur presets.
    readonly property int blurRadius: root.opt.blur.style === "glass" ? 50
        : root.opt.blur.style === "frosted" ? 9 : root.opt.blur.radius

    readonly property bool glassActive: root.glassOpt.enable
    readonly property bool blurActive: root.opt.blur.enable && root.blurRadius > 0
    readonly property bool filterActive: root.opt.filter !== "none"
        || root.opt.saturation !== 100 || root.opt.dim > 0 || root.opt.vignette > 0 || root.opt.grain > 0

    // The wallpaper hides itself once a stage renders it for us.
    readonly property bool takesOver: root.glassActive || root.blurActive || root.filterActive
    // What the lock screen's own blur should read.
    readonly property Item output: root.takesOver ? baked : root.wallpaper

    // Keep rendering only while something is actually changing. Walking the
    // option tree covers every knob, including ones added later, and QML tracks
    // the reads as binding dependencies.
    readonly property string digest: Config.options.background.wallpaperPath
        + JSON.stringify(root.opt) + JSON.stringify(root.glassOpt)

    // Anything below is live only while a bake is in flight.
    readonly property bool baking: settle.running || quickBake.running

    // Which side of the lock the digest was last taken on, so a group switch
    // can be told apart from a real edit. Assigned, never bound.
    property bool digestWasLocked: false
    Component.onCompleted: root.digestWasLocked = GlobalStates.screenLocked

    onDigestChanged: {
        // Locking swaps this whole chain from the desktop group to the lock
        // group, which changes the digest without anything animating: the
        // chain has to be re-rendered once and then it is a still image again.
        // The long settle is for a wallpaper transition or a slider being
        // dragged, and 2.5s of live full-screen blur is exactly what the lock
        // animation cannot afford.
        if (GlobalStates.screenLocked !== root.digestWasLocked) {
            root.digestWasLocked = GlobalStates.screenLocked;
            quickBake.restart();
            return;
        }
        settle.restart();
    }
    // Hiding the window (a fullscreen app, per background.hideWhenFullscreen)
    // can drop the frozen textures, so bake again on the way back. The lock
    // screen's own blur also flips this on every unlock, and 2.5s of live
    // fullscreen chain is exactly what the unlock animation cannot afford -
    // nothing changed there, so a couple of frames is enough.
    onVisibleChanged: if (root.visible) quickBake.restart()
    onWidthChanged: settle.restart()
    onHeightChanged: settle.restart()

    Timer {
        id: settle
        // Long enough to ride out a wallpaper transition and a slider drag.
        interval: 2500
        running: true
    }

    Timer {
        id: quickBake
        interval: 150
    }

    Connections {
        // The wallpaper loads asynchronously, so bake again once it is there.
        target: root.wallpaper
        ignoreUnknownSignals: true
        function onStatusChanged() {
            settle.restart();
        }
    }

    // Blur runs first: fluted glass refracts whatever sits behind it, so
    // blurring its output instead would smear the flutes and their highlights
    // away - the opposite of a glass pane over a frosted background.
    //
    // GaussianBlur reads its source through a texture of its own that is always
    // live, so hand it one that is already frozen instead of the raw wallpaper.
    ShaderEffectSource {
        id: blurInput
        anchors.fill: parent
        visible: false
        live: root.baking || root.isVideo
        // Never hidden: this one always reads the wallpaper directly.
        hideSource: false
        sourceItem: root.blurActive ? root.wallpaper : null
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
        id: glassLoader
        anchors.fill: parent
        active: root.glassActive
        sourceComponent: FlutedGlass {
            source: blurLoader.item ?? root.wallpaper
            hideSource: source !== root.wallpaper
            live: root.baking || root.isVideo
            opt: root.glassOpt
        }
    }

    Loader {
        id: filterLoader
        anchors.fill: parent
        active: root.filterActive
        sourceComponent: WallpaperFilter {
            source: glassLoader.item ?? blurLoader.item ?? root.wallpaper
            hideSource: source !== root.wallpaper
            live: root.baking || root.isVideo
            opt: root.opt
        }
    }

    // The only thing that actually paints: a frozen copy of the last stage.
    ShaderEffectSource {
        id: baked
        anchors.fill: parent
        visible: root.takesOver
        live: root.baking || root.isVideo
        hideSource: true
        sourceItem: root.takesOver
            ? (filterLoader.item ?? glassLoader.item ?? blurLoader.item)
            : null
    }
}
