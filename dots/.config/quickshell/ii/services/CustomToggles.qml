pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    // Active runtime state map: id -> bool
    property var activeStates: ({})

    readonly property list<var> list: {
        var raw = Config.options?.sidebar?.quickToggles?.customToggles;
        if (!raw)
            return [];
        var result = [];
        for (var i = 0; i < raw.length; i++) {
            if (raw[i] && raw[i].id)
                result.push(raw[i]);
        }
        return result;
    }

    function isToggled(id: string): bool {
        return !!root.activeStates[id];
    }

    function getToggle(id: string): var {
        for (var i = 0; i < root.list.length; i++) {
            if (root.list[i].id === id)
                return root.list[i];
        }
        return null;
    }

    function setToggled(id: string, toggled: bool): void {
        var updated = Object.assign({}, root.activeStates);
        updated[id] = toggled;
        root.activeStates = updated;
    }

    function toggle(id: string): void {
        var item = getToggle(id);
        if (!item)
            return;

        var currentState = isToggled(id);
        var nextState = !currentState;

        if (nextState) {
            if (item.commandStart && item.commandStart.trim().length > 0) {
                Quickshell.execDetached(["bash", "-c", item.commandStart.trim()]);
            }
        } else {
            if (item.commandStop && item.commandStop.trim().length > 0) {
                Quickshell.execDetached(["bash", "-c", item.commandStop.trim()]);
            }
        }
        setToggled(id, nextState);
    }

    function addToggle(name: string, icon: string, commandStart: string, commandStop: string): var {
        var newId = "custom_" + Date.now();
        var newEntry = {
            id: newId,
            type: "custom",
            name: name,
            icon: icon && icon.trim().length > 0 ? icon.trim() : "terminal",
            commandStart: commandStart ? commandStart.trim() : "",
            commandStop: commandStop ? commandStop.trim() : "",
            sizeW: 2,
            sizeH: 1
        };

        var current = [];
        if (Config.options?.sidebar?.quickToggles?.customToggles) {
            for (var i = 0; i < Config.options.sidebar.quickToggles.customToggles.length; i++) {
                current.push(Config.options.sidebar.quickToggles.customToggles[i]);
            }
        }
        current.push(newEntry);
        Config.options.sidebar.quickToggles.customToggles = current;
        return newEntry;
    }

    function updateToggle(id: string, name: string, icon: string, commandStart: string, commandStop: string): bool {
        if (!Config.options?.sidebar?.quickToggles?.customToggles)
            return false;

        var current = [];
        var found = false;
        for (var i = 0; i < Config.options.sidebar.quickToggles.customToggles.length; i++) {
            var item = Config.options.sidebar.quickToggles.customToggles[i];
            if (item && item.id === id) {
                var updated = {
                    id: id,
                    type: "custom",
                    name: name,
                    icon: icon && icon.trim().length > 0 ? icon.trim() : "terminal",
                    commandStart: commandStart ? commandStart.trim() : "",
                    commandStop: commandStop ? commandStop.trim() : "",
                    sizeW: item.sizeW || 2,
                    sizeH: item.sizeH || 1
                };
                current.push(updated);
                found = true;
            } else {
                current.push(item);
            }
        }
        if (found) {
            Config.options.sidebar.quickToggles.customToggles = current;
        }
        return found;
    }

    function removeToggle(id: string): bool {
        if (!Config.options?.sidebar?.quickToggles?.customToggles)
            return false;

        var current = [];
        for (var i = 0; i < Config.options.sidebar.quickToggles.customToggles.length; i++) {
            var item = Config.options.sidebar.quickToggles.customToggles[i];
            if (item && item.id !== id) {
                current.push(item);
            }
        }
        Config.options.sidebar.quickToggles.customToggles = current;

        if (root.activeStates[id] !== undefined) {
            var updatedStates = Object.assign({}, root.activeStates);
            delete updatedStates[id];
            root.activeStates = updatedStates;
        }

        if (Config.options?.sidebar?.quickToggles?.android?.pages) {
            var rawPages = Config.options.sidebar.quickToggles.android.pages;
            var pagesChanged = false;
            var newPages = [];
            for (var p = 0; p < rawPages.length; p++) {
                var page = rawPages[p];
                if (!page)
                    continue;
                var filteredPage = [];
                for (var j = 0; j < page.length; j++) {
                    if (page[j] && page[j].id === id) {
                        pagesChanged = true;
                    } else {
                        filteredPage.push(page[j]);
                    }
                }
                newPages.push(filteredPage);
            }
            if (pagesChanged) {
                Config.options.sidebar.quickToggles.android.pages = newPages;
            }
        }

        return true;
    }
}
