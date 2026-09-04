import qs.modules.common
import QtQuick

// The wavy fill behind StyledSlider / StyledProgressBar. The wave is drawn
// analytically in shaders/wavyLine.frag - property names here are its uniform
// names, so renaming one breaks the binding silently.
ShaderEffect {
    id: root
    property real amplitudeMultiplier: 0.5
    property real frequency: 6
    property color color: Appearance?.colors.colPrimary ?? "#685496"
    property real lineWidth: 4
    property real fullLength: width

    // False freezes the drift where it stands. The wave is a "something is
    // happening" cue, so a caller that has nothing happening turns it off.
    property bool animate: true

    // Uniforms. `amplitude` was `lineWidth * amplitudeMultiplier` in the
    // Canvas this replaces; keep that so callers need no changes.
    property vector2d resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
    property color waveColor: root.color
    property real amplitude: root.lineWidth * root.amplitudeMultiplier
    property real phase: 0

    fragmentShader: Qt.resolvedUrl("shaders/wavyLine.frag.qsb")

    // The Canvas took its phase from `Date.now() / 400`, i.e. 1/400 rad per
    // ms. One full cycle at that rate is 2*PI*400 ms, so animating the uniform
    // over exactly that keeps the old drift speed to the millisecond. This is
    // ambient motion rather than a transition, which is why it is derived from
    // the behaviour it replaces instead of an Appearance duration token.
    NumberAnimation on phase {
        running: root.animate && root.visible
        from: 0
        to: 2 * Math.PI
        duration: Math.round(2 * Math.PI * 400)
        loops: Animation.Infinite
    }
}
