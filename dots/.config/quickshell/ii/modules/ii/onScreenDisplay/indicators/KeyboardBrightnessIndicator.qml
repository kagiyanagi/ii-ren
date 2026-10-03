import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay
import qs.modules.common.widgets
import qs.modules.common

OsdMaterialValueIndicator {
    value: KeyboardBacklight.percentage / 100
    icon: "keyboard"
    shape: MaterialShape.Shape.Hexagon
}
