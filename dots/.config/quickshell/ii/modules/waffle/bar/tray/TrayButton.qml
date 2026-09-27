pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.bar

BarIconButton {
    id: root

    required property SystemTrayItem item
    property alias menuOpen: menu.visible
    readonly property bool barAtBottom: Config.options.waffles.bar.bottom
    iconSource: root.item?.icon ?? ""
    iconScale: 0
    Component.onCompleted: {
        root.iconScale = 1;
    }
    Behavior on iconScale {
        animation: Looks.transition.enter.createObject(this)
    }

    onClicked: {
        root.item?.activate();
    }

    altAction: () => {
        if (root.item?.hasMenu) menu.open();
    }

    QsMenuAnchor {
        id: menu
        menu: root.item?.menu ?? null
        anchor {
            adjustment: PopupAdjustment.ResizeY | PopupAdjustment.SlideX
            item: root
            gravity: root.barAtBottom ? Edges.Top : Edges.Bottom
            edges: root.barAtBottom ? Edges.Top : Edges.Bottom
        }
    }

    BarToolTip {
        extraVisibleCondition: root.shouldShowTooltip && !root.Drag.active
        text: root.item ? TrayService.getTooltipForItem(root.item) : ""
    }
}
