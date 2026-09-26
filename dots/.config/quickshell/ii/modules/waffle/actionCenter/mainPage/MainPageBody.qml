pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

BodyRectangle {
    id: root
    implicitHeight: contentLayout.implicitHeight

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        spacing: 0

        MainPageBodyToggles {
            id: togglesContainer
            Layout.fillWidth: true
        }

        WPanelSeparator {
            color: Looks.colors.bg1Border
        }

        MainPageBodySliders {
            Layout.margins: 12
            Layout.topMargin: 16
            Layout.bottomMargin: 12
        }
    }
}
