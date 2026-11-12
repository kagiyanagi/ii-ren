pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common

/**
 * Comfort View: desaturate, shift warm and cap highlights. State and settings only;
 * ScreenShader composes it with Reading Mode and Anti-flashbang and puts it on screen.
 */
Singleton {
    id: root

    readonly property bool manualEnable: Config.options?.light?.comfortView?.enable ?? false
    readonly property bool automatic: Config.options?.light?.comfortView?.automatic ?? false
    readonly property int intensity: Config.options?.light?.comfortView?.intensity ?? 50

    readonly property bool effectiveActive: manualEnable || (automatic && Hyprsunset.shouldBeOn)
    readonly property bool active: effectiveActive

    function toggleManual(checked) {
        if (checked === undefined)
            checked = !root.manualEnable;
        if (Config.options?.light?.comfortView)
            Config.options.light.comfortView.enable = checked;
    }

    function toggleAutomatic(checked) {
        if (checked === undefined)
            checked = !root.automatic;
        if (Config.options?.light?.comfortView)
            Config.options.light.comfortView.automatic = checked;
    }

    // Only the setting: ScreenShader debounces the shader a slider drag produces.
    function setIntensity(val) {
        if (Config.options?.light?.comfortView)
            Config.options.light.comfortView.intensity = Math.max(0, Math.min(100, Math.round(val)));
    }
}
