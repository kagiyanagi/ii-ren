pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "weather_math.js" as WMath

// Everything the weather service knows, in Pixel Weather's order: now, the
// next day, the week, then the details. The bar popup is the glance; this is
// the read. A status page, so nothing on it takes a click, and the hero is its
// one loud thing.
Item {
    id: root

    // Whether this is the cheatsheet's current tab. The weather only runs, and
    // the entrance only plays, while it is.
    property bool live: true

    readonly property var d: Weather.data
    readonly property bool us: Weather.useUSCS
    // wmoCode starts at -1 and is the one field every fetch overwrites, so it
    // says whether the rest is a measurement or the service's placeholder
    // (0 degrees in "City").
    readonly property bool hasReading: (root.d?.wmoCode ?? -1) >= 0
    readonly property var today: Weather.forecastData[0] ?? null

    readonly property int minutes: WMath.locationMinutes(DateTime.clock.date.getTime(),
        root.d?.utcOffset ?? -DateTime.clock.date.getTimezoneOffset() * 60)
    // An int, so the hourly columns rebuild when the slot turns over rather
    // than every time the clock ticks.
    readonly property int slot: Math.floor(root.minutes / 180)
    readonly property var hours: WMath.nextDay(Weather.hourlyData, root.slot)
    readonly property var hourSpan: WMath.span(root.hours.map(h => root.hourTemp(h)), 2)
    readonly property var weekSpan: WMath.span(Weather.forecastData.map(f => root.us ? f.minF : f.minC)
        .concat(Weather.forecastData.map(f => root.us ? f.maxF : f.maxC)), 0)

    readonly property int gaugeSize: 72
    readonly property int iconSize: 32

    function hourTemp(h) { return parseInt(root.us ? h.tempF : h.tempC) }
    function deg(v) { return Number.isFinite(v) ? Math.round(v) + "°" : "--" }
    function unitless(t) { return String(t ?? "--").replace(/[CF]$/, "") }
    function hourLabel(time) {
        return Qt.locale().toString(new Date(2000, 0, 1, Math.floor(parseInt(time) / 100)), Config.options.time.format);
    }
    // WHO's bands, on the rounded index so the number and its word agree.
    function uvLevel(uv) {
        const u = Math.round(uv ?? 0);
        return u < 3 ? Translation.tr("Low") : u < 6 ? Translation.tr("Moderate")
            : u < 8 ? Translation.tr("High") : u < 11 ? Translation.tr("Very high") : Translation.tr("Extreme");
    }
    function visibilityLevel(m) {
        if (!Number.isFinite(m)) return "";
        return m >= 10000 ? Translation.tr("Clear view") : m >= 4000 ? Translation.tr("Good")
            : m >= 1000 ? Translation.tr("Hazy") : Translation.tr("Fog");
    }

    // A failed fetch leaves nothing to show, and a geocoding miss (a misspelt
    // city) leaves forecastLoading up for good, so the wait is bounded by the
    // service's own retry budget -- the bar popup's rule.
    property bool stalled: false
    readonly property bool loading: Weather.forecastLoading && !root.stalled
    Timer {
        running: root.live && Weather.forecastLoading && !root.hasReading
        repeat: true
        interval: Weather.requestTimeout * (Weather.requestRetries + 1) + Weather.retryDelay * Weather.requestRetries
        onTriggered: root.stalled = true
    }
    // Coming back to the tab is the retry. getData is rate limited and drops a
    // request already in flight, so this cannot storm.
    onLiveChanged: if (root.live && !root.hasReading) {
        root.stalled = false;
        Weather.getData();
    }

    // The entrance plays each time the page comes into view with something to
    // show. There is no matching exit on purpose: the page slides out as one
    // and the sheet scales out as one, and a second fade inside either reads
    // as a stutter (the weather popup's reasoning).
    readonly property bool showing: root.live && root.hasReading
    onShowingChanged: if (root.showing) entrance.restart()
    Component.onCompleted: if (root.showing) entrance.restart()

    // 0 -> 1 behind the cards: what the graph, the range bars, the gauges and
    // the sun ride out to their readings on. Decelerating and never past 1 --
    // a gauge that swings past its value reports a number that never happened.
    property real fill: 1
    // The compass needle is a pointer, not a gauge, so it swings on the
    // spatial spec and may overshoot the bearing and settle.
    property real needle: 1
    // A short move toward where each card belongs, as the weather popup's do.
    readonly property int travel: 16

    component Rise: SequentialAnimation {
        id: rise
        required property Item card
        required property int order
        PropertyAction { target: rise.card; property: "opacity"; value: 0 }
        PropertyAction { target: rise.card; property: "lift"; value: root.travel }
        PauseAnimation {
            duration: Appearance.animation.staggerStep * Math.min(rise.order, Appearance.animation.staggerCap)
        }
        ParallelAnimation {
            NumberAnimation {
                target: rise.card
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            NumberAnimation {
                target: rise.card
                property: "lift"
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }
    }

    ParallelAnimation {
        id: entrance
        Rise { card: hero; order: 0 }
        Rise { card: hourly; order: 1 }
        Rise { card: week; order: 2 }
        Rise { card: uvTile; order: 3 }
        Rise { card: humidityTile; order: 4 }
        Rise { card: windTile; order: 5 }
        Rise { card: pressureTile; order: 6 }
        Rise { card: sunTile; order: 6 }
        Rise { card: rainTile; order: 6 }
        Rise { card: visibilityTile; order: 6 }
        SequentialAnimation {
            PropertyAction { target: root; property: "fill"; value: 0 }
            PropertyAction { target: root; property: "needle"; value: 0 }
            PauseAnimation { duration: Appearance.animation.staggerStep * 3 }
            ParallelAnimation {
                NumberAnimation {
                    target: root
                    property: "fill"
                    to: 1
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
                NumberAnimation {
                    target: root
                    property: "needle"
                    to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                }
            }
        }
    }

    component Card: Rectangle {
        id: card
        property real lift: 0
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        transform: Translate { y: card.lift }
    }

    component CardHeader: RowLayout {
        id: header
        property string icon
        property string title
        Layout.fillWidth: true
        spacing: 8
        MaterialSymbol {
            text: header.icon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            text: header.title
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    component Tile: Card {
        id: tile
        property alias icon: head.icon
        property alias title: head.title
        default property alias content: body.data
        Layout.fillWidth: true
        Layout.fillHeight: true
        CardHeader {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
        }
        Item {
            id: body
            anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16; topMargin: 8 }
        }
    }

    component Value: StyledText {
        Layout.fillWidth: true
        animateChange: true
        font.family: Appearance.font.family.numbers
        font.pixelSize: Appearance.font.pixelSize.hugeass * 1.25
        font.variableAxes: Appearance.font.variableAxes.title
        color: Appearance.colors.colOnSurface
    }

    component Note: StyledText {
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.smallie
        color: Appearance.colors.colOnSurfaceVariant
    }

    component Temp: StyledText {
        font.family: Appearance.font.family.numbers
        font.pixelSize: Appearance.font.pixelSize.normal
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: tempMetrics.advanceWidth
    }

    TextMetrics {
        id: tempMetrics
        font.family: Appearance.font.family.numbers
        font.pixelSize: Appearance.font.pixelSize.normal
        text: "-00°"
    }

    // Nothing on the page says anything true without a reading, so without one
    // it is a single status: still fetching, or failed with the way out.
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.hasReading && root.loading
        spacing: 12
        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            loading: parent.visible
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Weather.city === "" ? Translation.tr("Finding your location...")
                : Translation.tr("Getting weather for %1...").arg(Weather.city)
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
    PagePlaceholder {
        shown: !root.hasReading && !root.loading
        icon: "cloud_off"
        title: Translation.tr("No weather right now")
        description: Translation.tr("Check the connection, or the city in Settings > Services. Coming back to this tab tries again.")
        descriptionHorizontalAlignment: Text.AlignHCenter
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.hasReading
        spacing: 12

        Card {
            id: hero
            Layout.fillWidth: true
            Layout.preferredHeight: root.height * 0.3
            color: "transparent"

            Rectangle {
                id: sky
                anchors.fill: parent
                radius: hero.radius
                color: Appearance.colors.colPrimaryContainer
            }

            // AOSP's live weather wallpaper effects -- the shaders the desktop
            // runs -- over the sky: rain on the glass, snow, fog or sun, as
            // thick as the conditions call for, thickening in over AOSP's 3s
            // ramp. A shader pass per frame over one card is the feature
            // (TASTE 7), and it only runs while this tab is on screen; leaving
            // freezes it on its last frame for the slide out.
            WeatherEffects {
                id: fx
                anchors.fill: parent
                scene: sky
                paused: !root.live
                opt: ({ enable: true, followWeather: true, scale: 100, colorGrading: false })
                otherOpt: ({})
                // Held through the ramp out too, or the fog shader loses its
                // textures while it is still thinning.
                everConfigured: Weather.liveEffect.length > 0 || fx.takesOver
            }

            // Keeps the reading legible through the thickest weather -- fog at
            // 0.8 is nearly the text's own colour. The weather keeps the right
            // half, where the icon is.
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width / 2
                topLeftRadius: hero.radius
                bottomLeftRadius: hero.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Appearance.colors.colPrimaryContainer }
                    GradientStop { position: 1; color: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1) }
                }
            }

            ColumnLayout {
                anchors { left: parent.left; right: heroIcon.left; verticalCenter: parent.verticalCenter; margins: 24 }
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    animateChange: true
                    text: root.unitless(root.d.temp)
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.hugeass * 3
                    font.variableAxes: Appearance.font.variableAxes.numbers
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    animateChange: true
                    text: root.d.wDesc
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.variableAxes: Appearance.font.variableAxes.title
                    color: Appearance.colors.colOnPrimaryContainer
                }
                RowLayout {
                    Layout.topMargin: 4
                    spacing: 16
                    Repeater {
                        model: [
                            Translation.tr("Feels like %1").arg(root.unitless(root.d.tempFeelsLike)),
                            Translation.tr("High %1").arg(root.deg(root.us ? root.today?.maxF : root.today?.maxC)),
                            Translation.tr("Low %1").arg(root.deg(root.us ? root.today?.minF : root.today?.minC))
                        ]
                        delegate: StyledText {
                            required property string modelData
                            text: modelData
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }

            Rectangle {
                anchors { top: parent.top; right: parent.right; margins: 20 }
                implicitWidth: placeRow.implicitWidth + 24
                implicitHeight: placeRow.implicitHeight + 12
                radius: Appearance.rounding.full
                color: Appearance.colors.colOnPrimary
                RowLayout {
                    id: placeRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "location_on"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        Layout.maximumWidth: hero.width / 3
                        text: root.d.city
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }

            Image {
                id: heroIcon
                anchors { right: parent.right; bottom: parent.bottom; margins: 24 }
                width: Math.min(hero.height * 0.6, 160)
                height: width
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectFit
                source: WeatherIcons.getWeatherIcon(root.d.wCode ?? 113, Weather.isNight)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                Card {
                    id: hourly
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.height * 0.3

                    ColumnLayout {
                        anchors { fill: parent; margins: 16 }
                        spacing: 8

                        CardHeader {
                            icon: "schedule"
                            title: Translation.tr("Next 24 hours")
                        }

                        Item {
                            id: plotArea
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            readonly property real col: width / Math.max(1, root.hours.length)
                            // Room above the highest point for its label.
                            readonly property real band: Appearance.font.pixelSize.normal * 2

                            // The line draws in left to right: the clip widens,
                            // the graph under it never repaints.
                            Item {
                                id: plot
                                x: plotArea.col / 2
                                y: plotArea.band
                                width: (plotArea.width - plotArea.col) * root.fill
                                height: plotArea.height - plotArea.band
                                clip: true
                                Graph {
                                    width: plotArea.width - plotArea.col
                                    height: plot.height
                                    values: root.hours.map(h => WMath.position(root.hourTemp(h), root.hourSpan))
                                    color: Appearance.colors.colPrimary
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                }
                            }

                            Repeater {
                                model: root.hours
                                delegate: StyledText {
                                    required property var modelData
                                    required property int index
                                    readonly property real temp: root.hourTemp(modelData)
                                    x: plotArea.col * (index + 0.5) - width / 2
                                    y: plot.y + (1 - WMath.position(temp, root.hourSpan)) * plot.height - height - 4
                                    // Each reading arrives as the line reaches it.
                                    opacity: Math.max(0, Math.min(1, root.fill * (root.hours.length - 1) - index + 1))
                                    text: root.deg(temp)
                                    font.family: Appearance.font.family.numbers
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                        }

                        Row {
                            Layout.fillWidth: true
                            Repeater {
                                model: root.hours
                                delegate: ColumnLayout {
                                    required property var modelData
                                    required property int index
                                    width: plotArea.col
                                    spacing: 2
                                    Image {
                                        Layout.alignment: Qt.AlignHCenter
                                        sourceSize: Qt.size(root.iconSize, root.iconSize)
                                        source: WeatherIcons.getWeatherIcon(parseInt(modelData.code), modelData.isNight)
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: index === 0 ? Translation.tr("Now") : root.hourLabel(modelData.time)
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                    // Held at full height when dry, so the row never jumps.
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        opacity: (modelData.pop ?? 0) > 0 ? 1 : 0
                                        text: "%1%".arg(modelData.pop ?? 0)
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colTertiary
                                    }
                                }
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 4
                    rowSpacing: 12
                    columnSpacing: 12
                    uniformCellWidths: true
                    uniformCellHeights: true

                    Tile {
                        id: uvTile
                        icon: "sunny"
                        title: Translation.tr("UV index")
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4
                            Value { text: String(Math.round(root.d.uv ?? 0)) }
                            Note { text: root.uvLevel(root.d.uv) }
                            Item { Layout.fillHeight: true }
                            StyledProgressBar {
                                Layout.fillWidth: true
                                value: Math.min(1, (root.d.uv ?? 0) / 11) * root.fill
                            }
                        }
                    }

                    Tile {
                        id: humidityTile
                        icon: "humidity_low"
                        title: Translation.tr("Humidity")
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4
                            Value { text: root.d.humidity }
                            Note { text: Translation.tr("Dew point %1").arg(root.d.dewPoint ?? "--") }
                            Item { Layout.fillHeight: true }
                            StyledProgressBar {
                                Layout.fillWidth: true
                                value: (parseInt(root.d.humidity) || 0) / 100 * root.fill
                            }
                        }
                    }

                    Tile {
                        id: windTile
                        icon: "air"
                        title: Translation.tr("Wind")
                        RowLayout {
                            anchors.fill: parent
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 4
                                Value { text: root.d.wind }
                                Note { text: Translation.tr("Gusts %1").arg(root.d.gusts ?? "--") }
                                Note { text: Translation.tr("From %1").arg(root.d.windDir) }
                            }
                            Rectangle {
                                id: dial
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: Math.min(root.gaugeSize, parent.height)
                                Layout.preferredHeight: Layout.preferredWidth
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colLayer2
                                Repeater {
                                    model: [Translation.tr("N"), Translation.tr("E"), Translation.tr("S"), Translation.tr("W")]
                                    delegate: StyledText {
                                        required property string modelData
                                        required property int index
                                        readonly property real a: index * Math.PI / 2
                                        x: dial.width / 2 + Math.sin(a) * (dial.width / 2 - 8) - width / 2
                                        y: dial.height / 2 - Math.cos(a) * (dial.height / 2 - 8) - height / 2
                                        text: modelData
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "navigation"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.huge
                                    color: Appearance.colors.colPrimary
                                    // Open-Meteo gives where the wind comes from;
                                    // the arrow points where it is going.
                                    rotation: root.needle * (((root.d.windDeg ?? 0) + 180) % 360)
                                }
                            }
                        }
                    }

                    Tile {
                        id: pressureTile
                        icon: "compress"
                        title: Translation.tr("Pressure")
                        RowLayout {
                            anchors.fill: parent
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 4
                                Value { text: String(parseInt(root.d.press) || "--") }
                                Note { text: Translation.tr("hPa") }
                            }
                            CircularProgress {
                                Layout.alignment: Qt.AlignVCenter
                                implicitSize: Math.min(root.gaugeSize, parent.height)
                                // M3 Expressive's thick track.
                                lineWidth: 8
                                enableAnimation: false
                                colPrimary: Appearance.colors.colPrimary
                                // 950-1050 hPa: everything short of a hurricane's eye.
                                value: Math.max(0, Math.min(1, ((parseInt(root.d.press) || 950) - 950) / 100)) * root.fill
                            }
                        }
                    }

                    Tile {
                        id: sunTile
                        Layout.columnSpan: 2
                        icon: "wb_twilight"
                        title: Translation.tr("Sunrise and sunset")
                        readonly property real f: WMath.sunFraction(root.d.sunriseIso, root.d.sunsetIso, root.minutes)
                        readonly property int daylight: WMath.isoMinutes(root.d.sunsetIso) - WMath.isoMinutes(root.d.sunriseIso)

                        RowLayout {
                            id: sunTimes
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            spacing: 8
                            Note {
                                text: Translation.tr("Rise %1").arg(root.d.sunrise)
                            }
                            Note {
                                visible: sunTile.daylight > 0
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("%1 h %2 min of daylight").arg(Math.floor(sunTile.daylight / 60)).arg(sunTile.daylight % 60)
                            }
                            Note {
                                horizontalAlignment: Text.AlignRight
                                text: Translation.tr("Set %1").arg(root.d.sunset)
                            }
                        }

                        Shape {
                            id: arc
                            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: sunTimes.top; bottomMargin: 8 }
                            preferredRendererType: Shape.CurveRenderer
                            readonly property real rx: width / 2 - sun.width
                            readonly property real ry: height - sun.height / 2
                            readonly property real a: Math.PI * (1 + sunTile.f * root.fill)

                            ShapePath {
                                strokeColor: Appearance.colors.colLayer2
                                strokeWidth: 4
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: arc.width / 2
                                    centerY: arc.height
                                    radiusX: arc.rx
                                    radiusY: arc.ry
                                    startAngle: 180
                                    sweepAngle: 180
                                }
                            }
                            ShapePath {
                                strokeColor: Appearance.colors.colPrimary
                                strokeWidth: 4
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: arc.width / 2
                                    centerY: arc.height
                                    radiusX: arc.rx
                                    radiusY: arc.ry
                                    startAngle: 180
                                    sweepAngle: 180 * sunTile.f * root.fill
                                }
                            }
                        }

                        Rectangle {
                            id: sun
                            width: 16
                            height: 16
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimary
                            x: arc.x + arc.width / 2 + Math.cos(arc.a) * arc.rx - width / 2
                            y: arc.y + arc.height + Math.sin(arc.a) * arc.ry - height / 2
                        }
                    }

                    Tile {
                        id: rainTile
                        icon: "umbrella"
                        title: Translation.tr("Precipitation")
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4
                            Value { text: root.d.precip }
                            Note { text: Translation.tr("%1% chance today").arg(root.today?.pop ?? 0) }
                            Item { Layout.fillHeight: true }
                            StyledProgressBar {
                                Layout.fillWidth: true
                                value: (root.today?.pop ?? 0) / 100 * root.fill
                            }
                        }
                    }

                    Tile {
                        id: visibilityTile
                        icon: "visibility"
                        title: Translation.tr("Visibility")
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4
                            Value { text: root.d.visib }
                            Note { text: root.visibilityLevel(root.d.visibM) }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }

            Card {
                id: week
                Layout.preferredWidth: root.width * 0.3
                Layout.fillHeight: true

                ColumnLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 4

                    CardHeader {
                        icon: "calendar_month"
                        title: Translation.tr("%1-day forecast").arg(Weather.forecastData.length)
                    }

                    Repeater {
                        model: Weather.forecastData
                        delegate: RowLayout {
                            id: day
                            required property var modelData
                            required property int index
                            readonly property real lo: root.us ? modelData.minF : modelData.minC
                            readonly property real hi: root.us ? modelData.maxF : modelData.maxC
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            // A layout's height is capped at its tallest child's,
                            // so without this the rows cannot take the spare
                            // height and it lands in the header's cell instead.
                            Layout.maximumHeight: Infinity
                            spacing: 12

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: day.index === 0 ? Translation.tr("Today")
                                    : Qt.locale().dayName(new Date(day.modelData.date).getUTCDay(), Locale.ShortFormat)
                                font.variableAxes: day.index === 0 ? Appearance.font.variableAxes.title : Appearance.font.variableAxes.main
                                color: Appearance.colors.colOnSurface
                            }
                            Image {
                                sourceSize: Qt.size(root.iconSize, root.iconSize)
                                source: WeatherIcons.getWeatherIcon(day.modelData.code ?? 113, false)
                            }
                            StyledText {
                                Layout.preferredWidth: tempMetrics.advanceWidth
                                opacity: (day.modelData.pop ?? 0) > 0 ? 1 : 0
                                text: "%1%".arg(day.modelData.pop ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colTertiary
                            }
                            Temp {
                                text: root.deg(day.lo)
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            // The week's coldest to hottest, with this day's span on it.
                            Item {
                                id: track
                                Layout.preferredWidth: week.width * 0.3
                                implicitHeight: 8
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colLayer2
                                }
                                Rectangle {
                                    readonly property real from: WMath.position(day.lo, root.weekSpan)
                                    x: from * track.width
                                    width: Math.max(track.height, (WMath.position(day.hi, root.weekSpan) - from) * track.width) * root.fill
                                    height: track.height
                                    radius: Appearance.rounding.full
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: Appearance.colors.colPrimary }
                                        GradientStop { position: 1; color: Appearance.colors.colTertiary }
                                    }
                                }
                                // Where it is right now.
                                Rectangle {
                                    visible: day.index === 0
                                    width: track.height
                                    height: track.height
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colOnPrimary
                                    border.width: 2
                                    border.color: Appearance.colors.colOnSurface
                                    opacity: root.fill
                                    x: WMath.position(parseInt(root.d.temp), root.weekSpan) * track.width - width / 2
                                }
                            }
                            Temp {
                                text: root.deg(day.hi)
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                }
            }
        }
    }
}
