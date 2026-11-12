pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common

/**
 * Reading Mode: grayscale, optionally paper-toned. State and settings only;
 * ScreenShader composes it with Comfort View and Anti-flashbang and puts it on screen.
 */
Singleton {
    id: root

    readonly property bool manualEnable: Config.options?.light?.readingMode?.enable ?? false
    readonly property bool automatic: Config.options?.light?.readingMode?.automatic ?? false
    readonly property int intensity: Config.options?.light?.readingMode?.intensity ?? 100
    readonly property bool paperTone: Config.options?.light?.readingMode?.paperTone ?? false

    readonly property bool effectiveActive: manualEnable || (automatic && Hyprsunset.shouldBeOn)
    readonly property bool active: effectiveActive

    function toggleManual(checked) {
        if (checked === undefined)
            checked = !root.manualEnable;
        if (Config.options?.light?.readingMode)
            Config.options.light.readingMode.enable = checked;
    }

    function toggleAutomatic(checked) {
        if (checked === undefined)
            checked = !root.automatic;
        if (Config.options?.light?.readingMode)
            Config.options.light.readingMode.automatic = checked;
    }

    function togglePaperTone(checked) {
        if (checked === undefined)
            checked = !root.paperTone;
        if (Config.options?.light?.readingMode)
            Config.options.light.readingMode.paperTone = checked;
    }

    // Only the setting: ScreenShader debounces the shader a slider drag produces.
    function setIntensity(val) {
        if (Config.options?.light?.readingMode)
            Config.options.light.readingMode.intensity = Math.max(0, Math.min(100, Math.round(val)));
    }
}
