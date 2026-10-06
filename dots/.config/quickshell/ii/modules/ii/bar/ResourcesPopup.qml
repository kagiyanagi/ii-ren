import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

StyledPopup {
    id: root
    stickyHover: true

    readonly property int graphPointCount: 13
    readonly property int contentWidth: 380
    property list<real> cpuGraphHistory: []
    property list<real> gpuGraphHistory: []

    onActiveChanged: {
        ResourceUsage.resourcePopupMonitoringEnabled = active;
        cpuGraphHistory = [];
        gpuGraphHistory = [];
        if (active)
            ResourceUsage.requestGpuSample();
    }

    // String cleanup functions
    function cleanDistro(name) {
        return name.replace(/ Linux/g, "").replace(/\s*\(.*?\)/g, "").trim();
    }

    function cleanCpu(model) {
        return model.replace(/Intel\(R\)|Core\(TM\)|CPU|Processor|AMD|(\d+th Gen)/g, "").replace(/\s+/g, " ").trim();
    }

    function cleanGpu(model) {
        if (!model || model === "--")
            return "--";

        var cleaned = model.replace(/\(rev\s+[a-f0-9]+\)/gi, "").trim();
        var baseModel = "";

        if (/Advanced Micro Devices|AMD|ATI/i.test(cleaned)) {
            var rx = /\[([^\]]+)\]/g;
            var match;
            var modelBracket = "";
            while ((match = rx.exec(cleaned)) !== null) {
                var content = match[1].trim();
                if (content.toLowerCase() !== "amd/ati") {
                    modelBracket = content;
                }
            }

            if (modelBracket) {
                if (modelBracket.indexOf("/") !== -1) {
                    modelBracket = modelBracket.split("/")[0].trim();
                }
                baseModel = modelBracket;
            } else {
                var modelOnly = cleaned.replace(/Advanced Micro Devices, Inc\.\s*\[AMD\/ATI\]/gi, "").trim();
                if (modelOnly.toLowerCase() === "amd/ati" || modelOnly.length === 0) {
                    baseModel = "Radeon Graphics";
                } else {
                    baseModel = modelOnly;
                }
            }
        } else if (/Intel/i.test(cleaned)) {
            baseModel = cleaned.replace(/Intel Corporation/gi, "Intel").trim();
        } else if (/NVIDIA/i.test(cleaned)) {
            var rxNvidia = /\[([^\]]+)\]/g;
            var matchNvidia;
            var lastBracket = "";
            while ((matchNvidia = rxNvidia.exec(cleaned)) !== null) {
                lastBracket = matchNvidia[1].trim();
            }
            if (lastBracket) {
                baseModel = lastBracket;
            } else {
                baseModel = cleaned.replace(/NVIDIA Corporation/gi, "").trim();
            }
        } else {
            baseModel = cleaned;
        }

        var stripped = baseModel.replace(/NVIDIA|GeForce|AMD|Radeon|Laptop GPU|Graphics|Corporation/gi, "").replace(/\s+/g, " ").trim();
        if (stripped.length > 0) {
            stripped = stripped.replace(/^[\/\-\s]+/, "").trim();
            if (stripped.length > 0) {
                return stripped;
            }
        }
        return baseModel;
    }

    /*
     * One sibling entering: opacity on the effects spec plus a *single* short
     * translate on the enter spec, offset by the popup's stagger (DESIGN.md 2.8,
     * cluster Contract 1). The scale and the rotation that used to ride along
     * with it are gone -- three transforms per child is choreography, not motion.
     *
     * `running` is bound by each caller to the popup's open state, so a close
     * stops it mid-flight and the `from:` values restore the start state on the
     * next open. That is the whole of the reset that `onStartAnimChanged` and the
     * `popupOpenProgress` Connections block used to do by hand, twice, in ~95
     * lines of property pokes.
     *
     * Exit is the popup surface's own arrowPopup close, inherited from
     * StyledPopup (Contract 1); the content does not animate out separately.
     */
    component EnterAnim: SequentialAnimation {
        id: enterAnim

        property Item item
        property Translate slide
        property int delay: 0
        readonly property int offset: 12

        PauseAnimation {
            duration: enterAnim.delay
        }
        ParallelAnimation {
            NumberAnimation {
                target: enterAnim.item
                property: "opacity"
                from: 0
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            NumberAnimation {
                target: enterAnim.slide
                property: "y"
                from: enterAnim.offset
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
    }

    /*
     * A usage card with history behind it: CPU and GPU are the same card, and
     * were the same 250 lines written twice.
     *
     * The plot fills its rounded well edge to edge and clips its own painting to
     * the well's radius, inside the Canvas's image -- which is what the
     * `layer.enabled` + OpacityMask pair here used to buy, at one extra
     * framebuffer per card (DESIGN.md 8). The inset by the radius that replaced
     * the mask was free too, but it stopped the plot a radius short of both edges.
     */
    component UsageGraphCard: Rectangle {
        id: graphCard

        property string icon
        property string label
        property real usage: 0
        property real temp: 0
        property int points: 0
        property list<real> history

        implicitHeight: 196
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 0

            RowLayout {
                Layout.fillWidth: true

                MaterialSymbol {
                    text: graphCard.icon
                    iconSize: 32
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.8
                }

                Item {
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: 4

                    MaterialSymbol {
                        text: "thermostat"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Config.options.bar.weather.useUSCS ? Math.round(graphCard.temp * 1.8 + 32) + "°F" : Math.round(graphCard.temp) + "°C"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: graphCard.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.6
                }

                StyledText {
                    text: Math.round(graphCard.usage * 100) + "%"
                    // M3 type scale, Display Small (36sp) -- Appearance.font.pixelSize
                    // tops out at 23 and this is the popup's primary answer.
                    font.pixelSize: 36
                    font.weight: Font.Black
                    color: Appearance.colors.colOnLayer1
                }

                Rectangle {
                    id: graphWell
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSecondaryContainer

                    Graph {
                        anchors.fill: parent
                        radius: graphWell.radius
                        values: graphCard.history
                        points: graphCard.points
                        alignment: Graph.Alignment.Right
                    }
                }
            }
        }
    }

    /*
     * One horizontal meter: RAM, swap and disk were this card written three
     * times, 280 lines each, free to drift apart.
     *
     * The fill is a pill of its own, never narrower than the track is tall: at 0%
     * it is the circle round the icon, and the rest of the track maps onto the
     * remaining width -- the floor Android's brightness slider keeps its thumb at.
     * The percent printed beside it is the exact reading. It used to be the
     * track's silhouette scissored to the raw value, and below one pill-height
     * that left a flat-cut sliver of the left cap. A rounded rect at least as wide
     * as it is tall clamps its radius to the track's, so its left cap coincides
     * with the track's and it needs no clip or mask (DESIGN.md 8).
     * tools/check-resources-popup.py holds that geometry down.
     */
    component MeterPill: Rectangle {
        id: pill

        property string icon
        property string label
        property string usage
        property real percent: 0
        /*
         * A meter goes red when it is nearly full. Nothing in AOSP publishes
         * "nearly full" for a system meter, so it is named once here instead of
         * repeated per meter. The colour it crosses to is the one
         * CustomBatteryMeter settled on: the filled surface takes
         * colErrorContainer and its content the matching on-colour.
         */
        property real warnAt: 0.9
        // `NaN > 0` is false, so this clamps a missing reading to empty rather than
        // passing NaN into a width and taking the layout with it.
        readonly property real value: pill.percent > 0 ? Math.min(1, pill.percent) : 0
        readonly property bool warning: pill.value >= pill.warnAt
        readonly property color fillColor: pill.warning ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
        readonly property color contentColor: pill.warning ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer

        implicitHeight: 64
        radius: Appearance.rounding.full
        color: ColorUtils.applyAlpha(pill.fillColor, 0.25)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: pill.height + (pill.width - pill.height) * pill.value
            radius: pill.radius
            color: pill.fillColor

            Behavior on width {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            MaterialShape {
                shapeString: "Circle"
                implicitSize: 40
                color: Appearance.colors.colLayer4

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: pill.icon
                    iconSize: 22
                    color: Appearance.colors.colOnLayer4
                }
            }

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: pill.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: pill.contentColor
                }
                StyledText {
                    text: pill.usage
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: pill.contentColor
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: Math.round(pill.value * 100) + "%"
                // M3 type scale, Headline Small (24sp).
                font.pixelSize: 24
                font.weight: Font.Black
                color: pill.contentColor
                Layout.rightMargin: 12
            }
        }
    }

    contentItem: ColumnLayout {
        id: contentLayout
        spacing: 12
        implicitWidth: root.contentWidth

        Connections {
            target: ResourceUsage
            function onCpuSampled(usage) {
                if (!root.active) return;
                if (root.cpuGraphHistory.length === 0) {
                    root.cpuGraphHistory = [usage, usage];
                } else {
                    let hist = [...root.cpuGraphHistory, usage];
                    if (hist.length > root.graphPointCount) {
                        hist.shift();
                    }
                    root.cpuGraphHistory = hist;
                }
            }
            function onGpuSampled(usage) {
                if (!root.active) return;
                if (root.gpuGraphHistory.length === 0) {
                    root.gpuGraphHistory = [usage, usage];
                } else {
                    let hist = [...root.gpuGraphHistory, usage];
                    if (hist.length > root.graphPointCount) {
                        hist.shift();
                    }
                    root.gpuGraphHistory = hist;
                }
            }
        }

        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6

        readonly property var _visList: [true // Hero Card
            , true // CPU/GPU Cards
            , true // RAM Pill
            , Config.options.bar.resources.alwaysShowSwap // SWAP Pill
            , true // Disk Pill
            , Config.options.bar.resources.showDocker // Docker
        ]

        /*
         * The one stagger rule (DESIGN.md 2.8), counted over *visible* siblings:
         * with swap or docker hidden, counting raw indices would leave a hole in
         * the sequence and the tail would enter late for no reason on screen.
         */
        function getDelay(index) {
            let visIndex = 0;
            for (let i = 0; i < index; i++) {
                if (_visList[i])
                    visIndex++;
            }
            return Appearance.animation.staggerStep * Math.min(visIndex, Appearance.animation.staggerCap);
        }

        // Hero Card
        Rectangle {
            id: heroCard
            implicitWidth: root.contentWidth
            implicitHeight: 140
            radius: Appearance.rounding.large
            color: Appearance.colors.colPrimaryContainer

            opacity: 0
            transform: Translate {
                id: heroCardSlide
            }

            EnterAnim {
                item: heroCard
                slide: heroCardSlide
                delay: contentLayout.getDelay(0)
                running: contentLayout.startAnim
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                MaterialShape {
                    shapeString: "Cookie9Sided"
                    implicitSize: 74
                    color: Appearance.m3colors.m3primary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: Battery.available ? "laptop_chromebook" : "desktop_windows"
                        iconSize: 36
                        color: Appearance.m3colors.m3onPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    spacing: 4

                    Rectangle {
                        Layout.alignment: Qt.AlignRight
                        color: Appearance.colors.colPrimary
                        radius: Appearance.rounding.full
                        implicitWidth: distroRow.implicitWidth + 24
                        implicitHeight: 28

                        RowLayout {
                            id: distroRow
                            anchors.centerIn: parent
                            spacing: 8

                            CustomIcon {
                                source: SystemInfo.distroIcon
                                implicitWidth: 14
                                implicitHeight: 14
                                colorize: true
                                color: Appearance.m3colors.m3onPrimary
                            }
                            StyledText {
                                text: root.cleanDistro(SystemInfo.distroName)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                color: Appearance.m3colors.m3onPrimary
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: root.cleanCpu(ResourceUsage.cpuModel)
                            // M3 type scale, Headline Small (24sp).
                            font.pixelSize: 24
                            font.weight: Font.Black
                            color: Appearance.colors.colOnPrimaryContainer
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: root.cleanGpu(ResourceUsage.gpuModel)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }
            }
        }

        RowLayout {
            id: cpuGpuCardsRow
            implicitWidth: root.contentWidth
            spacing: 12

            opacity: 0
            transform: Translate {
                id: cpuGpuCardsRowSlide
            }

            EnterAnim {
                item: cpuGpuCardsRow
                slide: cpuGpuCardsRowSlide
                delay: contentLayout.getDelay(1)
                running: contentLayout.startAnim
            }

            UsageGraphCard {
                Layout.fillWidth: true
                icon: "memory"
                label: "CPU Usage"
                usage: ResourceUsage.cpuUsage
                temp: ResourceUsage.cpuTemp
                points: root.graphPointCount
                history: root.cpuGraphHistory
            }

            UsageGraphCard {
                Layout.fillWidth: true
                icon: "videogame_asset"
                label: "GPU Usage"
                usage: ResourceUsage.gpuUsage
                temp: ResourceUsage.gpuTemp
                points: root.graphPointCount
                history: root.gpuGraphHistory
            }
        }

        MeterPill {
            id: ramCard
            Layout.fillWidth: true
            icon: "memory_alt"
            label: "RAM"
            percent: ResourceUsage.memoryUsedPercentage
            usage: (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.memoryTotal / (1024 * 1024)).toFixed(0) + " GB"

            opacity: 0
            transform: Translate {
                id: ramCardSlide
            }

            EnterAnim {
                item: ramCard
                slide: ramCardSlide
                delay: contentLayout.getDelay(2)
                running: contentLayout.startAnim
            }
        }

        MeterPill {
            id: swapCard
            visible: Config.options.bar.resources.alwaysShowSwap
            Layout.fillWidth: true
            icon: "swap_horiz"
            label: "SWAP"
            percent: ResourceUsage.swapUsedPercentage
            usage: (ResourceUsage.swapUsed / (1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.swapTotal / (1024 * 1024)).toFixed(0) + " GB"

            opacity: 0
            transform: Translate {
                id: swapCardSlide
            }

            EnterAnim {
                item: swapCard
                slide: swapCardSlide
                delay: contentLayout.getDelay(3)
                running: contentLayout.startAnim
            }
        }

        MeterPill {
            id: diskCard
            Layout.fillWidth: true
            icon: "hard_drive"
            label: "DISK · " + (Config.options?.resources?.diskMount ?? "/")
            percent: ResourceUsage.diskUsedPercentage
            usage: (ResourceUsage.diskUsed / (1024 * 1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.diskTotal / (1024 * 1024 * 1024)).toFixed(0) + " GB"

            opacity: 0
            transform: Translate {
                id: diskCardSlide
            }

            EnterAnim {
                item: diskCard
                slide: diskCardSlide
                delay: contentLayout.getDelay(4)
                running: contentLayout.startAnim
            }
        }

        /*
         * Docker is the power-user footer and never outranks a meter. The two
         * hairline rules that used to flank a "Containers" caption here were a
         * separator bar (design law 11 / DESIGN.md 5.5), and the caption itself
         * repeated the header DockerSection already draws -- the 12 of column
         * spacing is the separation.
         */
        DockerSection {
            id: dockerSection
            Layout.fillWidth: true
            visible: Config.options.bar.resources.showDocker

            opacity: 0
            transform: Translate {
                id: dockerSectionSlide
            }

            EnterAnim {
                item: dockerSection
                slide: dockerSectionSlide
                delay: contentLayout.getDelay(5)
                running: contentLayout.startAnim
            }
        }
    }
}
