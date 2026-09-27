import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Toolbar {
    id: extraOptions
    z: 1

    property alias field: filterField

    IconToolbarButton {
        implicitWidth: height
        onClicked: {
            Wallpapers.openFallbackPicker(wallpaperSelectorContent.useDarkMode);
            GlobalStates.wallpaperSelectorOpen = false;
        }
        altAction: () => {
            Wallpapers.openFallbackPicker(wallpaperSelectorContent.useDarkMode);
            GlobalStates.wallpaperSelectorOpen = false;
            Config.options.wallpaperSelector.useSystemFileDialog = true
        }
        text: "open_in_new"
        StyledToolTip {
            text: Translation.tr("Use the system file picker instead\nRight-click to make this the default behavior")
        }
    }

    IconToolbarButton {
        implicitWidth: height
        onClicked: {
            if (wallpaperSelectorContent.viewMode === "folder" && !wallpaperSelectorContent.activeColorFilter) {
                Wallpapers.randomFromCurrentFolder(wallpaperSelectorContent.useDarkMode);
                return;
            }
            // Whatever the grid is showing: favourites, a colour, the browser.
            const entries = grid.model;
            if (entries.length > 0)
                wallpaperSelectorContent.activate(entries[Math.floor(Math.random() * entries.length)]);
        }
        text: "ifl"
        StyledToolTip {
            text: Translation.tr("Pick one at random")
        }
    }

    IconToolbarButton {
        implicitWidth: height
        onClicked: {
            if (!toggled) wallpaperSelectorContent.updateColorCache();
            colorFilterToolbar.shown = !colorFilterToolbar.shown;
            if (!colorFilterToolbar.shown) wallpaperSelectorContent.activeColorFilter = "";
        }
        toggled: colorFilterToolbar.shown
        text: "palette"
        StyledToolTip {
            text: colorCacheProc.running ? Translation.tr("Updating color cache...") : Translation.tr("Filter by color")
        }
    }

    IconToolbarButton {
        implicitWidth: height
        onClicked: wallpaperSelectorContent.useDarkMode = !wallpaperSelectorContent.useDarkMode
        text: wallpaperSelectorContent.useDarkMode ? "dark_mode" : "light_mode"
        StyledToolTip {
            text: Translation.tr("Click to toggle light/dark mode\n(applied when wallpaper is chosen)")
        }
    }

    ToolbarTextField {
        id: filterField
        placeholderText: {
            if (wallpaperSelectorContent.browserMode) return Translation.tr("Search API (e.g. nature, city)");
            return focus ? Translation.tr("Search wallpapers") : Translation.tr("Hit \"/\" to search")
        }

        // Style
        clip: true
        font.pixelSize: Appearance.font.pixelSize.small

        // Search
        onTextChanged: {
            if (!wallpaperSelectorContent.browserMode) Wallpapers.searchQuery = text;
        }

        // The field holds focus from the moment the surface opens, and a TextField
        // eats Return, so Enter picks the focused tile from here too.
        onAccepted: {
            if (!wallpaperSelectorContent.browserMode) {
                grid.activateCurrent();
                return;
            }
            if (text.trim().length === 0) return;
            wallpaperSelectorContent.moreOptionsModelData = null;
            wallpaperSelectorContent.browserService.clearResponses();
            wallpaperSelectorContent.browserService.makeRequest(text.trim().split(/\s+/), 20, 1);
            grid.currentIndex = 0;
            text = "";
        }

        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
                wallpaperSelectorContent.handleFilePasting(event);
                return;
            }
            else if (text.length !== 0) {
                // No filtering, just navigate grid
                if (event.key === Qt.Key_Down) {
                    grid.moveSelection(grid.columns);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Up) {
                    grid.moveSelection(-grid.columns);
                    event.accepted = true;
                    return;
                }
            }
            event.accepted = false;
        }
    }

    IconToolbarButton {
        implicitWidth: height
        onClicked: {
            GlobalStates.wallpaperSelectorOpen = false;
        }
        text: "close"
        StyledToolTip {
            text: Translation.tr("Cancel wallpaper selection")
        }
    }
}
