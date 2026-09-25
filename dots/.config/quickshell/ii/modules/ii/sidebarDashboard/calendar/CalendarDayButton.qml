import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

// Not a RippleButton: that keeps a layer and an OpacityMask per instance for its
// ripple, and the grid is 42 of these (DESIGN.md 8). Hover and press still land.
Rectangle {
    id: root

    // today: 1 is today, 0 is this month, -1 spills over from a neighbouring one
    required property var cell
    readonly property var date: new Date(cell.year, cell.month, cell.day)
    readonly property bool isToday: cell.today === 1
    readonly property var events: cell.today === -1 ? [] : CalendarService.getTasksByDate(date)
    readonly property bool showsEvents: events.length > 0 && (mouse.containsMouse || activeFocus)

    function openDay(): void {
        Qt.openUrlExternally(`https://calendar.google.com/calendar/r/day/${root.cell.year}/${root.cell.month + 1}/${root.cell.day}`);
    }

    implicitWidth: 40
    implicitHeight: 40
    radius: Appearance.rounding.full
    // Tab only: a click never focuses a Rectangle, so focus is the keyboard's alone.
    // It shares pressed's 0.10 layer (DESIGN.md 3.1).
    activeFocusOnTab: true
    Keys.onReturnPressed: root.openDay()
    Keys.onSpacePressed: root.openDay()
    color: isToday
        ? (mouse.pressed || activeFocus ? Appearance.colors.colPrimaryActive : mouse.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
        : (mouse.pressed || activeFocus ? Appearance.colors.colLayer1Active : mouse.containsMouse ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1))
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    StyledText {
        anchors.centerIn: parent
        text: root.cell.day
        color: root.isToday ? Appearance.colors.colOnPrimary : root.cell.today === 0 ? Appearance.colors.colOnLayer1 : Appearance.colors.colOutlineVariant
    }

    // M3's small badge: 6dp
    Rectangle {
        visible: root.events.length > 0
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 4
        }
        width: 6
        height: 6
        radius: Appearance.rounding.full
        color: root.isToday ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // clicked, not released: a press dragged off the day opens nothing
        onClicked: root.openDay()
    }
}
