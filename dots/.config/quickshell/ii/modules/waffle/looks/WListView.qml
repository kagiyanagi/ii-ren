pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import QtQuick
import QtQuick.Controls

ListView {
    id: root

    boundsBehavior: Flickable.DragOverBounds

    ScrollBar.vertical: WScrollBar {}

    displaced: Transition {
        animations: [Looks.transition.enter.createObject(this, {
                property: "y"
            })]
    }

}
