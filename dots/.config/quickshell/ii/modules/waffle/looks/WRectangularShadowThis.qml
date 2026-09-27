pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks

Item {
    default property Item contentItem
    property Item shadow: WRectangularShadow {
        target: contentItem
    }
    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight

    children: [shadow, contentItem]
}
