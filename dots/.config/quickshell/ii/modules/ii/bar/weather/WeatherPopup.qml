import qs.modules.ii.bar
import qs.services
import qs.modules.common
import "../cards"

import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    stickyHover: true

    required property bool compact
    property bool compactMode: Config.options.bar.tooltips.compactPopups
    property int cardMargins: 16

    // Forecast data model bound to central Weather singleton
    property var forecastData: Weather.forecastData
    property var hourlyData: Weather.hourlyData
    property bool forecastLoading: Weather.forecastLoading
    property int maxHourlyBars: 5

    // Weather.data ships a complete placeholder reading - 0 degrees, city
    // "City", sunrise at 00:00 - so a popup that renders it unconditionally
    // states four wrong numbers with total confidence. wmoCode starts at -1
    // and is the one field refineData always overwrites, so it is what says
    // whether any of the rest is a measurement.
    readonly property bool hasReading: (Weather.data?.wmoCode ?? -1) >= 0

    // Nothing in the service tells the user a fetch failed. A hard failure
    // drops forecastLoading with nothing to show; a geocoding miss - a
    // misspelt city - comes back 200 with no results, returns early, and
    // leaves forecastLoading true for good with no retry timer behind it, so
    // the popup spins forever. Bound the wait by the service's own budget and
    // treat anything past it as failed. Repeating, because a fetch that stops
    // and restarts must be able to stall again; it stops on its own the moment
    // loading ends or a reading lands.
    //
    // Declared as a property rather than as a plain child: StyledPopup's
    // default property is `contentItem`, so a bare Timer here is assigned as
    // the popup's content and the real one becomes a duplicate binding.
    property bool fetchStalled: false

    readonly property Timer fetchDeadline: Timer {
        running: root.forecastLoading && !root.hasReading
        repeat: true
        interval: Weather.requestTimeout * (Weather.requestRetries + 1) + Weather.retryDelay * Weather.requestRetries
        onTriggered: root.fetchStalled = true
    }

    property var filteredHourlyData: {
        const now = new Date();
        const currentHr = now.getHours();
        // Round down to nearest 3-hour slot (API intervals: 0, 3, 6, 9, 12, 15, 18, 21)
        const currentSlot = Math.floor(currentHr / 3) * 3;
        const hours = root.hourlyData ?? [];
        let futureHours = [];
        let passedMidnight = false;

        for (let i = 0; i < hours.length; i++) {
            const item = hours[i];
            const itemHour = Math.floor(parseInt(item.time) / 100);

            if (i > 0 && itemHour < Math.floor(parseInt(hours[i - 1].time) / 100)) {
                passedMidnight = true;
            }

            if (passedMidnight || itemHour >= currentSlot) {
                futureHours.push(item);
            }
        }
        return futureHours.slice(0, root.maxHourlyBars);
    }

    // Read for the status line, not to drive a refetch: Weather watches the
    // city itself through fetchKey, debounced and forced, so the onCityChanged
    // that used to sit here only raced that with an unforced call the rate
    // limit then dropped.
    readonly property string city: Config.options.bar.weather.city

    function fetchForecast() {
        Weather.getData();
    }

    // Re-opening is the retry. getData is rate limited to once a minute and
    // request() drops a second call for a label already in flight, so hovering
    // at the popup cannot turn into a request storm.
    onOpenedChanged: {
        if (root.opened && !root.hasReading)
            root.fetchForecast();
    }

    function getDayName(dateStr, index) {
        if (index === 0)
            return Translation.tr("Today");
        if (index === 1)
            return Translation.tr("Tomorrow");
        const date = new Date(dateStr);
        const days = [Translation.tr("Sun"), Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"), Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat")];
        return days[date.getUTCDay()];
    }

    function formatHour(timeStr) {
        const hour = Math.floor(parseInt(timeStr) / 100);
        return hour.toString().padStart(2, '0') + ":00";
    }

    function getHourlyTempRange() {
        const data = root.filteredHourlyData.length > 0 ? root.filteredHourlyData : (root.hourlyData ?? []);
        // Math.max(x, 1) downstream does NOT clamp a NaN away - Math.max(NaN, 1)
        // is NaN, and so is every bar height derived from it, which lands an
        // undefined height on the chart rather than a short bar. parseInt over a
        // missing or malformed temperature is the way in, and the service can
        // emit one: refineData walks hourly.time but reads hourly.temperature_2m
        // at the same index without checking it is as long. Drop the non-finite
        // readings here, at the one place both of HourlyForecast's callers route
        // through, rather than guarding the division at each of them.
        // Guarded by tools/check-weather-hourly.py.
        const temps = data.map(h => Weather.useUSCS ? parseInt(h?.tempF) : parseInt(h?.tempC)).filter(t => isFinite(t));
        if (temps.length === 0)
            return {
                min: 0,
                max: 100
            };
        const min = Math.min(...temps);
        const max = Math.max(...temps);
        // Add 20% padding (minimum 2°) to make small differences more visible -
        // and, because the minimum is unconditional, to keep a single hour or a
        // flat run from collapsing the span to zero and dividing by it.
        const padding = Math.max(2, (max - min) * 0.2);
        return {
            min: min - padding,
            max: max + padding
        };
    }

    Component.onCompleted: root.fetchForecast()

    // One entrance for every child of every popup in this cluster, so its
    // contents cannot drift apart: siblings enter together, offset by
    // staggerStep and capped (DESIGN.md 2.8), each with opacity on an effects
    // spec and exactly one transform on a spatial one (2.1). The two
    // PropertyActions are the reset 2.7 asks for, at the head of the animation
    // rather than in a handler somewhere - the previous entrance's final frame
    // is what a reopen would otherwise show for the length of the stagger.
    //
    // There is no matching exit, deliberately: the popup surface scales and
    // fades out as one (cluster Contract 1), and a second fade running inside
    // it reads as a stutter rather than as the content leaving.
    component CardEnter: SequentialAnimation {
        id: entrance

        required property Item card
        required property Translate shift
        required property int slot

        // How far the card travels into place: a short move toward where it
        // belongs, not a slide in from off the surface. It lives here so the
        // resting offset has one owner and the Translates below can stay bare.
        readonly property int fromShift: 12

        PropertyAction {
            target: entrance.card
            property: "opacity"
            value: 0
        }
        PropertyAction {
            target: entrance.shift
            property: "y"
            value: entrance.fromShift
        }
        PauseAnimation {
            duration: Appearance.animation.staggerStep * Math.min(entrance.slot, Appearance.animation.staggerCap)
        }
        ParallelAnimation {
            NumberAnimation {
                target: entrance.card
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            NumberAnimation {
                target: entrance.shift
                property: "y"
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }
    }

    contentItem: ColumnLayout {
        id: contentLayout
        spacing: 12

        // The content enters with the surface, not 60% of the way through it.
        // The cards read this to run their own internals.
        readonly property bool startAnim: root.opened

        onStartAnimChanged: {
            if (startAnim)
                enterAnim.restart();
        }

        ParallelAnimation {
            id: enterAnim

            CardEnter {
                card: weatherStatus
                shift: weatherStatusShift
                slot: 0
            }
            CardEnter {
                card: weatherHero
                shift: weatherHeroShift
                slot: 0
            }
            CardEnter {
                card: hourlyForecast
                shift: hourlyForecastShift
                slot: 1
            }
            CardEnter {
                card: metricsGrid
                shift: metricsGridShift
                slot: 2
            }
            CardEnter {
                card: inDayForecast
                shift: inDayForecastShift
                slot: 3
            }
        }

        // Every block below needs a reading to say anything true, so with none
        // the popup is this one line instead of a hero full of placeholder
        // numbers over three empty cards. It covers all three ways there can be
        // nothing: still fetching, no city configured (the service falls back
        // to locating by IP, which is a wait, not an error), and a fetch that
        // failed or stalled. LoadingPlaceholder already draws both halves.
        LoadingPlaceholder {
            id: weatherStatus
            visible: !root.hasReading
            Layout.minimumWidth: 240
            loading: root.forecastLoading && !root.fetchStalled
            loadingText: root.city === "" ? Translation.tr("Finding your location...") : Translation.tr("Getting weather for %1...").arg(root.city)
            emptyText: Translation.tr("No weather right now. Hover again to retry.")

            opacity: 0
            transform: Translate {
                id: weatherStatusShift
            }
        }

        HeroCard {
            id: weatherHero
            visible: root.hasReading
            Layout.minimumWidth: 320
            margins: 20
            iconSize: 100
            iconUrl: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, Weather.isNight)
            pillText: Weather.data.city || "--"
            pillIcon: Weather.data.city ? "location_on" : ""
            title: Weather.data.temp
            subtitle: Weather.data.wDesc
            startAnim: contentLayout.startAnim

            opacity: 0
            transform: Translate {
                id: weatherHeroShift
            }
        }

        HourlyForecast {
            id: hourlyForecast
            visible: !root.compact && root.hasReading
            spacing: 6

            icon: "schedule"
            title: Translation.tr("Hourly")
            headerExtraText: Translation.tr("Last refresh: %1").arg(Weather.data.lastRefresh || "--").slice(0, 20)

            shapeString: "Clover4Leaf"
            shapeColor: Appearance.colors.colSecondaryContainer
            symbolColor: Appearance.colors.colOnSecondaryContainer

            Layout.minimumWidth: 360
            margins: root.cardMargins
            startAnim: contentLayout.startAnim

            opacity: 0
            transform: Translate {
                id: hourlyForecastShift
            }
        }

        MetricsGrid {
            id: metricsGrid
            visible: !root.compact && root.hasReading

            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8
            uniformCellWidths: true
            startAnim: contentLayout.startAnim

            opacity: 0
            transform: Translate {
                id: metricsGridShift
            }
        }

        InDayForecast {
            id: inDayForecast
            visible: !root.compact && root.hasReading

            Layout.minimumWidth: 360
            margins: root.cardMargins
            spacing: 8
            shapeString: "Cookie6Sided"
            shapeColor: Appearance.colors.colSecondaryContainer
            symbolColor: Appearance.colors.colOnSecondaryContainer
            title: Translation.tr("Forecast")
            icon: "calendar_month"
            startAnim: contentLayout.startAnim

            opacity: 0
            transform: Translate {
                id: inDayForecastShift
            }
        }
    }
}
