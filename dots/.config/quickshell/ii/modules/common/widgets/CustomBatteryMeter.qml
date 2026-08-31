import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string style: Config.options.bar.battery.style ?? "filled"
    property int showPercentage: Config.options.bar.battery.showPercentage ?? 1 // 0: hidden, 1: inside, 2: outside
    property bool showChargingIndicator: Config.options.bar.battery.showChargingIndicator ?? true
    property bool showPercentSign: Config.options.bar.battery.showPercentSign ?? true

    property real percentage: Battery.percentage ?? 1.0
    property bool isCharging: Battery.isCharging ?? false
    property bool isPluggedIn: Battery.isPluggedIn ?? false
    property bool isLow: percentage <= (Config.options.battery.low / 100)
    property bool isCritical: percentage <= (Config.options.battery.critical / 100)
    property bool vertical: false

    property color highlightColor: (isLow && !isCharging) ? Appearance.m3colors.m3error : Appearance.colors.colOnSecondaryContainer
    property color trackColor: Appearance.colors.colSecondaryContainer
    property color contentColor: (isLow && !isCharging) ? Appearance.m3colors.m3error : Appearance.colors.colOnSecondaryContainer

    readonly property int percentageInt: Math.round(percentage * 100)
    readonly property string percentageText: percentageInt.toString() + (showPercentSign ? "%" : "")
    readonly property string rawPercentageText: percentageInt.toString()

    // Does this style support rendering text inside the icon?
    readonly property bool supportsInsideText: {
        return style !== "landscape_line" && style !== "landscape_signal" && style !== "text";
    }

    // Should outside percentage text be displayed?
    readonly property bool displayOutsideText: {
        if (root.style === "text") return false; // Handled internally by text component
        if (root.showPercentage === 2) return true;
        if (root.showPercentage === 1 && !root.supportsInsideText) return true; // Fallback for line/signal
        return false;
    }

    // Should inside text be displayed?
    readonly property bool displayInsideText: {
        return root.showPercentage === 1 && root.supportsInsideText && (!root.isCharging || !root.showChargingIndicator);
    }

    implicitWidth: mainLayout.implicitWidth
    implicitHeight: mainLayout.implicitHeight

    // Spatial animation for smooth battery level fill transitions
    property real animatedPercentage: percentage
    Behavior on animatedPercentage {
        NumberAnimation {
            duration: Appearance.animation.elementMoveSlow.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
    }

    // Charging animation pulse timer for dotted/circle effects
    property real chargingPulse: 0
    Timer {
        id: chargingTimer
        interval: 100
        running: root.isCharging && (root.style === "dotted" || root.style === "circle" || root.style === "big_dotted_circle" || root.style === "landscape_signal")
        repeat: true
        onTriggered: {
            root.chargingPulse = (root.chargingPulse + 1) % 16;
        }
    }

    // Layout containing the battery icon and optional outside percentage text
    RowLayout {
        id: mainLayout
        anchors.centerIn: parent
        spacing: 6

        // Main Battery Graphic
        Item {
            id: iconContainer
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: iconLoader.implicitWidth
            implicitHeight: iconLoader.implicitHeight

            Loader {
                id: iconLoader
                anchors.centerIn: parent
                sourceComponent: {
                    switch (root.style) {
                    case "circle": return circleComponent;
                    case "dotted": return dottedComponent;
                    case "filled_circle": return filledCircleComponent;
                    case "big_circle": return bigCircleComponent;
                    case "big_dotted_circle": return bigDottedComponent;
                    case "portrait": return portraitComponent;
                    case "landscape": return landscapeRightComponent;
                    case "landscape_left": return landscapeLeftComponent;
                    case "landscape_ios": return landscapeIosComponent;
                    case "landscape_line": return landscapeLineComponent;
                    case "landscape_musku": return landscapeMuskuComponent;
                    case "landscape_origami": return landscapeOrigamiComponent;
                    case "landscape_signal": return landscapeSignalComponent;
                    case "filled": case "landscape_pill": return filledComponent;
                    case "text": return textOnlyComponent;
                    default: return filledComponent;
                    }
                }
            }
        }

        // Outside Percentage Text (Shown only when showPercentage == 2 or fallback)
        StyledText {
            id: outsideText
            Layout.alignment: Qt.AlignVCenter
            visible: root.displayOutsideText
            text: root.percentageText
            color: root.contentColor
            font {
                pixelSize: Appearance.font.pixelSize.smaller
                weight: Font.DemiBold
            }
        }
    }

    // -------------------------------------------------------------
    // Style 1: Circle (LineageOS / OxygenOS / AOSP Circle Battery)
    // -------------------------------------------------------------
    Component {
        id: circleComponent
        Item {
            implicitWidth: 20
            implicitHeight: 20

            Shape {
                id: circleShape
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                preferredRendererType: Shape.CurveRenderer

                // Background track
                ShapePath {
                    strokeColor: root.trackColor
                    strokeWidth: 2.5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 10
                        centerY: 10
                        radiusX: 7.5
                        radiusY: 7.5
                        startAngle: 0
                        sweepAngle: 360
                    }
                }

                // Foreground active arc
                ShapePath {
                    strokeColor: root.highlightColor
                    strokeWidth: 2.5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 10
                        centerY: 10
                        radiusX: 7.5
                        radiusY: 7.5
                        startAngle: -90
                        sweepAngle: Math.max(1, root.animatedPercentage * 360)
                    }
                }
            }

            // Center charging bolt
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.isCharging && root.showChargingIndicator
                fill: 1
                text: "bolt"
                iconSize: Appearance.font.pixelSize.smaller - 2
                color: root.highlightColor
            }

            // Inside percentage
            StyledText {
                anchors.centerIn: parent
                visible: root.displayInsideText
                text: root.rawPercentageText
                color: root.highlightColor
                font {
                    pixelSize: Appearance.font.pixelSize.smaller - 3
                    weight: Font.Bold
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 2: Dotted Circle (CyanogenMod / Resurrection Remix Dotted)
    // -------------------------------------------------------------
    Component {
        id: dottedComponent
        Item {
            implicitWidth: 20
            implicitHeight: 20

            Repeater {
                model: 12
                delegate: Item {
                    id: dotWrapper
                    width: parent.width
                    height: parent.height
                    anchors.centerIn: parent

                    readonly property real angleRad: (index * 30 - 90) * (Math.PI / 180)
                    readonly property real dotRadius: 7.5
                    readonly property real dotCenterX: 10 + dotRadius * Math.cos(angleRad)
                    readonly property real dotCenterY: 10 + dotRadius * Math.sin(angleRad)

                    readonly property bool isActive: {
                        if (root.isCharging && root.showChargingIndicator) {
                            return index <= root.animatedPercentage * 12 || Math.floor(root.chargingPulse % 12) === index;
                        }
                        return (index + 0.5) / 12 <= root.animatedPercentage || (root.animatedPercentage > 0 && index === 0);
                    }

                    Rectangle {
                        x: dotWrapper.dotCenterX - width / 2
                        y: dotWrapper.dotCenterY - height / 2
                        width: 2.4
                        height: 2.4
                        radius: Appearance.rounding.full
                        color: dotWrapper.isActive ? root.highlightColor : root.trackColor

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.fadeFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                            }
                        }
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.isCharging && root.showChargingIndicator
                fill: 1
                text: "bolt"
                iconSize: Appearance.font.pixelSize.smaller - 2
                color: root.highlightColor
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.displayInsideText
                text: root.rawPercentageText
                color: root.highlightColor
                font {
                    pixelSize: Appearance.font.pixelSize.smaller - 3
                    weight: Font.Bold
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 3: Filled Circle (Iconify Filled Circle / Solid Donut Gauge)
    // -------------------------------------------------------------
    Component {
        id: filledCircleComponent
        Item {
            implicitWidth: 20
            implicitHeight: 20

            Shape {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                preferredRendererType: Shape.CurveRenderer

                // Background solid circle track
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.trackColor
                    PathAngleArc {
                        centerX: 10
                        centerY: 10
                        radiusX: 9
                        radiusY: 9
                        startAngle: 0
                        sweepAngle: 360
                    }
                }

                // Active level pie / wedge
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.highlightColor
                    startX: 10
                    startY: 10
                    PathAngleArc {
                        centerX: 10
                        centerY: 10
                        radiusX: 9
                        radiusY: 9
                        startAngle: -90
                        sweepAngle: Math.max(2, root.animatedPercentage * 360)
                    }
                    PathLine { x: 10; y: 10 }
                }

                // Inner cutout circle for donut look
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: Appearance.colors.colLayer1
                    PathAngleArc {
                        centerX: 10
                        centerY: 10
                        radiusX: 5
                        radiusY: 5
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.isCharging && root.showChargingIndicator
                fill: 1
                text: "bolt"
                iconSize: Appearance.font.pixelSize.smaller - 3
                color: root.highlightColor
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.displayInsideText
                text: root.rawPercentageText
                color: root.highlightColor
                font {
                    pixelSize: Appearance.font.pixelSize.smaller - 4
                    weight: Font.Bold
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 4: Big Circle (EvoX Big Circle Battery - 24dp bold)
    // -------------------------------------------------------------
    Component {
        id: bigCircleComponent
        Item {
            implicitWidth: 24
            implicitHeight: 24

            Shape {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: root.trackColor
                    strokeWidth: 3.2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 12
                        centerY: 12
                        radiusX: 9.5
                        radiusY: 9.5
                        startAngle: 0
                        sweepAngle: 360
                    }
                }

                ShapePath {
                    strokeColor: root.highlightColor
                    strokeWidth: 3.2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 12
                        centerY: 12
                        radiusX: 9.5
                        radiusY: 9.5
                        startAngle: -90
                        sweepAngle: Math.max(1, root.animatedPercentage * 360)
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.isCharging && root.showChargingIndicator
                fill: 1
                text: "bolt"
                iconSize: Appearance.font.pixelSize.smaller
                color: root.highlightColor
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.displayInsideText
                text: root.rawPercentageText
                color: root.highlightColor
                font {
                    pixelSize: Appearance.font.pixelSize.smaller - 2
                    weight: Font.Bold
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 5: Big Dotted Circle (EvoX 16-Segment Big Dotted Circle)
    // -------------------------------------------------------------
    Component {
        id: bigDottedComponent
        Item {
            implicitWidth: 24
            implicitHeight: 24

            Repeater {
                model: 16
                delegate: Item {
                    id: bigDotWrapper
                    width: parent.width
                    height: parent.height
                    anchors.centerIn: parent

                    readonly property real angleRad: (index * 22.5 - 90) * (Math.PI / 180)
                    readonly property real dotRadius: 9.5
                    readonly property real dotCenterX: 12 + dotRadius * Math.cos(angleRad)
                    readonly property real dotCenterY: 12 + dotRadius * Math.sin(angleRad)

                    readonly property bool isActive: {
                        if (root.isCharging && root.showChargingIndicator) {
                            return index <= root.animatedPercentage * 16 || Math.floor(root.chargingPulse) === index;
                        }
                        return (index + 0.5) / 16 <= root.animatedPercentage || (root.animatedPercentage > 0 && index === 0);
                    }

                    Rectangle {
                        x: bigDotWrapper.dotCenterX - width / 2
                        y: bigDotWrapper.dotCenterY - height / 2
                        width: 2.8
                        height: 2.8
                        radius: Appearance.rounding.full
                        color: bigDotWrapper.isActive ? root.highlightColor : root.trackColor

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.fadeFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                            }
                        }
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.isCharging && root.showChargingIndicator
                fill: 1
                text: "bolt"
                iconSize: Appearance.font.pixelSize.smaller
                color: root.highlightColor
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.displayInsideText
                text: root.rawPercentageText
                color: root.highlightColor
                font {
                    pixelSize: Appearance.font.pixelSize.smaller - 2
                    weight: Font.Bold
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 6: Portrait (AOSP / LineageOS Portrait Battery)
    // -------------------------------------------------------------
    Component {
        id: portraitComponent
        Item {
            implicitWidth: 14
            implicitHeight: 22

            Column {
                anchors.centerIn: parent
                spacing: 1

                // Top terminal / nub
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 5
                    height: 2
                    radius: Appearance.rounding.small
                    color: root.animatedPercentage >= 0.98 ? root.highlightColor : root.trackColor
                }

                // Battery body
                Rectangle {
                    id: vertBody
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 13
                    height: 18
                    radius: Appearance.rounding.small
                    color: root.trackColor
                    clip: true

                    // Bottom-anchored fill
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 1.5
                        height: Math.max(0, (vertBody.height - 3) * root.animatedPercentage)
                        radius: Appearance.rounding.small
                        color: root.highlightColor
                    }

                    // Bolt or inside percentage
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.isCharging && root.showChargingIndicator
                        fill: 1
                        text: "bolt"
                        iconSize: Appearance.font.pixelSize.smaller - 2
                        color: root.highlightColor
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.displayInsideText
                        text: root.rawPercentageText
                        color: root.animatedPercentage >= 0.6 ? Appearance.colors.colLayer1 : root.highlightColor
                        font {
                            pixelSize: Appearance.font.pixelSize.smaller - 3
                            weight: Font.Bold
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 7: Landscape (EvoX / crDroid Right Landscape Battery)
    // -------------------------------------------------------------
    Component {
        id: landscapeRightComponent
        Item {
            implicitWidth: 25
            implicitHeight: 14

            Row {
                anchors.centerIn: parent
                spacing: 1

                // Battery body
                Rectangle {
                    id: battBody
                    width: 21
                    height: 13
                    radius: Appearance.rounding.small
                    color: root.trackColor
                    clip: true

                    // Inner fill
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 1.5
                        width: Math.max(0, (battBody.width - 3) * root.animatedPercentage)
                        radius: Appearance.rounding.small
                        color: root.highlightColor
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.isCharging && root.showChargingIndicator
                        fill: 1
                        text: "bolt"
                        iconSize: Appearance.font.pixelSize.smaller - 2
                        color: root.highlightColor
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.displayInsideText
                        text: root.rawPercentageText
                        color: root.animatedPercentage >= 0.6 ? Appearance.colors.colLayer1 : root.highlightColor
                        font {
                            pixelSize: Appearance.font.pixelSize.smaller - 3
                            weight: Font.Bold
                        }
                    }
                }

                // Positive terminal / nub on right
                Rectangle {
                    anchors.verticalCenter: battBody.verticalCenter
                    width: 2.5
                    height: 5.5
                    radius: Appearance.rounding.small
                    color: root.animatedPercentage >= 0.98 ? root.highlightColor : root.trackColor
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 8: Landscape Left (Left Nub Landscape Battery)
    // -------------------------------------------------------------
    Component {
        id: landscapeLeftComponent
        Item {
            implicitWidth: 25
            implicitHeight: 14

            Row {
                anchors.centerIn: parent
                spacing: 1

                // Positive terminal / nub on left
                Rectangle {
                    anchors.verticalCenter: battBodyLeft.verticalCenter
                    width: 2.5
                    height: 5.5
                    radius: Appearance.rounding.small
                    color: root.animatedPercentage >= 0.98 ? root.highlightColor : root.trackColor
                }

                // Battery body
                Rectangle {
                    id: battBodyLeft
                    width: 21
                    height: 13
                    radius: Appearance.rounding.small
                    color: root.trackColor
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 1.5
                        width: Math.max(0, (battBodyLeft.width - 3) * root.animatedPercentage)
                        radius: Appearance.rounding.small
                        color: root.highlightColor
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.isCharging && root.showChargingIndicator
                        fill: 1
                        text: "bolt"
                        iconSize: Appearance.font.pixelSize.smaller - 2
                        color: root.highlightColor
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.displayInsideText
                        text: root.rawPercentageText
                        color: root.animatedPercentage >= 0.6 ? Appearance.colors.colLayer1 : root.highlightColor
                        font {
                            pixelSize: Appearance.font.pixelSize.smaller - 3
                            weight: Font.Bold
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 9: Landscape iOS (Iconify iOS 15/16 Style Battery)
    // -------------------------------------------------------------
    Component {
        id: landscapeIosComponent
        Item {
            implicitWidth: 26
            implicitHeight: 14

            Row {
                anchors.centerIn: parent
                spacing: 1

                Rectangle {
                    id: iosBody
                    width: 22
                    height: 13
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    border.color: root.highlightColor
                    border.width: 1.2
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 2
                        width: Math.max(0, (iosBody.width - 4) * root.animatedPercentage)
                        radius: Appearance.rounding.small
                        color: root.highlightColor
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.isCharging && root.showChargingIndicator
                        fill: 1
                        text: "bolt"
                        iconSize: Appearance.font.pixelSize.smaller - 2
                        color: root.highlightColor
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.displayInsideText
                        text: root.rawPercentageText
                        color: root.animatedPercentage >= 0.6 ? Appearance.colors.colLayer1 : root.highlightColor
                        font {
                            pixelSize: Appearance.font.pixelSize.smaller - 3
                            weight: Font.Bold
                        }
                    }
                }

                Rectangle {
                    anchors.verticalCenter: iosBody.verticalCenter
                    width: 2
                    height: 4.5
                    radius: Appearance.rounding.small
                    color: root.highlightColor
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 10: Landscape Line (EvoX Minimalist Line Bar)
    // -------------------------------------------------------------
    Component {
        id: landscapeLineComponent
        Item {
            implicitWidth: 28
            implicitHeight: 14

            RowLayout {
                anchors.centerIn: parent
                spacing: 2

                Rectangle {
                    id: lineTrack
                    width: 24
                    height: 6
                    radius: Appearance.rounding.full
                    color: root.trackColor
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: lineTrack.width * root.animatedPercentage
                        radius: Appearance.rounding.full
                        color: root.highlightColor
                    }
                }

                MaterialSymbol {
                    visible: root.isCharging && root.showChargingIndicator
                    fill: 1
                    text: "bolt"
                    iconSize: Appearance.font.pixelSize.smaller - 2
                    color: root.highlightColor
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 11: Landscape Musku (Iconify Musku Modern Sleek)
    // -------------------------------------------------------------
    Component {
        id: landscapeMuskuComponent
        Item {
            implicitWidth: 24
            implicitHeight: 14

            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 12
                radius: Appearance.rounding.small
                color: root.trackColor
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1.5
                    width: Math.max(0, (parent.width - 3) * root.animatedPercentage)
                    radius: Appearance.rounding.small
                    color: root.highlightColor
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3
                    color: root.highlightColor
                    opacity: root.animatedPercentage >= 0.95 ? 1.0 : 0.4
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.isCharging && root.showChargingIndicator
                    fill: 1
                    text: "bolt"
                    iconSize: Appearance.font.pixelSize.smaller - 2
                    color: root.highlightColor
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.displayInsideText
                    text: root.rawPercentageText
                    color: root.animatedPercentage >= 0.6 ? Appearance.colors.colLayer1 : root.highlightColor
                    font {
                        pixelSize: Appearance.font.pixelSize.smaller - 3
                        weight: Font.Bold
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 12: Landscape Origami (EvoX Origami Faceted Geometric)
    // -------------------------------------------------------------
    Component {
        id: landscapeOrigamiComponent
        Item {
            implicitWidth: 25
            implicitHeight: 14

            Shape {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.trackColor
                    startX: 2; startY: 1
                    PathLine { x: 20; y: 1 }
                    PathLine { x: 24; y: 5 }
                    PathLine { x: 24; y: 9 }
                    PathLine { x: 20; y: 13 }
                    PathLine { x: 2; y: 13 }
                    PathLine { x: 0; y: 11 }
                    PathLine { x: 0; y: 3 }
                    PathLine { x: 2; y: 1 }
                }

                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.highlightColor
                    startX: 2; startY: 2.5
                    PathLine { x: 2 + Math.max(0, 20 * root.animatedPercentage); y: 2.5 }
                    PathLine { x: 2 + Math.max(0, 20 * root.animatedPercentage); y: 11.5 }
                    PathLine { x: 2; y: 11.5 }
                    PathLine { x: 1; y: 10 }
                    PathLine { x: 1; y: 4 }
                    PathLine { x: 2; y: 2.5 }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.isCharging && root.showChargingIndicator
                fill: 1
                text: "bolt"
                iconSize: Appearance.font.pixelSize.smaller - 2
                color: root.highlightColor
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.displayInsideText
                text: root.rawPercentageText
                color: root.animatedPercentage >= 0.6 ? Appearance.colors.colLayer1 : root.highlightColor
                font {
                    pixelSize: Appearance.font.pixelSize.smaller - 3
                    weight: Font.Bold
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 13: Landscape Signal (EvoX Stepped Cellular Bars)
    // -------------------------------------------------------------
    Component {
        id: landscapeSignalComponent
        Item {
            implicitWidth: 26
            implicitHeight: 14

            Row {
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: 5
                    delegate: Rectangle {
                        width: 3.5
                        height: 4 + index * 2
                        anchors.bottom: parent.bottom
                        radius: Appearance.rounding.small
                        readonly property bool isActive: {
                            if (root.isCharging && root.showChargingIndicator) {
                                return index <= root.animatedPercentage * 5 || Math.floor(root.chargingPulse % 5) === index;
                            }
                            return (index + 0.5) / 5 <= root.animatedPercentage || (root.animatedPercentage > 0 && index === 0);
                        }
                        color: isActive ? root.highlightColor : root.trackColor

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.fadeFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                            }
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 14: Filled (Material 3 Expressive Pill / ClippedProgressBar)
    // -------------------------------------------------------------
    Component {
        id: filledComponent
        ClippedProgressBar {
            id: filledBar
            vertical: root.vertical

            // Proper width scaling depending on whether percentage text is inside or not
            valueBarWidth: {
                if (root.vertical) return 20;
                if (root.showPercentage === 1) {
                    if (root.isCharging && root.showChargingIndicator) {
                        return root.showPercentSign ? 43 : 37;
                    }
                    return root.showPercentSign ? 36 : 30;
                }
                // When text is outside or hidden: compact elegant pill
                return root.isCharging ? 26 : 24;
            }
            valueBarHeight: root.vertical ? 36 : 18
            value: root.percentage
            highlightColor: root.highlightColor
            trackColor: root.trackColor

            textMask: Item {
                anchors.centerIn: parent
                width: filledBar.valueBarWidth
                height: filledBar.valueBarHeight

                RowLayout {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 0.5
                    spacing: 0
                    visible: !root.vertical

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: -2
                        Layout.rightMargin: -1
                        fill: 1
                        text: "bolt"
                        iconSize: Appearance.font.pixelSize.smaller
                        visible: root.isCharging && root.showChargingIndicator
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        // ONLY display inside text if showPercentage is specifically 1 (Inside)!
                        visible: root.showPercentage === 1
                        font: filledBar.font
                        text: root.showPercentSign ? (root.percentageInt + "%") : root.rawPercentageText
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: -4
                    visible: root.vertical

                    MaterialSymbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        fill: 1
                        text: {
                            if (filledBar.value == 1) return "check";
                            if (root.isCharging && root.showChargingIndicator) return "bolt";
                            return Icons.getBatteryIcon(root.percentageInt);
                        }
                        iconSize: Appearance.font.pixelSize.normal
                    }
                    StyledText {
                        // ONLY display inside text if showPercentage is specifically 1 (Inside)!
                        visible: root.showPercentage === 1 && text.length <= 3
                        anchors.horizontalCenter: parent.horizontalCenter
                        font: filledBar.font
                        text: root.rawPercentageText
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Style 15: Text Only (Minimalist Typography)
    // -------------------------------------------------------------
    Component {
        id: textOnlyComponent
        RowLayout {
            spacing: 2

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: root.isCharging && root.showChargingIndicator
                fill: 1
                text: "bolt"
                iconSize: Appearance.font.pixelSize.smaller
                color: root.highlightColor
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: root.percentageText
                color: root.contentColor
                font {
                    pixelSize: Appearance.font.pixelSize.small
                    weight: Font.DemiBold
                }
            }
        }
    }
}
