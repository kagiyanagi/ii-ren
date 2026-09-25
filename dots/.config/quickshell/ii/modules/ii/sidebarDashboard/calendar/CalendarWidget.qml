import QtQuick
import QtQuick.Layouts
import Quickshell
import "calendar_layout.js" as CalendarLayout
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property int monthShift: 0
    property var locale: Qt.locale(Config.options.calendar.locale)
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0, Config.options.time.firstDayOfWeek)

    anchors.topMargin: 10
    width: calendarColumn.width
    implicitHeight: calendarColumn.height + 10 * 2
    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown)
                monthShift++;
            else if (event.key === Qt.Key_PageUp)
                monthShift--;
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (event.angleDelta.y > 0)
                monthShift--;
            else if (event.angleDelta.y < 0)
                monthShift++;
        }
    }

    ColumnLayout {
        id: calendarColumn

        anchors.centerIn: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            CalendarHeaderButton {
                clip: true
                buttonText: `${monthShift != 0 ? "• " : ""}${viewingDate.toLocaleDateString(root.locale, "MMMM yyyy")}`
                tooltipText: (monthShift === 0) ? "" : Translation.tr("Jump to current month")
                downAction: () => {
                    monthShift = 0;
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }

            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift--;
                }

                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }

            }

            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift++;
                }

                contentItem: MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }

            }

        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: calendarColumn.spacing

            Repeater {
                model: 7

                delegate: StyledText {
                    required property int index
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignHCenter
                    // Qt counts days from Sunday, firstDayOfWeek from Monday
                    text: root.locale.dayName((index + Config.options.time.firstDayOfWeek + 1) % 7, Locale.NarrowFormat)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        Repeater {
            model: 6

            delegate: RowLayout {
                id: week
                required property int index
                Layout.alignment: Qt.AlignHCenter
                spacing: calendarColumn.spacing

                Repeater {
                    model: 7

                    delegate: CalendarDayButton {
                        id: day
                        required property int index
                        cell: root.calendarLayout[week.index][index]
                        onShowsEventsChanged: {
                            if (day.showsEvents)
                                eventCard.show(day);
                            else if (eventCard.cell === day)
                                eventCard.hide();
                        }
                    }
                }
            }
        }
    }

    CalendarPopup {
        id: eventCard
        parent: root.QsWindow?.contentItem ?? root
        maxWidth: calendarColumn.width
        locale: root.locale
    }
}
