import qs.modules.common
import QtQuick
import QtQuick.Effects

// Repaints whatever it is given in one flat colour, animating between colours.
// The brightness term compensates for the tint's own lightness, so a dark colour
// does not come out muddy the way a plain overlay does.
// The modern replacement for Qt5Compat's ColorOverlay.
MultiEffect {
    property color sourceColor: "black"

    colorization: 1
    brightness: 1 - sourceColor.hslLightness

    Behavior on colorizationColor {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
}
