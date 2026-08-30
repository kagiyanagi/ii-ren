import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    
    property bool colorize: false
    property color color
    property string source: ""
    property string iconFolder: Qt.resolvedUrl(Quickshell.shellPath("assets/icons"))  // The folder to check first
    width: 30
    height: 30
    
    IconImage {
        id: iconImage
        anchors.fill: parent
        source: {
            // Nothing to show is not the same as the icon folder itself, which is
            // what concatenating an empty name used to ask the loader for.
            if (root.source === "")
                return "";
            const fullPathWhenSourceIsIconName = iconFolder + "/" + root.source;
            if (iconFolder && fullPathWhenSourceIsIconName) {
                return fullPathWhenSourceIsIconName
            }
            return root.source
        }
        implicitSize: root.height
    }

    Loader {
        active: root.colorize
        anchors.fill: iconImage
        sourceComponent: ColorOverlay {
            source: iconImage
            color: root.color
        }
    }
}
