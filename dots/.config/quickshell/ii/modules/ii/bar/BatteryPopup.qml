import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "./cards"
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

StyledPopup {
    id: root
    stickyHover: true
    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    readonly property bool hasTimeData: {
        const timeValue = Battery.isCharging ? Battery.timeToFullEffective : Battery.timeToEmpty;
        const power = Battery.energyRate;
        return !(Battery.chargeState === 4 || Battery.chargeLimitReached || timeValue <= 0 || power <= 0.01);
    }

    // Hide the limit label when it would collide with the fixed 0/50/100 labels
    readonly property bool showLimitLabel: Battery.chargeLimitActive && Battery.chargeLimit >= 8
        && Battery.chargeLimit <= 92 && Math.abs(Battery.chargeLimit - 50) >= 8

    // Hero card glow color logic:
    readonly property color heroGlowColor: {
        if (Battery.percentage <= 0.15 && !Battery.isCharging)
            return Appearance.m3colors.m3error;
        // M3 has no positive/success role, and this palette is near-monochrome,
        // so tertiary would be indistinguishable from the discharging primary.
        // Charging needs a signal colour the theme cannot supply.
        if (Battery.isCharging || Battery.chargeLimitReached)
            // design-ok: wants an Appearance.colors.colPositive; none exists yet.
            return "#10E055";
        return Appearance.colors.colPrimary;
    }

    component AxisLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.small
        font.family: Appearance.font.family.numbers
        color: Appearance.colors.colOnSurfaceVariant
    }

    /*
     * Contract 1's one entrance rule (DESIGN.md 2.8), the same shape every popup
     * in this cluster uses: opacity on an effects spec, one transform on the
     * enter spatial spec, siblings offset by their place in the visible order.
     * `running` is bound to the popup's open state, so a close stops it
     * mid-flight and the `from:` values restore the start state on the next open.
     * That is the whole of the reset the two ~60-line property-poke blocks and
     * their `popupOpenProgress` Connections used to do by hand.
     *
     * The metric tiles do it themselves through MetricCard.startAnim/animDelay.
     * Exit is the surface's own arrowPopup close, inherited from StyledPopup;
     * the content does not animate out separately.
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

    ColumnLayout {
        id: mainLayout
        anchors.centerIn: parent
        spacing: 16

        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6

        readonly property var _visList: [
            true, // hero
            true, // grid cell 1
            true, // grid cell 2
            true, // grid cell 3
            true  // grid cell 4
        ]

        // Counted over *visible* siblings, so a hidden tile does not leave a
        // hole in the stagger.
        function getDelay(index) {
            let visIndex = 0;
            for (let i = 0; i < index; i++) {
                if (_visList[i])
                    visIndex++;
            }
            return Appearance.animation.staggerStep * Math.min(visIndex, Appearance.animation.staggerCap);
        }

        // HERO CARD - how long you have left, which is what this popup is for.
        Rectangle {
            id: batteryHero
            Layout.preferredWidth: 380
            Layout.preferredHeight: 220
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHigh

            opacity: 0
            transform: Translate {
                id: batteryHeroSlide
            }

            EnterAnim {
                item: batteryHero
                slide: batteryHeroSlide
                delay: mainLayout.getDelay(0)
                running: mainLayout.startAnim
            }

            // The gauge fills in from empty once the card is in place. This is
            // the reading, not decoration, so it is the one thing in here that
            // animates on its own.
            property real animProgress: 0.0

            NumberAnimation {
                target: batteryHero
                property: "animProgress"
                from: 0
                to: 1
                running: mainLayout.startAnim
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12

                StyledText {
                    text: {
                        if (Battery.chargeState === 4)
                            return Translation.tr("Fully Charged");
                        if (Battery.chargeLimitReached)
                            return Translation.tr("Charge limit reached");
                        if (Battery.isCharging)
                            return Translation.tr("Charging...");
                        return Translation.tr("Discharging...");
                    }
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurfaceVariant
                }

                RowLayout {
                    spacing: 8

                    StyledText {
                        text: Math.floor(Battery.percentage * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: "•"
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnSurface
                        visible: root.hasTimeData
                    }

                    StyledText {
                        text: {
                            if (!root.hasTimeData && Battery.chargeState !== 4 && !Battery.chargeLimitReached)
                                return Translation.tr("Calculating...");
                            if (Battery.chargeState === 4 || Battery.chargeLimitReached)
                                return "";
                            const time = root.formatTime(Battery.isCharging ? Battery.timeToFullEffective : Battery.timeToEmpty);
                            if (Battery.isCharging && Battery.chargeLimitActive)
                                return Translation.tr("%1 until %2%").arg(time).arg(Battery.chargeLimit);
                            return Translation.tr("%1 left").arg(time);
                        }
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                        visible: root.hasTimeData
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                Item {
                    id: axisLabels
                    Layout.fillWidth: true
                    implicitHeight: axisLabelZero.implicitHeight

                    AxisLabel {
                        id: axisLabelZero
                        text: "0"
                        anchors.left: parent.left
                    }

                    AxisLabel {
                        text: "50"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    AxisLabel {
                        text: "100"
                        anchors.right: parent.right
                    }

                    Loader {
                        active: root.showLimitLabel
                        x: axisLabels.width * (Battery.chargeLimit / 100) - width / 2
                        sourceComponent: AxisLabel {
                            text: Battery.chargeLimit
                        }
                    }
                }

                Item {
                    id: batteryBarContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64

                    Rectangle {
                        id: batteryTrack
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        color: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.9)
                    }

                    Rectangle {
                        id: batteryFill
                        width: parent.width * Battery.percentage * batteryHero.animProgress
                        height: parent.height
                        radius: Appearance.rounding.normal
                        color: root.heroGlowColor
                    }

                    Rectangle {
                        id: centerMarkerLine
                        width: 2
                        height: parent.height / 3
                        anchors.centerIn: parent
                        radius: Appearance.rounding.full
                        color: ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.9)
                        z: 1  // to stay above the fill
                    }

                    Loader {
                        active: Battery.chargeLimitActive
                        anchors.verticalCenter: parent.verticalCenter
                        x: batteryBarContainer.width * (Battery.chargeLimit / 100) - width / 2
                        z: 1  // to stay above the fill, same as the center marker
                        sourceComponent: Rectangle {
                            implicitWidth: 2
                            implicitHeight: batteryBarContainer.height / 3
                            radius: Appearance.rounding.full
                            color: ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.9)
                        }
                    }
                }
            }
        }

        // DETAILED INFO GRID. No divider above it: sections are separated by the
        // 16 of `spacing` and their own container layer (design law 11, 5.5).
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 12
            columnSpacing: 12

            MetricCard {
                shapeString: "Circle"
                radius: Appearance.rounding.large
                title: Translation.tr("Health")
                symbol: "health_metrics"
                value: `${Battery.health.toFixed(0)}%`
                accentColor: Appearance.colors.colPrimaryContainer
                symbolColor: Appearance.colors.colOnPrimaryContainer
                startAnim: mainLayout.startAnim
                animDelay: mainLayout.getDelay(1)
            }

            MetricCard {
                shapeString: "Circle"
                radius: Appearance.rounding.large
                title: Battery.isCharging ? Translation.tr("Input") : Translation.tr("Draw")
                symbol: Battery.isCharging ? "electric_bolt" : "power"
                value: `${Math.abs(Battery.energyRate).toFixed(1)}W`
                accentColor: Appearance.colors.colSecondaryContainer
                symbolColor: Appearance.colors.colOnSecondaryContainer
                startAnim: mainLayout.startAnim
                animDelay: mainLayout.getDelay(2)
            }

            MetricCard {
                shapeString: "Circle"
                radius: Appearance.rounding.large
                title: Translation.tr("Cycles")
                symbol: "autorenew"
                value: {
                    if (Battery.cycles >= 0)
                        return Battery.cycles.toString();
                    return Battery.health > 0 ? `~${Math.round((100 - Battery.health) * 10)}` : "--";
                }
                accentColor: Appearance.colors.colTertiaryContainer
                symbolColor: Appearance.colors.colOnTertiaryContainer
                startAnim: mainLayout.startAnim
                animDelay: mainLayout.getDelay(3)
            }

            MetricCard {
                shapeString: "Circle"
                radius: Appearance.rounding.large
                title: Translation.tr("Status")
                symbol: Battery.isLowAndNotCharging ? "battery_alert"
                    : Battery.isCharging ? "battery_charging_full" : "battery_full"
                value: {
                    if (Battery.chargeState === 4)
                        return Translation.tr("Full");
                    if (Battery.chargeLimitReached)
                        return Translation.tr("Limit reached");
                    if (Battery.isCharging)
                        return Translation.tr("Charging");
                    return Translation.tr("Discharging");
                }
                accentColor: Battery.isLowAndNotCharging ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                symbolColor: Battery.isLowAndNotCharging ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                startAnim: mainLayout.startAnim
                animDelay: mainLayout.getDelay(4)
            }
        }
    }
}
