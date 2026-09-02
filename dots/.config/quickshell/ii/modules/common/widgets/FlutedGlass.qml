import qs.modules.common
import QtQuick

// Fluted / reeded glass over `source`. Property names here are the uniform
// names in shaders/flutedGlass.frag - renaming one breaks the binding
// silently. Values come from the live config; `preset` overrides individual
// keys so a settings preview can show a style without saving it.
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
    // Desktop and lock screen target separately; the caller resolves which
    // one is active and hands it in. Defaults to desktop for callers (like
    // the settings preview) that always override every key via `preset`.
    property var opt: Config.options.background.effects.glass.desktop

    // Index order matches the shader's `pattern` / `profile` switches.
    readonly property var patternNames: ["lines", "rain", "chevron", "bubble"]
    readonly property var profileNames: ["lens", "prism", "contour", "cascade", "flat"]

    property variant src: sourceTexture
    property vector2d resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
    property real cellSize: root.preset.fluteWidth ?? root.opt.fluteWidth
    property real angle: (root.preset.angle ?? root.opt.angle) * Math.PI / 180
    property real distortion: (root.preset.distortion ?? root.opt.distortion) / 100
    property real dispersion: (root.preset.dispersion ?? root.opt.dispersion) / 100
    property real blurAmount: (root.preset.smear ?? root.opt.smear) / 100
    property real highlights: (root.preset.highlights ?? root.opt.highlights) / 100
    property real shadows: (root.preset.shadows ?? root.opt.shadows) / 100
    property real edges: (root.preset.edges ?? root.opt.edges) / 100
    property real grain: (root.preset.frost ?? root.opt.frost) / 100
    property real irregularity: (root.preset.irregularity ?? root.opt.irregularity) / 100
    property real waviness: (root.preset.waviness ?? root.opt.waviness) / 100
    property int pattern: Math.max(0, root.patternNames.indexOf(root.preset.pattern ?? root.opt.pattern))
    property int profile: Math.max(0, root.profileNames.indexOf(root.preset.profile ?? root.opt.profile))

    fragmentShader: Qt.resolvedUrl("shaders/flutedGlass.frag.qsb")

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
