import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

/*
    Almost all of the custom color schemes (latte.json, samurai.json etc.) are gotten from https://github.com/snowarch/quickshell-ii-niri/blob/main/modules/common/ThemePresets.qml

    To add a new custom color scheme:

    1. Get a proper color scheme (in the same format as the default ones) and put in to ~/.config/illogical_impulse/themes
    2. Add the exact name of the json file to the config.json - appearance - customColorSchemes
*/

GridLayout {
    id: root
    implicitWidth: parent.width
    columns: 3

    readonly property list<string> builtInColorSchemes: ["angel_light", "angel", "ayu", "cobalt2", "cursor", "dracula", "flexoki", "frappe", "github", "gruvbox", "kanagawa", "latte", "macchiato", "material_ocean", "matrix", "mercury", "mocha", "nord", "open_code", "orng", "osaka_jade", "rose_pine", "sakura", "samurai", "synthwave84", "vercel", "vesper", "zen_burn", "zen_garden"]
    property list<string> customColorSchemes: Config.options.appearance.customColorSchemes ?? []

    readonly property list<string> wallpaperColorSchemes: ["scheme-auto", "scheme-content", "scheme-tonal-spot", "scheme-fidelity", "scheme-fruit-salad", "scheme-expressive", "scheme-rainbow", "scheme-neutral", "scheme-monochrome"]

    property bool customTheme: false
    property bool builtInTheme: false
    property list<string> colorSchemes: customTheme ? customColorSchemes : builtInTheme ? builtInColorSchemes : root.wallpaperColorSchemes

    function formatText(text) {
        if (customTheme || builtInTheme) return text.charAt(0).toUpperCase() + text.slice(1);
        const sliced = text.split("-").slice(1).join(" ");
        return sliced.charAt(0).toUpperCase() + sliced.slice(1);
    }

    property int loadedCount: 0

    Repeater {
        model: root.colorSchemes
        
        delegate: ColorPreviewButton {
            Layout.fillWidth: true
            
            colorScheme: modelData
            colorSchemeDisplayName: formatText(modelData)
            customTheme: root.customTheme
            builtInTheme: root.builtInTheme
            
            shouldLoad: index < root.loadedCount
            wallpaperPreview: root.wallpaperPreviews[modelData] ?? null
        }
    }

    // Every wallpaper scheme from one read of the image, in the venv the colour scripts
    // need: a plain python3 per button lacked materialyoucolor and failed nine times
    // over, so these never showed a colour. The path is an argument, not shell text.
    property var wallpaperPreviews: ({})
    Process {
        running: !root.customTheme && !root.builtInTheme && Config.options.background.wallpaperPath.length > 0
        command: ["bash", "-c", 'source "$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")/bin/activate" && exec python3 "$@"', "_",
            FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/generate_colors_material.py`),
            "--path", Config.options.background.wallpaperPath, "--preview-all", root.wallpaperColorSchemes.join(",")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpaperPreviews = JSON.parse(this.text);
                } catch (e) {} // a video wallpaper or no venv: the buttons keep their names
            }
        }
    }

    Timer {
        id: loadTimer
        interval: 20
        repeat: true
        running: false
        
        onTriggered: {
            root.loadedCount += 1

            if (root.loadedCount >= root.colorSchemes.length) { // stop it after all are loaded
                loadTimer.stop()
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(() => loadTimer.start())
    }
}