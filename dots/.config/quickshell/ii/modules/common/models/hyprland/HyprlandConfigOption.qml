pragma ComponentBehavior: Bound
import QtQml
import QtQuick
import Quickshell.Io
import qs.services
import "../"

NestableObject {
    id: root

    required property string key
    property alias fetching: fetchProc.running
    property bool set
    property var value

    // False until the first fetch lands. Controls bound to `value` fire their
    // change handlers during construction, while it is still undefined, so
    // writing before this flips would clobber the real config with a default.
    property bool loaded: false

    // hyprctl reports gaps as css ("4 4 4 4") and switches as true/false.
    // Controls need one comparable number out of all of those.
    readonly property real numericValue: {
        if (typeof root.value === "number")
            return root.value;
        if (typeof root.value === "boolean")
            return root.value ? 1 : 0;
        const parsed = parseFloat(String(root.value ?? ""));
        return isNaN(parsed) ? 0 : parsed;
    }

    Component.onCompleted: fetch()

    Connections {
        target: HyprlandSettings
        function onReloaded() {
            root.fetch();
        }
    }

    function fetch() {
        fetchProc.command = fetchProc.baseCommand.concat([root.key]);
        fetchProc.running = true;
    }

    function setValue(newValue) {
        HyprlandSettings.changeKey(root.key, newValue)
    }

    function reset() {
        HyprlandSettings.reset(root.key)
    }

    Process {
        id: fetchProc
        property list<string> baseCommand: ["hyprctl", "getoption", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text == "no such option")
                    return;
                try {
                    const obj = JSON.parse(text);
                    // Note that the value is returned as "<data type>": <value>
                    // It's the only field that isn't always in the same key so we put it in an else
                    for (const key in obj) {
                        if (key == "option")
                            continue;
                        else if (key == "set")
                            root.set = obj[key];
                        else
                            root.value = obj[key];
                    }
                    root.loaded = true;
                } catch (e) {
                    console.log(`[HyprlandConfigOption] Failed to fetch option "${root.key}":\n  - Output: ${text.trim()}\n  - Error: ${e}`);
                }
            }
        }
    }
}
