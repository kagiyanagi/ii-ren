import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay
import qs.modules.common.widgets
import qs.modules.common

OsdMaterialValueIndicator {
    // The LED counts in kernel levels (0..max_brightness, often 0..2); the indicator
    // takes 0-1. maxValue is 0 until max_brightness loads, and 0/0 is NaN.
    value: KeyboardBacklight.maxValue > 0 ? KeyboardBacklight.currentValue / KeyboardBacklight.maxValue : 0
    icon: KeyboardBacklight.currentValue > 0 ? "keyboard_full" : "keyboard_off"
    shape: MaterialShape.Shape.Hexagon
}
