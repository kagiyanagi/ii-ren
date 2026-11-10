pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "hyprlandOverrides.js" as Overrides

/**
 * Game mode: no animations, blur, shadows, gaps or rounding, and tearing allowed,
 * as overrides in shellOverrides/main.lua so they hold across a Hyprland reload.
 * On/off is its own state in Persistent, not read off animations:enabled, which the
 * user may turn off on their own. Turning it on saves what main.lua had for each key
 * and turning it off puts that back: the user's own override, or none if there was
 * none. A key changed while game mode was on (Settings, `iiren hyprset`) keeps the
 * newer value.
 */
Singleton {
    id: root

    readonly property bool active: Persistent.ready && Persistent.states.hyprland.gameMode
    readonly property var values: ({
        "animations:enabled": 0,
        "decoration:shadow:enabled": 0,
        "decoration:blur:enabled": 0,
        "general:gaps_in": 0,
        "general:gaps_out": 0,
        "general:border_size": 1,
        "decoration:rounding": 0,
        "general:allow_tearing": 1
    })

    // The change last sent, until main.lua shows it. hyprset rewrites the file once
    // per key, and a toggle read off a half-written file would save game mode's own
    // values as the user's, or leave them behind as the user's changes.
    property var pending: null

    function toggle() {
        root.setActive(!root.active);
    }

    function setActive(on) {
        if (!Persistent.ready || !HyprlandSettings.overridesLoaded || root.pending || on === root.active)
            return;
        const overrides = HyprlandSettings.overrides;
        const states = Persistent.states.hyprland;
        let change;
        if (on) {
            states.gameModeSaved = Overrides.snapshot(overrides, Object.keys(root.values));
            change = { set: root.values, reset: [] };
        } else {
            change = Overrides.restorePlan([...states.gameModeSaved], root.values, overrides);
            states.gameModeSaved = [];
        }
        states.gameMode = on;
        if (Overrides.reached(overrides, change))
            return;
        root.pending = change;
        pendingTimeout.restart();
        HyprlandSettings.updateKeys(change.set, change.reset);
    }

    readonly property var overrides: HyprlandSettings.overrides
    onOverridesChanged: {
        if (root.pending && Overrides.reached(root.overrides, root.pending))
            root.pending = null;
    }

    // A write that never lands (hyprset missing, a value refused) must not lock the toggle.
    Timer {
        id: pendingTimeout
        interval: 3000
        onTriggered: root.pending = null
    }
}
