pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * Anti-flashbang: darken the screen by its average brightness. ScreenShader composes
 * it with Comfort View and Reading Mode, which used to replace it outright.
 */
Singleton {
    id: root

    readonly property bool enabled: ScreenShader.antiFlashbang

    function enable() {
        ScreenShader.setAntiFlashbang(true);
    }

    function disable() {
        ScreenShader.setAntiFlashbang(false);
    }

    function toggle() {
        ScreenShader.setAntiFlashbang(!root.enabled);
    }
}
