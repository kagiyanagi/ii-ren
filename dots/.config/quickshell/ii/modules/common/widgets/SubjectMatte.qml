import QtQuick

// The subject half of a packed subject-depth video: the wallpaper frame with
// its own matte applied, so it can be drawn back over the desktop widgets.
//
// `source` is the VideoOutput playing the packed file - frame on top, matte
// underneath, at double height. Property names here are the uniform names in
// shaders/subjectMatte.frag.
ShaderEffect {
    id: root

    required property Item source

    property variant src: sourceTexture
    // The shader needs this to stay half a texel off the seam between the two
    // halves of the packed frame.
    property real texel: 1 / Math.max(1, sourceTexture.height)

    // Measured off a baked wallpaper: h.264 returns clear pixels at a mean of
    // 0.18/255 and leaves the opaque interior bottoming out near 237/255.
    // Rescaling between these pins both ends without flattening the soft edge.
    property real toe: 0.02
    property real shoulder: 0.94

    fragmentShader: Qt.resolvedUrl("shaders/subjectMatte.frag.qsb")

    // ShaderEffect can only sample a texture provider, and VideoOutput is a
    // plain Item. hideSource stays false: the same VideoOutput also draws the
    // wallpaper itself, and hiding it would take the background with it.
    ShaderEffectSource {
        id: sourceTexture
        // Sized to the source, not to this item. Filling the parent would
        // squash the double-height packed frame into a wallpaper-sized texture
        // and halve the vertical resolution of both the frame and its matte.
        width: root.source?.width ?? 0
        height: root.source?.height ?? 0
        visible: false
        live: true
        hideSource: false
        sourceItem: root.source
    }
}
