import qs.modules.common
import QtQuick

// The custom-ROM wallpaper effect set (risingOS/Evolution X) in one pass, plus
// the adjustments that stack on top of any of them. Property names here are
// the uniform names in shaders/wallpaperFilter.frag.
ShaderEffect {
    id: root

    required property Item source
    property var preset: ({})
    // False freezes the input texture: the result is a still image, so there is
    // no reason to re-read the source once nothing is changing.
    property bool live: true
    // The wallpaper must keep rendering itself even though we draw over it:
    // its transition animation runs through layers on its own images, and an
    // item nothing renders never produces them, so the wipe never appears.
    property bool hideSource: true
    readonly property var opt: Config.options.background.effects

    // Index order matches the shader's `filterMode` switch.
    readonly property var filterNames: ["none", "grayscale", "sepia", "negative",
        "posterize", "pixelate", "sharpen", "chromatic", "radialBlur"]

    property variant src: sourceTexture
    property vector2d resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
    property real saturation: (root.preset.saturation ?? root.opt.saturation) / 100
    property real dim: (root.preset.dim ?? root.opt.dim) / 100
    property real vignette: (root.preset.vignette ?? root.opt.vignette) / 100
    property real grain: (root.preset.grain ?? root.opt.grain) / 100
    property real pixelSize: root.preset.pixelSize ?? root.opt.pixelSize
    property real posterizeLevels: root.preset.posterizeLevels ?? root.opt.posterizeLevels
    property real sharpen: root.preset.sharpen ?? root.opt.sharpen
    property real chromatic: root.preset.chromatic ?? root.opt.chromatic
    property real radialBlur: (root.preset.radialBlur ?? root.opt.radialBlur) / 100
    property int filterMode: Math.max(0, root.filterNames.indexOf(root.preset.filter ?? root.opt.filter))

    fragmentShader: Qt.resolvedUrl("shaders/wallpaperFilter.frag.qsb")

    // ShaderEffect can only sample a texture provider, and both the wallpaper
    // and the stage before us are plain Items, so wrap whatever we are handed.
    // ShaderEffectSource renders its sourceItem explicitly, which is also what
    // lets the desktop hide the wallpaper while we draw it.
    ShaderEffectSource {
        id: sourceTexture
        anchors.fill: parent
        visible: false
        live: root.live
        // Stops the stage before us painting to the screen as well as into
        // this texture, which it would otherwise do only to be covered up.
        hideSource: root.hideSource
        sourceItem: root.source
    }
}
