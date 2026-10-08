import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "batteryHistory.js" as History

/*
 * Everything the shell does about the battery, under the last day or week of it.
 * The chart is Android's battery usage graph: the charge line over the time on
 * the charger, the draw on battery below it on the same clock, and a pointer over
 * either reads both out in the header. UPower keeps the history (batteryHistory.js).
 */
ContentPage {
    id: page
    readonly property int index: 3
    property bool register: parent.register ?? false
    forceWidth: true

    // UPower names the object after the kernel's, anything outside [A-Za-z0-9_] as _.
    readonly property string devicePath: `/org/freedesktop/UPower/devices/battery_${Battery.batteryNativePath.replace(/[^A-Za-z0-9_]/g, "_")}`

    property string range: "day"
    property real now: Date.now() / 1000
    readonly property var edges: History.edges(page.range, page.now)
    readonly property real from: edges[0]
    readonly property real to: edges[edges.length - 1]
    property var charge: []
    property var rate: []
    property bool historyLoaded: false
    property bool historyFailed: false
    readonly property var series: History.levelSeries(page.charge, page.from, { t: page.now, v: Battery.percentage * 100, s: Battery.chargeState })
    readonly property var spans: History.pluggedSpans(page.series, page.from, page.now)
    readonly property var usage: History.draw(page.rate, page.edges, page.now)
    readonly property real drawMax: Math.max(5, Math.ceil(Math.max(0, ...page.usage.bins.filter(b => b !== null)) / 5) * 5)
    // How long a full battery lasts at this range's draw, once there is enough of it to say.
    readonly property real fullLasts: page.usage.seconds >= 1800 && page.usage.mean > 0.5
        ? (Battery.laptopBattery?.energyCapacity ?? 0) / page.usage.mean * 3600 : 0

    property real hoverT: -1
    readonly property var hoverLevel: page.hoverT >= 0 ? History.levelAt(page.series, page.hoverT) : null
    readonly property int hoverBin: page.hoverT < 0 ? -1 : page.edges.findIndex((e, i) => i + 1 < page.edges.length && page.hoverT >= e && page.hoverT < page.edges[i + 1])
    function hoverAt(fraction) {
        page.hoverT = Math.max(page.from, Math.min(page.now, page.from + fraction * (page.to - page.from)))
    }

    // The line draws in left to right on a new range: a clip widens over plots
    // that never repaint for it (CheatsheetWeather's hourly graph does the same).
    property real reveal: 0
    property bool revealPending: true
    onRangeChanged: {
        page.revealPending = true
        page.refresh()
    }
    NumberAnimation {
        id: revealAnim
        target: page
        property: "reveal"
        from: 0
        to: 1
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    function xAt(t, w) { return (t - page.from) / (page.to - page.from) * w }
    function yAt(v, h) { return 1 + (h - 2) * (1 - v / 100) }
    function watts(w) { return `${w.toFixed(1)} W` }

    readonly property string statusText: {
        const draw = Math.abs(Battery.energyRate) > 0.01 ? page.watts(Math.abs(Battery.energyRate)) : ""
        let parts
        if (Battery.chargeState === UPowerDeviceState.FullyCharged)
            parts = [Translation.tr("Fully charged")]
        else if (Battery.chargeLimitReached)
            parts = [Translation.tr("Charge limit reached")]
        else if (Battery.isCharging) {
            const time = Battery.timeToFullEffective > 0 ? History.duration(Battery.timeToFullEffective) : ""
            parts = [Translation.tr("Charging"), time && (Battery.chargeLimitActive
                ? Translation.tr("%1 until %2%").arg(time).arg(Battery.chargeLimit) : Translation.tr("%1 until full").arg(time)), draw]
        } else if (Battery.isPluggedIn)
            parts = [Translation.tr("Plugged in, not charging")]
        else
            parts = [Battery.timeToEmpty > 0 ? Translation.tr("%1 left").arg(History.duration(Battery.timeToEmpty)) : Translation.tr("On battery"), draw]
        return parts.filter(p => p).join("  ·  ")
    }

    readonly property string hoverText: {
        if (page.hoverT < 0) return ""
        const s = page.hoverLevel?.s
        const state = s === undefined ? Translation.tr("Not recorded") : s === UPowerDeviceState.Charging ? Translation.tr("Charging")
            : History.pluggedIn(s) ? Translation.tr("Plugged in") : Translation.tr("On battery")
        const draw = page.hoverBin >= 0 ? page.usage.bins[page.hoverBin] : null
        return [Qt.locale().toString(new Date(page.hoverT * 1000), `ddd ${Config.options.time.format}`), state,
            draw !== null ? Translation.tr("%1 average").arg(page.watts(draw)) : ""].filter(p => p).join("  ·  ")
    }

    // Day: the clock's 6-hour marks. Week: each day under its own bar.
    readonly property var ticks: page.range === "week"
        ? page.edges.slice(0, -1).map((e, i) => ({ t: (e + page.edges[i + 1]) / 2, text: Qt.locale().toString(new Date(e * 1000), "ddd") }))
        : page.edges.filter(e => new Date(e * 1000).getHours() % 6 === 0).map(e => ({ t: e, text: Qt.locale().toString(new Date(e * 1000), Config.options.time.format) }))

    readonly property string emptyText: page.historyFailed && page.charge.length === 0 ? Translation.tr("Couldn't read the battery history")
        : page.historyLoaded && page.series.length < 2 ? Translation.tr("No history for this period yet") : ""

    function refresh() {
        if (!Battery.batteryNativePath) return
        page.now = Date.now() / 1000
        historyProc.running = false
        historyProc.running = true
    }
    onDevicePathChanged: {
        page.refresh()
        propsProc.running = true
    }
    Component.onCompleted: {
        // The bar layout's gear on its battery entry lands here.
        if (page.Window.window?.pendingSectionHighlight === "batteryIndicator") {
            page.Window.window.pendingSectionHighlight = ""
            Qt.callLater(() => page.contentY = indicatorSection.mapToItem(page.contentItem, 0, 0).y)
        }
        page.refresh()
        propsProc.running = true
        powerProfilesProc.running = true
        SessionWarnings.refresh()
    }
    Connections {
        target: Battery
        function onChargeStateChanged() { page.refresh() }
    }
    // UPower adds a sample about every minute while awake.
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: page.refresh()
    }

    // Both series, one JSON line each. The path and span arrive as $0 and $1:
    // data, never script.
    Process {
        id: historyProc
        command: ["sh", "-c", 'for k in charge rate; do busctl --system --json=short call org.freedesktop.UPower "$0" org.freedesktop.UPower.Device GetHistory suu "$k" "$1" 100000 || exit 1; done',
            page.devicePath, String(Math.ceil(page.now - page.from + 6 * 3600))]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const lines = text.trim().split("\n")
                    const charge = History.parse(lines[0]), rate = History.parse(lines[1])
                    page.charge = charge
                    page.rate = rate
                    page.historyFailed = false
                } catch (e) {
                    page.historyFailed = true // and the last good frame stays
                }
                page.historyLoaded = true
                if (!page.revealPending) return
                page.revealPending = false
                if (page.historyFailed) page.reveal = 1
                else revealAnim.restart()
            }
        }
    }

    // The threshold ones last: a UPower older than 1.90 has none, and busctl stops at the first it lacks.
    readonly property var propNames: ["EnergyFullDesign", "Technology", "Vendor", "Temperature",
        "ChargeThresholdSupported", "ChargeThresholdEnabled", "ChargeStartThreshold", "ChargeEndThreshold"]
    property var props: ({})
    property bool propsLoaded: false
    Process {
        id: propsProc
        command: ["busctl", "--system", "--json=short", "get-property", "org.freedesktop.UPower", page.devicePath,
            "org.freedesktop.UPower.Device", ...page.propNames]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {}
                text.trim().split("\n").forEach((line, i) => {
                    try { out[page.propNames[i]] = JSON.parse(line).data } catch (e) {}
                })
                page.props = out
                page.propsLoaded = true
            }
        }
    }

    // GNOME's "Preserve battery health": UPower writes the thresholds, and on a
    // kernel with charge modes (charge_types) selects the one that obeys them.
    // Its polkit rule lets the active session do it without a password.
    property bool thresholdFailed: false
    Process {
        id: thresholdProc
        property bool want
        command: ["busctl", "--system", "call", "org.freedesktop.UPower", page.devicePath,
            "org.freedesktop.UPower.Device", "EnableChargeThreshold", "b", String(want)]
        onExited: code => {
            page.thresholdFailed = code !== 0
            propsProc.running = true
            Battery.reloadChargeLimit()
        }
    }

    property bool powerProfilesAvailable: true
    Process {
        id: powerProfilesProc
        command: ["busctl", "--system", "status", "org.freedesktop.UPower.PowerProfiles"]
        onExited: code => page.powerProfilesAvailable = code === 0
    }

    readonly property var technologies: ["", Translation.tr("Lithium-ion"), Translation.tr("Lithium polymer"),
        Translation.tr("Lithium iron phosphate"), Translation.tr("Lead acid"), Translation.tr("Nickel-cadmium"), Translation.tr("Nickel-metal hydride")]

    component Caption: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
    // The one status line under a row, when there is something to say (TASTE 3.4).
    component StatusLine: Caption {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        wrapMode: Text.Wrap
        visible: text !== ""
    }
    component Stat: ColumnLayout {
        property alias label: statLabel.text
        property alias value: statValue.text
        Layout.fillWidth: true
        spacing: 2
        Caption {
            id: statLabel
        }
        StyledText {
            id: statValue
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colOnSurface
        }
    }
    component Crosshair: Rectangle {
        visible: page.hoverT >= 0
        x: Math.round(page.xAt(page.hoverT, parent.width))
        width: 1
        height: parent.height
        color: Appearance.colors.colOnSurfaceVariant
    }
    component HoverArea: MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: mouse => page.hoverAt(mouse.x / width)
        onExited: page.hoverT = -1
    }

    Item {
        visible: UPower.displayDevice.ready && !Battery.available
        Layout.fillWidth: true
        implicitHeight: 400

        PagePlaceholder {
            shown: parent.visible
            icon: "battery_android_full"
            title: Translation.tr("No battery")
            description: Translation.tr("This device runs on mains power, so there is nothing to set here")
            descriptionHorizontalAlignment: Text.AlignHCenter
        }
    }

    ColumnLayout {
        visible: Battery.available
        Layout.fillWidth: true
        spacing: 32

        // The card bleeds as ContentGroup's do, so it meets the same edges as the sections below.
        Item {
            Layout.fillWidth: true
            implicitHeight: usageCard.implicitHeight

            Rectangle {
                id: usageCard
                x: -8
                width: parent.width + 16
                implicitHeight: usageColumn.implicitHeight + 32
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh

                ColumnLayout {
                    id: usageColumn
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    // Now, or wherever the pointer is on the chart. Both lines keep their height.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: page.hoverT < 0 ? `${Math.round(Battery.percentage * 100)}%`
                                    : page.hoverLevel ? `${Math.round(page.hoverLevel.v)}%` : "–"
                                // The page's answer. Tabular, since it changes under the pointer.
                                font.pixelSize: Appearance.font.pixelSize.displayLarge
                                font.family: Appearance.font.family.numbers
                                font.variableAxes: Appearance.font.variableAxes.numbers
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: page.hoverT < 0 ? page.statusText : page.hoverText
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        ButtonGroup {
                            Layout.alignment: Qt.AlignTop
                            spacing: 2
                            SelectionGroupButton {
                                leftmost: true
                                buttonText: Translation.tr("24 hours")
                                toggled: page.range === "day"
                                onClicked: page.range = "day"
                            }
                            SelectionGroupButton {
                                rightmost: true
                                buttonText: Translation.tr("7 days")
                                toggled: page.range === "week"
                                onClicked: page.range = "week"
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 8
                        Caption {
                            Layout.fillWidth: true
                            text: Translation.tr("Battery level")
                        }
                        Rectangle {
                            implicitWidth: 12
                            implicitHeight: 12
                            radius: Appearance.rounding.unsharpen
                            color: Appearance.colors.colSecondaryContainer
                        }
                        Caption {
                            text: Translation.tr("Plugged in")
                        }
                        Item {
                            implicitWidth: yAxis.width
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Item {
                            id: levelPlot
                            Layout.fillWidth: true
                            implicitHeight: 160

                            // Tab in and the readout starts at now; Left/Right step a bar,
                            // Home/End jump to the ends, as the pointer would read them.
                            activeFocusOnTab: true
                            onActiveFocusChanged: page.hoverT = activeFocus ? page.now : -1
                            Keys.onPressed: event => {
                                const step = (page.to - page.from) / (page.edges.length - 1)
                                const at = page.hoverT < 0 ? page.now : page.hoverT
                                const moves = { [Qt.Key_Left]: at - step, [Qt.Key_Right]: at + step, [Qt.Key_Home]: page.from, [Qt.Key_End]: page.now }
                                if (!(event.key in moves)) return
                                page.hoverT = Math.max(page.from, Math.min(page.now, moves[event.key]))
                                event.accepted = true
                            }
                            StateOverlay {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                contentColor: Appearance.colors.colOnSurface
                                focused: levelPlot.activeFocus
                            }

                            Item {
                                width: parent.width * page.reveal
                                height: parent.height
                                clip: true

                                Canvas {
                                    id: levelCanvas
                                    width: levelPlot.width
                                    height: levelPlot.height
                                    readonly property var deps: [page.series, page.spans, page.edges, width, height,
                                        Appearance.colors.colPrimary, Appearance.colors.colSecondaryContainer, Appearance.colors.colOutlineVariant] // design-ok: the gridlines' colour
                                    onDepsChanged: requestPaint()
                                    onPaint: {
                                        const ctx = getContext("2d")
                                        ctx.reset()
                                        const w = width, h = height, pts = page.series
                                        ctx.fillStyle = Appearance.colors.colSecondaryContainer
                                        for (const s of page.spans) {
                                            const a = page.xAt(s[0], w)
                                            ctx.fillRect(a, 0, page.xAt(s[1], w) - a, h)
                                        }
                                        // design-ok: a chart's scale, hairline and recessive, not a section divider
                                        ctx.fillStyle = Appearance.colors.colOutlineVariant
                                        for (const v of [0, 50, 100])
                                            ctx.fillRect(0, Math.round(page.yAt(v, h)), w, 1)
                                        ctx.lineWidth = 2
                                        ctx.lineJoin = "round"
                                        ctx.lineCap = "round"
                                        ctx.strokeStyle = Appearance.colors.colPrimary
                                        ctx.fillStyle = ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                                        for (const run of History.segments(pts)) {
                                            if (run.length < 2) continue
                                            const trace = () => {
                                                ctx.beginPath()
                                                run.forEach((p, i) => i ? ctx.lineTo(page.xAt(p.t, w), page.yAt(p.v, h)) : ctx.moveTo(page.xAt(p.t, w), page.yAt(p.v, h)))
                                            }
                                            trace()
                                            ctx.lineTo(page.xAt(run[run.length - 1].t, w), h)
                                            ctx.lineTo(page.xAt(run[0].t, w), h)
                                            ctx.fill()
                                            trace()
                                            ctx.stroke()
                                        }
                                    }
                                }

                                // Now: the line's end, ringed in the card so it stays legible on the line.
                                Rectangle {
                                    visible: page.series.length > 1
                                    x: page.xAt(page.now, levelPlot.width) - width / 2
                                    y: page.yAt(Battery.percentage * 100, levelPlot.height) - height / 2
                                    width: 12
                                    height: 12
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colPrimary
                                    border.width: 2
                                    border.color: usageCard.color
                                }
                            }

                            Crosshair {}
                            Rectangle {
                                visible: page.hoverLevel !== null
                                x: page.xAt(page.hoverT, levelPlot.width) - width / 2
                                y: page.yAt(page.hoverLevel?.v ?? 0, levelPlot.height) - height / 2
                                width: 12
                                height: 12
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colOnSurface
                                border.width: 2
                                border.color: usageCard.color
                            }
                            StyledText {
                                anchors.centerIn: parent
                                visible: text !== ""
                                text: page.emptyText
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            HoverArea {}
                        }

                        Item {
                            id: yAxis
                            implicitWidth: 40
                            implicitHeight: levelPlot.height
                            Repeater {
                                model: [100, 50, 0]
                                Caption {
                                    required property int modelData
                                    y: page.yAt(modelData, yAxis.height) - height / 2
                                    font.family: Appearance.font.family.numbers
                                    text: `${modelData}%`
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 8
                        Caption {
                            Layout.fillWidth: true
                            text: Translation.tr("Power draw on battery")
                        }
                        Item {
                            implicitWidth: yAxis.width
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Item {
                            id: drawPlot
                            Layout.fillWidth: true
                            implicitHeight: 64

                            Item {
                                width: parent.width * page.reveal
                                height: parent.height
                                clip: true

                                // Bars grow from the bottom edge; their rounded
                                // rect runs past it, so the base comes out square.
                                Canvas {
                                    width: drawPlot.width
                                    height: drawPlot.height
                                    readonly property var deps: [page.usage, page.edges, page.hoverBin, width, height,
                                        Appearance.colors.colSecondary, Appearance.colors.colOutlineVariant] // design-ok: the gridline's colour
                                    onDepsChanged: requestPaint()
                                    onPaint: {
                                        const ctx = getContext("2d")
                                        ctx.reset()
                                        const w = width, h = height, e = page.edges
                                        // design-ok: a chart's scale, hairline and recessive, not a section divider
                                        ctx.fillStyle = Appearance.colors.colOutlineVariant
                                        ctx.fillRect(0, 0, w, 1)
                                        page.usage.bins.forEach((v, b) => {
                                            if (v === null) return
                                            const a = page.xAt(e[b], w), z = page.xAt(e[b + 1], w)
                                            const bw = Math.min(24, (z - a) * 0.6)
                                            const bh = Math.max(2, v / page.drawMax * (h - 1))
                                            const r = Math.min(4, bw / 2)
                                            // The hovered bar lifts by the others stepping back.
                                            ctx.fillStyle = page.hoverBin < 0 || b === page.hoverBin ? Appearance.colors.colSecondary
                                                : ColorUtils.transparentize(Appearance.colors.colSecondary, 0.6)
                                            ctx.beginPath()
                                            ctx.roundedRect((a + z - bw) / 2, h - bh, bw, bh + r, r, r)
                                            ctx.fill()
                                        })
                                    }
                                }
                            }

                            Crosshair {}
                            HoverArea {}
                        }

                        Item {
                            implicitWidth: yAxis.width
                            implicitHeight: drawPlot.height
                            Caption {
                                y: -height / 2
                                font.family: Appearance.font.family.numbers
                                text: page.watts(page.drawMax).replace(".0", "")
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.rightMargin: yAxis.width + 8
                        implicitHeight: tickMetrics.implicitHeight

                        Caption {
                            id: tickMetrics
                            visible: false
                            text: "0"
                        }
                        Repeater {
                            model: page.ticks
                            Caption {
                                required property var modelData
                                x: Math.max(0, Math.min(parent.width - width, page.xAt(modelData.t, parent.width) - width / 2))
                                font.family: Appearance.font.family.numbers
                                text: modelData.text
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 16
                        uniformCellSizes: true
                        Stat {
                            label: Translation.tr("On battery")
                            value: History.duration(page.usage.seconds)
                        }
                        Stat {
                            label: Translation.tr("Average draw")
                            value: page.usage.seconds > 0 ? page.watts(page.usage.mean) : "–"
                        }
                        Stat {
                            label: Translation.tr("Full charge lasts")
                            value: page.fullLasts > 0 ? `≈ ${History.duration(page.fullLasts)}` : "–"
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "energy_savings_leaf"
            title: Translation.tr("Power mode")

            ConfigSelectionArray {
                enabled: page.powerProfilesAvailable
                currentValue: PowerProfiles.profile
                onSelected: newValue => {
                    PowerProfiles.profile = newValue;
                }
                options: [
                    { displayName: Translation.tr("Power saver"), icon: "energy_savings_leaf", value: PowerProfile.PowerSaver },
                    { displayName: Translation.tr("Balanced"), icon: "airwave", value: PowerProfile.Balanced },
                    ...(PowerProfiles.hasPerformanceProfile ? [{ displayName: Translation.tr("Performance"), icon: "local_fire_department", value: PowerProfile.Performance }] : [])
                ]
            }
            StatusLine {
                text: !page.powerProfilesAvailable ? Translation.tr("Needs power-profiles-daemon, which isn't running")
                    : PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected ? Translation.tr("Performance is held back while the laptop is on a lap")
                    : PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature ? Translation.tr("Performance is held back while the laptop is hot")
                    : ""
            }
            ConfigSwitch {
                enabled: page.powerProfilesAvailable
                buttonIcon: "battery_saver"
                text: Translation.tr("Power saver at low battery")
                checked: Config.options.battery.autoPowerSaver
                onCheckedChanged: {
                    Config.options.battery.autoPowerSaver = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Switches to power saver at the low warning level, and back once plugged in")
                }
            }
        }

        ContentSection {
            icon: "charger"
            title: Translation.tr("Charging")

            ConfigSwitch {
                // Until UPower answers it neither claims support nor denies it.
                enabled: !page.propsLoaded || page.props.ChargeThresholdSupported === true
                buttonIcon: "health_metrics"
                text: Translation.tr("Limit charging to %1%").arg(page.props.ChargeEndThreshold ?? 80)
                toggles: false
                checked: page.props.ChargeThresholdEnabled === true
                onClicked: {
                    if (!page.propsLoaded || thresholdProc.running) return;
                    thresholdProc.want = !checked;
                    thresholdProc.running = true;
                }
            }
            StatusLine {
                color: page.thresholdFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                text: !page.propsLoaded ? ""
                    : page.props.ChargeThresholdSupported !== true ? Translation.tr("Not supported by this battery")
                    : page.thresholdFailed ? Translation.tr("Couldn't change the charge limit")
                    : page.props.ChargeThresholdEnabled ? Translation.tr("Stops at %1% and starts again below %2%. A battery kept off full ages slower.").arg(page.props.ChargeEndThreshold).arg(page.props.ChargeStartThreshold)
                    : Battery.chargeLimitActive ? Translation.tr("Charging already stops at %1%, set outside the shell").arg(Battery.chargeLimit)
                    : ""
            }
            ConfigSpinBox {
                icon: "notifications_active"
                text: Translation.tr("Full warning")
                value: Config.options.battery.full
                from: 0
                to: 101
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.full = value;
                }
                StyledToolTip {
                    text: Translation.tr("Notifies when charged to this level. 101 turns it off")
                }
            }
            ConfigSelectionRow {
                buttonIcon: "bolt"
                text: Translation.tr("Ripple when plugged in")
                summary: Translation.tr("Plays from the side your charger port is on")
                currentValue: Config.options.battery.chargingRipple
                onSelected: newValue => {
                    Config.options.battery.chargingRipple = newValue;
                    if (newValue !== "off")
                        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "chargingRipple", "play", newValue]);
                }
                options: [
                    { displayName: Translation.tr("Off"), icon: "block", value: "off" },
                    { displayName: Translation.tr("Bottom left"), icon: "south_west", value: "bottomLeft" },
                    { displayName: Translation.tr("Center"), icon: "filter_center_focus", value: "center" },
                    { displayName: Translation.tr("Bottom right"), icon: "south_east", value: "bottomRight" }
                ]
            }
        }

        ContentSection {
            icon: "health_metrics"
            title: Translation.tr("Battery health")

            // The tiles paint their own cards, so they bleed as ContentGroup's do.
            Item {
                Layout.fillWidth: true
                implicitHeight: healthGrid.implicitHeight

                GridLayout {
                    id: healthGrid
                    x: -8
                    width: parent.width + 16
                    columns: 2
                    rowSpacing: 4
                    columnSpacing: 4
                    uniformCellWidths: true

                    SpecTile {
                        corner: 0
                        icon: "health_metrics"
                        label: Translation.tr("Maximum capacity")
                        value: Battery.health > 0 ? `${Math.round(Battery.health)}%` : Translation.tr("Not reported")
                        usage: Battery.health > 0 ? Battery.health / 100 : -1
                        // Apple's line: below 80% of its design, a battery is worn.
                        detail: Battery.health <= 0 ? "" : Battery.health >= 80 ? Translation.tr("Normal") : Translation.tr("Worn, holds less than when new")
                    }
                    SpecTile {
                        corner: 1
                        icon: "battery_android_full"
                        label: Translation.tr("Holds")
                        value: `${(Battery.laptopBattery?.energyCapacity ?? 0).toFixed(1)} Wh`
                        detail: page.props.EnergyFullDesign > 0 ? Translation.tr("%1 Wh when new").arg(page.props.EnergyFullDesign.toFixed(1)) : ""
                    }
                    SpecTile {
                        corner: 2
                        icon: "autorenew"
                        label: Translation.tr("Charge cycles")
                        value: Battery.cycles >= 0 ? `${Battery.cycles}` : Translation.tr("Not reported")
                    }
                    SpecTile {
                        corner: 3
                        icon: "battery_charging_full"
                        label: Translation.tr("Battery")
                        value: Battery.laptopBattery?.model || Translation.tr("Unknown")
                        detail: [page.props.Vendor ?? "", page.technologies[page.props.Technology] ?? "",
                            page.props.Temperature > 0 ? `${Math.round(page.props.Temperature)} °C` : ""].filter(p => p).join("  ·  ")
                    }
                }
            }
        }

        ContentSection {
            icon: "battery_alert"
            title: Translation.tr("Low battery")

            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("Low warning")
                value: Config.options.battery.low
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.low = value;
                }
            }
            ConfigSpinBox {
                icon: "dangerous"
                text: Translation.tr("Critical warning")
                value: Config.options.battery.critical
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.critical = value;
                }
            }

            ContentSubsection {
                title: Translation.tr("When the battery runs out")
                tooltip: Translation.tr("What the laptop does at the level below, unless it is charging. Hibernate keeps the session with no power at all")

                ConfigSelectionArray {
                    currentValue: Config.options.battery.automaticSuspend ? Config.options.battery.criticalAction : "none"
                    onSelected: newValue => {
                        Config.options.battery.automaticSuspend = newValue !== "none";
                        if (newValue !== "none") Config.options.battery.criticalAction = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Nothing"), icon: "block", value: "none" },
                        { displayName: Translation.tr("Suspend"), icon: "bedtime", value: "suspend" },
                        { displayName: Translation.tr("Hibernate"), icon: "downloading", value: "hibernate", enabled: SessionWarnings.can("CanHibernate") },
                        { displayName: Translation.tr("Shut down"), icon: "power_settings_new", value: "poweroff" }
                    ]
                }
                ConfigSpinBox {
                    enabled: Config.options.battery.automaticSuspend
                    icon: "battery_alert"
                    text: Translation.tr("At battery level")
                    value: Config.options.battery.suspend
                    from: 0
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.battery.suspend = value;
                    }
                }
                StatusLine {
                    text: SessionWarnings.can("CanHibernate") ? "" : Translation.tr("This machine can't hibernate: it needs a swap area and a resume setup")
                }
            }
        }

        ContentSection {
            icon: "bedtime"
            title: Translation.tr("Sleep on battery")

            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Shorter timeouts on battery")
                checked: Config.options.battery.idle.enable
                onCheckedChanged: {
                    Config.options.battery.idle.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Plugged in, hypridle's timeouts still apply. A playing video holds both")
                }
            }
            ConfigSpinBox {
                enabled: Config.options.battery.idle.enable
                icon: "mode_standby"
                text: Translation.tr("Screen off after (min)")
                value: Config.options.battery.idle.screenOff
                from: 1
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.battery.idle.screenOff = value;
                }
            }
            ConfigSpinBox {
                enabled: Config.options.battery.idle.enable
                icon: "bedtime"
                text: Translation.tr("Sleep after (min)")
                value: Config.options.battery.idle.sleep
                from: 1
                to: 120
                stepSize: 1
                onValueChanged: {
                    Config.options.battery.idle.sleep = value;
                }
            }
        }

        ContentSection {
            id: indicatorSection
            icon: "battery_android_full"
            title: Translation.tr("Battery indicator")

            // The first card of the run the rows sit on, painted by ContentGroup
            // so it reaches the same edges and takes the run's corners.
            Item {
                readonly property bool wantsCard: true
                Layout.fillWidth: true
                implicitHeight: 64

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12

                    CustomBatteryMeter {
                        percentage: Battery.percentage ?? 0.85
                        isCharging: Battery.isCharging ?? false
                        isPluggedIn: Battery.isPluggedIn ?? false
                        isLow: Battery.isLow ?? false
                        isCritical: Battery.isCritical ?? false
                        style: Config.options.bar.battery.style ?? "filled"
                        showPercentage: Config.options.bar.battery.showPercentage ?? 1
                        showChargingIndicator: Config.options.bar.battery.showChargingIndicator ?? true
                        showPercentSign: Config.options.bar.battery.showPercentSign ?? true
                    }

                    StyledText {
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: Translation.tr("Live bar preview")
                    }
                }
            }

            ConfigSelectionRow {
                buttonIcon: "battery_full"
                text: Translation.tr("Battery icon style")
                summary: Translation.tr("Custom ROM style battery icons (Evolution X & Iconify)")
                currentValue: Config.options.bar.battery.style ?? "filled"
                onSelected: newValue => {
                    Config.options.bar.battery.style = newValue;
                }
                options: [
                    { displayName: Translation.tr("Filled (M3 pill)"), icon: "pill", value: "filled" },
                    { displayName: Translation.tr("Portrait"), icon: "battery_android_full", value: "portrait" },
                    { displayName: Translation.tr("Landscape (right)"), icon: "battery_horiz_075", value: "landscape" },
                    { displayName: Translation.tr("Landscape (left)"), icon: "battery_horiz_050", value: "landscape_left" },
                    { displayName: Translation.tr("Landscape (iOS)"), icon: "battery_saver", value: "landscape_ios" },
                    { displayName: Translation.tr("Landscape (line)"), icon: "horizontal_rule", value: "landscape_line" },
                    { displayName: Translation.tr("Landscape (Musku)"), icon: "shapes", value: "landscape_musku" },
                    { displayName: Translation.tr("Landscape (Origami)"), icon: "polyline", value: "landscape_origami" },
                    { displayName: Translation.tr("Landscape (signal)"), icon: "signal_cellular_4_bar", value: "landscape_signal" },
                    { displayName: Translation.tr("Circle"), icon: "progress_activity", value: "circle" },
                    { displayName: Translation.tr("Dotted circle"), icon: "motion_mode", value: "dotted" },
                    { displayName: Translation.tr("Filled circle"), icon: "radio_button_checked", value: "filled_circle" },
                    { displayName: Translation.tr("Big circle"), icon: "adjust", value: "big_circle" },
                    { displayName: Translation.tr("Big dotted circle"), icon: "scatter_plot", value: "big_dotted_circle" },
                    { displayName: Translation.tr("Text only"), icon: "match_case", value: "text" }
                ]
            }

            ConfigSelectionRow {
                buttonIcon: "percent"
                text: Translation.tr("Percentage display")
                enabled: Config.options.bar.battery.style !== "text"
                currentValue: Config.options.bar.battery.showPercentage ?? 1
                onSelected: newValue => {
                    Config.options.bar.battery.showPercentage = newValue;
                }
                options: [
                    { displayName: Translation.tr("Hidden"), icon: "visibility_off", value: 0 },
                    { displayName: Translation.tr("Inside"), icon: "center_focus_strong", value: 1 },
                    { displayName: Translation.tr("Outside"), icon: "align_horizontal_right", value: 2 }
                ]
            }

            ConfigSwitch {
                buttonIcon: "percent"
                text: Translation.tr("Show percentage symbol (%)")
                checked: Config.options.bar.battery.showPercentSign ?? true
                onCheckedChanged: {
                    Config.options.bar.battery.showPercentSign = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "bolt"
                text: Translation.tr("Show charging indicator")
                checked: Config.options.bar.battery.showChargingIndicator ?? true
                onCheckedChanged: {
                    Config.options.bar.battery.showChargingIndicator = checked;
                }
            }
        }
    }
}
