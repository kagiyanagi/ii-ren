pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.waffle.looks

WBarAttachedPanelContent {
    id: root
    required property string iconName
    property real value
    property bool showNumber: true

    property alias timer: autoCloseTimer

    Timer {
        id: autoCloseTimer
        running: true
        interval: (Config.ready && Config.options.osd?.timeout) ? Config.options.osd.timeout : 3000
        repeat: false
        onTriggered: {
            root.close();
        }
    }

    contentItem: WPane {
        anchors.centerIn: parent
        borderColor: Looks.colors.ambientShadow

        contentItem: Item {
            implicitWidth: root.showNumber ? 192 : 168
            implicitHeight: 48

            RowLayout {
                id: contentRow
                anchors.fill: parent
                anchors.margins: 12

                spacing: 12

                FluentIcon {
                    Layout.alignment: Qt.AlignVCenter
                    icon: root.iconName
                    implicitSize: 16
                }

                WProgressBar {
                    id: progressBar
                    value: root.value
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: root.showNumber ? 0 : 4
                }

                WTextWithFixedWidth {
                    visible: root.showNumber
                    text: Math.round((root.value ?? 0) * 100)
                    longestText: "100"
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
