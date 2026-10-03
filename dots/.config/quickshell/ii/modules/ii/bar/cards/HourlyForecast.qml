import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.animations

SectionCard {
    id: hourlyForecastCard
    property int hourlyChartHeight: 144

    // Internal animation control
    property bool startAnim: false

    onStartAnimChanged: {
        if (!hourlyForecastCard.startAnim) return;
        for (let i = 0; i < barRepeater.count; i++) {
            const item = barRepeater.itemAt(i);
            if (!item) continue;
            item.barOpacity = 0.0;
            item.barHeightAnim = 0;
        }
        Qt.callLater(() => {
            for (let j = 0; j < barRepeater.count; j++) {
                const bar = barRepeater.itemAt(j);
                if (!bar) continue;
                // Siblings staggerStep apart, capped (DESIGN.md 2.8): a 24-hour
                // forecast past the cap reads as broken, not choreographed.
                bar.barAnimDelay = Appearance.animation.staggerStep * Math.min(j, Appearance.animation.staggerCap);
                bar.startBarAnim();
            }
        });
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: hourlyForecastCard.hourlyChartHeight
        visible: !root.forecastLoading && root.filteredHourlyData.length > 0

        property var tempRange: root.getHourlyTempRange()
        property real tempSpan: Math.max(tempRange.max - tempRange.min, 1)

        RowLayout {
            anchors.fill: parent
            spacing: 6

            Repeater {
                id: barRepeater
                model: root.filteredHourlyData

                Item {
                    id: barItem
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    required property var modelData
                    required property int index

                    property int hourValue: Math.floor(parseInt(modelData.time) / 100)
                    property bool isCurrentHour: index === 0
                    property real temp: Weather.useUSCS ? parseInt(modelData.tempF) : parseInt(modelData.tempC)
                    property var parentTempRange: root.getHourlyTempRange()
                    property real parentTempSpan: Math.max(parentTempRange.max - parentTempRange.min, 1)
                    // A missing or unparseable temperature makes this NaN, and a
                    // NaN bar height draws nothing and warns every frame. Clamp,
                    // and fall back to the bottom of the range.
                    property real normalized: {
                        const n = (barItem.temp - barItem.parentTempRange.min) / barItem.parentTempSpan;
                        return isFinite(n) ? Math.max(0, Math.min(1, n)) : 0;
                    }
                    // Bar height: 45% min to 100% max for better visual contrast
                    property real availableBarSpace: Math.max(0, barItem.parent.height - timeLabel.height + 10)
                    property real barHeight: availableBarSpace * (0.45 + normalized * 0.55)

                    // Animation properties
                    property real barOpacity: 1.0
                    property real barHeightAnim: barHeight
                    property int barAnimDelay: 0

                    function startBarAnim() {
                        barAnim.restart();
                    }

                    // Opacity on an effects spec, one transform -- the bar's own
                    // growth -- on the enter spec (DESIGN.md 2.1, 2.5).
                    ParallelAnimation {
                        id: barAnim

                        DelayedPropertyAnimation {
                            target: barItem
                            property: "barOpacity"
                            from: 0
                            to: 1
                            delay: barItem.barAnimDelay
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                        DelayedPropertyAnimation {
                            target: barItem
                            property: "barHeightAnim"
                            from: 0
                            to: barItem.barHeight
                            delay: barItem.barAnimDelay
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                        }
                    }

                    StyledText {
                        id: timeLabel
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.formatHour(modelData.time)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: isCurrentHour ? Font.Bold : Font.Normal
                        color: isCurrentHour ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        opacity: barItem.barOpacity
                    }

                    Rectangle {
                        id: barRect
                        anchors.bottom: timeLabel.top
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        height: barItem.barHeightAnim
                        radius: Appearance.rounding.normal
                        color: isCurrentHour ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                        opacity: barItem.barOpacity
                        transformOrigin: Item.Bottom

                        ColumnLayout {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: 8
                            spacing: 2

                            Image {
                                id: weatherIcon
                                Layout.alignment: Qt.AlignHCenter
                                source: WeatherIcons.getWeatherIcon(modelData.code ?? 113, modelData.isNight ?? false)
                                sourceSize: Qt.size(Appearance.font.pixelSize.large, Appearance.font.pixelSize.large)
                                opacity: barItem.barOpacity
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: barItem.temp + "°"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: isCurrentHour ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                                opacity: barItem.barOpacity
                            }
                        }

                        Rectangle {
                            visible: isCurrentHour
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            width: 20
                            height: 20
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimary
                            opacity: barItem.barOpacity

                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
        }
    }

    LoadingPlaceholder {
        Layout.preferredHeight: hourlyForecastCard.hourlyChartHeight
        visible: root.forecastLoading || root.filteredHourlyData.length === 0
        loading: root.forecastLoading
        loadingText: Translation.tr("Loading forecast…")
        emptyText: Translation.tr("No forecast data")
        // A fetch ran and came back with nothing: say so, rather than leaving
        // the card reading as "loading forever".
        errorText: Weather.lastFetchTimestamp > 0 ? Translation.tr("Couldn't load the forecast") : ""
    }
}