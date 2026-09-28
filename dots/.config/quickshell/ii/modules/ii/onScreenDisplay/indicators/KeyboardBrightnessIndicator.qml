import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay
import qs.modules.common.widgets
import qs.modules.common

OsdMaterialValueIndicator {
    value: KeyboardBacklight.percentage / 100
    icon: "keyboard"
    shape: MaterialShape.Shape.Hexagon

    onMoved: function(newValue) {
        const max = KeyboardBacklight.maxValue;
        const level = Math.round(newValue * max);
        KeyboardBacklight.setValue(level);
    }
}
