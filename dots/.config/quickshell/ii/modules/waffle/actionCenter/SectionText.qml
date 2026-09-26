pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks

WText {
    id: root
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.topMargin: 6
    Layout.bottomMargin: 6

    font {
        weight: Looks.font.weight.stronger
        pixelSize: Looks.font.pixelSize.large
    }
}
