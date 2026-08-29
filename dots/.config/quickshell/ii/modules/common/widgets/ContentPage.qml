import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    // 600 left the two-up chip rows a few pixels short once the cards took
    // their padding, so every one of them wrapped a trailing chip onto row two.
    property real baseWidth: 660
    property bool forceWidth: false
    property real bottomContentPadding: 100

    default property alias contentData: contentColumn.data

    clip: true
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding // Add some padding at the bottom
    implicitWidth: contentColumn.implicitWidth
    
    ColumnLayout {
        id: contentColumn
        width: root.forceWidth ? root.baseWidth : Math.max(root.baseWidth, implicitWidth)
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            margins: 20
        }
        spacing: 30
    }

}
