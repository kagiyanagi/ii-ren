import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.ii.onScreenDisplay
import qs.modules.common.widgets
import qs.modules.common

OsdMaterialValueIndicator {
    id: root

    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
    property var brightnessMonitor: Brightness.getMonitorForScreen(focusedScreen)

    value: root.brightnessMonitor?.brightness ?? 0.5
    icon: {
        if (Hyprsunset.temperatureActive) return "routine";
        const val = root.value;
        if (val <= 0.33) return "brightness_low";
        if (val <= 0.66) return "brightness_medium";
        return "brightness_high";
    }
    shape: MaterialShape.Shape.SoftBurst
}
