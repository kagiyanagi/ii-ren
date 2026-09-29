pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

// Quick toggles the user defines: a name, an icon, and a command for each way.
// On or off is only what the last click said, kept in Persistent so a shell
// reload does not flip every tile back to off. Nothing asks the system.
Singleton {
    id: root

    readonly property list<var> list: (Config.options?.sidebar?.quickToggles?.customToggles ?? []).filter(item => item?.id)

    function isToggled(id: string): bool {
        return Persistent.states.sidebar.activeCustomToggles.includes(id);
    }

    function getToggle(id: string): var {
        return root.list.find(item => item.id === id) ?? null;
    }

    function setToggled(id: string, toggled: bool): void {
        const others = Persistent.states.sidebar.activeCustomToggles.filter(other => other !== id);
        Persistent.states.sidebar.activeCustomToggles = toggled ? [...others, id] : others;
    }

    function toggle(id: string): void {
        const item = root.getToggle(id);
        if (!item)
            return;
        const next = !root.isToggled(id);
        const command = next ? item.commandStart : item.commandStop;
        if (command)
            Quickshell.execDetached(["bash", "-c", command]);
        root.setToggled(id, next);
    }

    function entry(id, name, icon, commandStart, commandStop) {
        return {
            id: id,
            name: name.trim(),
            icon: icon.trim() || "terminal",
            commandStart: commandStart.trim(),
            commandStop: commandStop.trim()
        };
    }

    function addToggle(name: string, icon: string, commandStart: string, commandStop: string): void {
        Config.options.sidebar.quickToggles.customToggles = [...root.list, root.entry("custom_" + Date.now(), name, icon, commandStart, commandStop)];
    }

    function updateToggle(id: string, name: string, icon: string, commandStart: string, commandStop: string): void {
        Config.options.sidebar.quickToggles.customToggles = root.list.map(item => item.id === id ? root.entry(id, name, icon, commandStart, commandStop) : item);
    }

    // Also takes the tile off whichever page holds it, or the page would keep
    // a tile with nothing behind it.
    function removeToggle(id: string): void {
        Config.options.sidebar.quickToggles.customToggles = root.list.filter(item => item.id !== id);
        root.setToggled(id, false);
        const android = Config.options.sidebar.quickToggles.android;
        android.pages = android.pages.map(page => page?.filter ? page.filter(item => item?.id !== id) : page);
    }
}
