import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Toolbar {
    id: colorToolbar
    z: 1
    // Two rows of four, sized from the swatches themselves: a fixed 196x90 held
    // three a row and cut the third row off.
    implicitHeight: swatches.implicitHeight + padding * 2
    radius: Appearance.rounding.large

    // Opened by the palette button, to its right: it grows out of that side, on
    // the ArrowPopup recipe (DESIGN.md 2.6).
    property bool shown: false
    transformOrigin: Item.BottomRight
    scale: Appearance.animationCurves.arrowPopupScale
    opacity: 0
    visible: opacity > 0
    onShownChanged: shown ? motion.open() : motion.close()
    ArrowPopupMotion {
        id: motion
        target: colorToolbar
    }

    ConfigSelectionArray {
        id: swatches
        readonly property real swatchWidth: children[0]?.width ?? 0
        // ceil: fractional widths wrap a row early
        Layout.preferredWidth: leftPadding + rightPadding + Math.ceil(swatchWidth) * 4 + spacing * 3
        currentValue: wallpaperSelectorContent.activeColorFilter
        onSelected: newValue => {
            wallpaperSelectorContent.activeColorFilter = newValue
        }
        options: [ 
            {
                displayName: "",
                shape: "Pill",
                value: "#ed3802", // we use different values for the filters than the actual colors shown on the buttons 
                color: "#c63c1f"  // to have warmer colors on the UI, but still have the filters work correctly 
            }, 
            {
                displayName: "",
                shape: "Pentagon",
                value: "#f4a40e",
                color: "#c88a1a"
            }, 
            {
                displayName: "",
                shape: "Sunny",
                value: "#f8e115",
                color: "#c6b21a"
            }, 
            {
                displayName: "",
                shape: "Bun",
                value: "#8CD65E",
                color: "#3fa34d"
            }, 
            {
                displayName: "",
                shape: "PixelCircle",
                value: "#2c94fa",
                color: "#3a7bd5"
            }, 
            {
                displayName: "",
                shape: "Arch",
                value: "#831cd7",
                color: "#6e3ac7"
            },
            {
                displayName: "",
                shape: "Heart",
                value: "#f454b1",
                color: "#c94a8a"
            },
            {
                displayName: "",
                shape: "Cookie7Sided",
                value: "#a7a7a9",
                color: "#8c8c8f"
            }
        ]
    }       
}