import qs.modules.common
import QtQuick

StyledText {
    id: root
    property real iconSize: Appearance?.font.pixelSize.small ?? 16
    property real fill: 0
    property real truncatedFill: fill.toFixed(1) // Reduce memory consumption spikes from constant font remapping
    renderType: Text.NativeRendering
    // One glyph: elided it measures 0 wide and vanishes rather than showing an
    // ellipsis, so a squeezed row would drop the icon. Opt out of StyledText's
    // ElideRight. Measured, not assumed.
    elide: Text.ElideNone
    font {
        hintingPreference: Font.PreferNoHinting
        family: Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded"
        pixelSize: iconSize
        weight: Font.Normal + (Font.DemiBold - Font.Normal) * truncatedFill
        variableAxes: { 
            "FILL": truncatedFill,
            // "wght": font.weight,
            // "GRAD": 0,
            "opsz": iconSize,
        }
    }

    Behavior on fill { // Leaky leaky, no good
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
}
