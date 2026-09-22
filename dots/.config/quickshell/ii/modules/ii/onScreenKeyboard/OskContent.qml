import qs.modules.common
import "layouts.js" as Layouts
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property var layouts: Layouts.byName
    readonly property int layoutCount: Object.keys(root.layouts).length
    // The shipped config default named a layout that does not exist in layouts.js, so
    // this fell back for everyone and the other two layouts were unreachable.
    property var activeLayoutName: (layouts.hasOwnProperty(Config.options?.osk.layout))
        ? Config.options?.osk.layout
        : Layouts.defaultLayout
    property var currentLayout: layouts[activeLayoutName]

    // Cycles from the *resolved* name, so a config holding an unknown layout lands on
    // the first one rather than nowhere.
    function cycleLayout(): void {
        const names = Object.keys(root.layouts);
        Config.options.osk.layout = names[(names.indexOf(root.activeLayoutName) + 1) % names.length];
    }

    implicitWidth: keyRows.implicitWidth
    implicitHeight: keyRows.implicitHeight

    ColumnLayout {
        id: keyRows
        anchors.fill: parent
        spacing: 4

        Repeater {
            model: root.currentLayout.keys

            delegate: RowLayout {
                id: keyRow
                required property var modelData
                spacing: 4

                Repeater {
                    model: modelData
                    // A normal key looks like this: {keytype: "normal", label: "a", labelShift: "A", shape: "normal", keycode: 30}
                    delegate: OskKey {
                        required property var modelData
                        keyData: modelData
                    }
                }
            }
        }
    }
}
