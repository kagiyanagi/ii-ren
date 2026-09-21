import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import qs.modules.common.functions

Item {
    id: root
    property real spacing: 8

    property int startHour: 0
    property int startMinute: 0
    property int endHour: 24
    // Minutes, not milliseconds -- the old name read as an animation duration to
    // both the design checker and to anyone skimming the file.
    property int slotMinutes: 60
    property int slotHeight: 60 // in pixels
    property int timeColumnWidth: 100
    property real maxContentWidth: 1350

    readonly property int totalSlots: Math.floor(((endHour * 60) - (startHour * 60 + startMinute)) / slotMinutes)
    readonly property real pixelsPerMinute: slotHeight / slotMinutes
    readonly property int contentHeight: totalSlots * slotHeight

    property real maxHeight: 700
    property real headerHeight: 64 // Material 3 standard header height
    property real currentTimeY: -1
    property bool initialScrollApplied: false
    property var days: CalendarService.eventsInWeek
    // A week with no days divided by zero and rendered as a 108px sliver with a
    // lone clock in it. It gets the placeholder instead.
    readonly property bool hasDays: root.days?.length > 0
    readonly property real dayColumnWidth: !root.hasDays ? 0
        : Math.min(180, (maxContentWidth - timeColumnWidth - (days.length + 1) * spacing) / days.length)
    readonly property int currentDayIndex: (DateTime.clock.date.getDay() - Config.options.time.firstDayOfWeek+ 6)%7

    implicitWidth: !root.hasDays ? maxContentWidth
        : Math.min(maxContentWidth, timeColumnWidth + (dayColumnWidth * days.length) + ((days.length + 1) * spacing))
    implicitHeight: Math.min(headerHeight + contentHeight, maxHeight)
    readonly property color todayHighlightFill: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.12)
    readonly property color todayHighlightBorder: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.28)
    readonly property color dayBackgroundFill: ColorUtils.applyAlpha(Appearance.colors.colSecondary, 0.04)
    readonly property color dayBackgroundFillVariant: ColorUtils.applyAlpha(Appearance.colors.colSecondary, 0.08)

    function updateCurrentTimeLine() {
        let time = DateTime.clock.date;
        let hours = time.getHours();
        let minutes = time.getMinutes();

        let baseTotalMinutes = root.startHour * 60 + root.startMinute;
        let currentTotalMinutes = hours * 60 + minutes;
        let diffMinutes = currentTotalMinutes - baseTotalMinutes;

        currentTimeY = diffMinutes * root.pixelsPerMinute;
    }

    function isAllDayEvent(event) {
        if (!event)
            return false;

        let start = event.start || "";
        let end = event.end || "";

        return (start === "00:00" && end === "23:59") ||
               (start === "00:00" && end === "00:00") ||
               (!event.start && !event.end);
    }

    function getAllDayEvents(events) {
        if (!events || !events.length)
            return [];

        return events.filter(function(evt) { return root.isAllDayEvent(evt); });
    }

    function getTimedEvents(events) {
        if (!events || !events.length)
            return [];

        return events.filter(function(evt) { return !root.isAllDayEvent(evt); });
    }

    function formatEventTooltip(event) {
        if (!event)
            return "";

        let title = event.title || qsTr("Event");
        if (root.isAllDayEvent(event))
            return Translation.tr("All day event:") + "\n" + title;

        let description = event.description || "";

        let startTotal = root.parseTimeToMinutes(event.start);
        let endTotal = root.parseTimeToMinutes(event.end);

        let startStr = root.formatMinutes(startTotal) || event.start || "";
        let endStr = root.formatMinutes(endTotal) || event.end || "";
        let range = startStr && endStr ? startStr + " - " + endStr : startStr || endStr;
        return range ? description ? "•  " + title + "\n•  " + range + "\n•  " + description : "•  " +  title + "\n•  " + range : "•  " + title;
    }

    function formatMinutes(totalMinutes) {
        if (totalMinutes === null)
            return "";
        let date = new Date();
        date.setHours(Math.floor(totalMinutes / 60), totalMinutes % 60, 0, 0);
        return Qt.formatTime(date, Config.options?.time.format ?? "hh:mm");
    }

    function parseTimeToMinutes(timeStr) {
        if (!timeStr)
            return null;
        let parts = timeStr.split(":");
        if (parts.length < 2)
            return null;
        let hour = parseInt(parts[0]);
        let minute = parseInt(parts[1]);
        if (isNaN(hour) || isNaN(minute))
            return null;
        return hour * 60 + minute;
    }

    function earliestEventStartMinutes() {
        if (!root.days || root.days.length === 0)
            return -1;

        var earliest = -1;
        for (var i = 0; i < root.days.length; i++) {
            var timed = root.getTimedEvents(root.days[i]?.events);
            for (var j = 0; j < timed.length; j++) {
                var start = root.parseTimeToMinutes(timed[j].start);
                if (start === null)
                    continue;
                if (earliest === -1 || start < earliest)
                    earliest = start;
            }
        }
        return earliest;
    }

    function scrollToFirstEvent() {
        if (!styledFlickable)
            return;

        let earliest = root.earliestEventStartMinutes();
        let minOfDay = earliest;

        if (minOfDay === -1 || minOfDay <= (root.startHour * 60 + root.startMinute)) {
            styledFlickable.contentY = 0;
            return;
        }

        let diff = minOfDay - (root.startHour * 60 + root.startMinute);
        if (diff < 0)
            diff = 0;

        let targetY = diff * root.pixelsPerMinute - root.slotHeight;
        targetY = Math.max(0, targetY);

        let maxScroll = Math.max(0, styledFlickable.contentHeight - styledFlickable.height);
        if (styledFlickable.height <= 0) {
            Qt.callLater(root.scrollToFirstEvent);
            return;
        }
        styledFlickable.contentY = Math.min(targetY, maxScroll);
    }

    function maybeApplyInitialScroll() {
        if (root.initialScrollApplied)
            return;

        if (!styledFlickable || styledFlickable.height <= 0 || !root.days || root.days.length === 0) {
            Qt.callLater(root.maybeApplyInitialScroll);
            return;
        }

        root.scrollToFirstEvent();
        root.initialScrollApplied = true;
    }

    component TimeChip: Rectangle {
        required property real maxWidth
        readonly property int horizontalPadding: 8

        implicitWidth: Math.min(chipText.implicitWidth + horizontalPadding * 2, maxWidth)
        implicitHeight: 32
        radius: Appearance.rounding.normal
        color: Appearance.colors.colPrimary

        StyledText {
            id: chipText
            anchors.centerIn: parent
            width: parent.width - parent.horizontalPadding * 2
            horizontalAlignment: Text.AlignHCenter
            text: DateTime.time
            font.weight: Font.Medium
            color: Appearance.colors.colOnPrimary
            elide: Text.ElideRight
        }
    }

    Connections {
        target: DateTime.clock
        function onDateChanged() {
            root.updateCurrentTimeLine();
        }
    }

    Connections {
        target: CalendarService
        function onEventsInWeekChanged() {
            Qt.callLater(root.maybeApplyInitialScroll);
        }
    }

    Component.onCompleted: {
        root.updateCurrentTimeLine();
        Qt.callLater(root.maybeApplyInitialScroll);
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colSurfaceContainer
        radius: Appearance.rounding.large
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }

    PagePlaceholder {
        anchors.centerIn: parent
        shown: !root.hasDays
        icon: "calendar_month"
        title: Translation.tr("Nothing this week")
        description: Translation.tr("Events from your calendars show up here")
        descriptionHorizontalAlignment: Text.AlignHCenter
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: root.hasDays

        Row {
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: root.spacing

            Item {
                width: root.timeColumnWidth
                height: root.headerHeight

                // Current time indicator
                TimeChip {
                    anchors.centerIn: parent
                    maxWidth: parent.width - 8
                }
            }

            Repeater {
                model: root.days
                delegate: Item {
                    id: dayHeader
                    width: root.dayColumnWidth
                    height: root.headerHeight

                    readonly property var allDayEvents: root.getAllDayEvents(modelData.events)
                    readonly property bool isToday: index === root.currentDayIndex

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        height: 40
                        radius: Appearance.rounding.large
                        color: dayHeader.allDayEvents.length > 0 ? Appearance.colors.colPrimaryContainer
                            : dayHeader.isToday ? Appearance.colors.colPrimary
                            : Appearance.colors.colSurfaceContainerHigh

                        StyledText {
                            anchors.centerIn: parent
                            // An elide with no width never elides.
                            width: parent.width - 16
                            horizontalAlignment: Text.AlignHCenter
                            font.weight: Font.Medium
                            color: dayHeader.allDayEvents.length > 0 ? Appearance.colors.colOnPrimaryContainer
                                : dayHeader.isToday ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnSurfaceVariant
                            text: modelData.name
                            elide: Text.ElideRight
                        }

                        HoverHandler {
                            id: allDayHover
                        }

                        // The pill's recolour is the all-day indicator, and this
                        // is how you read them. It used to be a column of
                        // transparent rectangles, anchored horizontally but not
                        // vertically so they spilled out of the 40px pill, each
                        // holding a tooltip bound to *this* handler -- so one
                        // hover popped every one of that day's tooltips at once.
                        StyledToolTip {
                            extraVisibleCondition: allDayHover.hovered && dayHeader.allDayEvents.length > 0
                            text: dayHeader.allDayEvents.map(event => root.formatEventTooltip(event)).join("\n")
                        }
                    }
                }
            }
        }

        // Whitespace on the grid, not a hairline (law 11).
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 12
        }

        StyledFlickable {
            id: styledFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true

            clip: true
            contentWidth: width
            contentHeight: root.contentHeight
            topMargin: 20
            bottomMargin: 20

            Row {
                id: contentRow
                spacing: root.spacing

                Column {
                    id: timeColumn
                    width: root.timeColumnWidth

                    Repeater {
                        model: root.totalSlots
                        delegate: Item {
                            width: parent.width
                            height: root.slotHeight

                            StyledText {
                                text: root.formatMinutes(root.startHour * 60 + root.startMinute + index * root.slotMinutes)
                                anchors.top: parent.top
                                anchors.topMargin: -font.pixelSize / 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Row {
                    id: eventsRow
                    height: root.contentHeight
                    spacing: root.spacing

                    Repeater {
                        id: daysRepeater
                        model: root.days
                        delegate: Item {
                            width: root.dayColumnWidth
                            height: parent.height
                            clip: true
                            
                            property bool isToday: index === root.currentDayIndex
                            property var timedEvents: root.getTimedEvents(modelData.events)

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.large
                                color: isToday ? root.todayHighlightFill : index % 2 == 0 ? root.dayBackgroundFill : root.dayBackgroundFillVariant
                                border.width: isToday ? 1 : 0
                                border.color: isToday ? root.todayHighlightBorder : "transparent"
                            }

                            Repeater {
                                model: timedEvents
                                Rectangle {
                                    id: eventCard
                                    // An event with no colour of its own fell
                                    // back to colTertiaryContainer here but had
                                    // its label contrast computed from the
                                    // *undefined* original -- a NaN luminance
                                    // fails `< 0.5` and returns black, on a dark
                                    // card. Both read the colour on screen.
                                    readonly property color fill: modelData.color || Appearance.colors.colTertiaryContainer
                                    readonly property color onFill: ColorUtils.getContrastingTextColor(eventCard.fill)

                                    width: parent.width - 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    radius: Appearance.rounding.normal
                                    clip: true
                                    y: (root.parseTimeToMinutes(modelData.start) - (root.startHour * 60 + root.startMinute)) * root.pixelsPerMinute
                                    height: {
                                        let totalMins = root.parseTimeToMinutes(modelData.end) - root.parseTimeToMinutes(modelData.start);
                                        return Math.max(totalMins * root.pixelsPerMinute - 4, 48); // Minimum height for touch targets
                                    }

                                    color: eventCard.fill

                                    HoverHandler {
                                        id: eventHover
                                    }

                                    StyledToolTip {
                                        extraVisibleCondition: eventHover.hovered
                                        text: root.formatEventTooltip(modelData)
                                    }

                                    Column {
                                        anchors {
                                            fill: parent
                                            margins: 8
                                        }
                                        spacing: 4

                                        StyledText {
                                            id: eventTitle
                                            text: modelData.title

                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            width: parent.width
                                            color: eventCard.onFill
                                        }

                                        StyledText {
                                            text: root.formatMinutes(root.parseTimeToMinutes(modelData.start))
                                                + " - " + root.formatMinutes(root.parseTimeToMinutes(modelData.end))
                                            font.weight: Font.Medium
                                            width: parent.width
                                            wrapMode: Text.NoWrap
                                            color: eventCard.onFill
                                            elide: Text.ElideRight
                                            visible: !truncated
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: currentTimeLine
                width: contentRow.width + root.spacing * 2
                height: 4
                color: Appearance.colors.colPrimary
                y: root.currentTimeY
                visible: root.currentTimeY >= 0 && root.currentTimeY <= contentRow.height
                z: 10
                radius: Appearance.rounding.unsharpen

                Behavior on y {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                // Material 3 time chip
                TimeChip {
                    x: (timeColumn.width / 2) - (width / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    maxWidth: timeColumn.width - 8
                }
            }
        }
    }
}

