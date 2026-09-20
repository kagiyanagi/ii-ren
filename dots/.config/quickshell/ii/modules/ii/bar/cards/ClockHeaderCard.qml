pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.animations
import qs.services

Rectangle {
    id: root

    Layout.fillWidth: true
    Layout.preferredHeight: 200
    implicitHeight: 200

    radius: Appearance.rounding.large
    color: Appearance.colors.colPrimaryContainer

    // Internal animation control
    property bool startAnim: false

    // Face, hand, time, suffix, day, date: staggerStep apart and capped
    // (DESIGN.md 2.8), each with opacity on an effects spec and at most one
    // transform on the enter spec (2.1, 2.5).
    readonly property int enterTravel: 24

    onStartAnimChanged: {
        if (!root.startAnim) return;
        clockCircle.opacity = 0.0;
        clockCircleTranslate.x = -root.enterTravel;
        clockHand.opacity = 0.0;
        timeText.opacity = 0.0;
        timeText.scale = 0.9;
        ampmText.opacity = 0.0;
        dayText.opacity = 0.0;
        dayText.translateX = root.enterTravel;
        dateText.opacity = 0.0;
        dateText.translateX = root.enterTravel;
        Qt.callLater(() => {
            clockCircleAnim.restart();
            clockHandAnim.restart();
            timeAnim.restart();
            ampmAnim.restart();
            dayAnim.restart();
            dateAnim.restart();
        });
    }

    component EnterFade: DelayedPropertyAnimation {
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    component EnterMove: DelayedPropertyAnimation {
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    // Keep rounded clipping for the oversized clock artwork. Render the mask
    // layer at 2x so the popup scale does not enlarge a low-resolution card.
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * 2)), Math.max(1, Math.ceil(height * 2)))
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.radius
            antialiasing: true
        }
    }

    // Left-side clock circle container (approx 306px, centered on screen layout)
    Item {
        id: clockCircle
        width: parent.height * 1.53
        height: width
        opacity: 0.0
        anchors {
            left: parent.left
            leftMargin: -width * 0.52
            verticalCenter: parent.verticalCenter
        }
        
        transform: Translate {
            id: clockCircleTranslate
            x: -root.enterTravel
        }

        ParallelAnimation {
            id: clockCircleAnim

            EnterFade {
                target: clockCircle
            }
            EnterMove {
                target: clockCircleTranslate
                property: "x"
                from: -root.enterTravel
            }
        }

        // The face used to be rendered offscreen and composited back through a
        // radial-gradient pair, an OpacityMask and a MaskedBlur -- four effects
        // for a soft glow on one corner, on a shell that targets integrated
        // graphics (DESIGN.md 8, law 8). It draws in place now; the card's own
        // rounded-clip layer is the one effect this widget gets.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Appearance.colors.colPrimary
        }

        Item {
            id: ticksContainer
            anchors.fill: parent
            z: 1

            Repeater {
                model: 90
                delegate: Rectangle {
                    id: tick

                    required property int index
                    width: 2.5
                    height: ticksContainer.width / 2 * 0.17 // r * 0.17 (equivalent to r2 - r1)
                    color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.55)
                    antialiasing: true

                    x: ticksContainer.width / 2 - tick.width / 2
                    y: ticksContainer.height / 2 - ticksContainer.height / 2 * 0.95 // top of the tick is at cy - r2

                    transform: Rotation {
                        origin.x: tick.width / 2
                        origin.y: ticksContainer.height / 2 * 0.95 // r2
                        angle: tick.index * 4 // 360 / 90 = 4 degrees per tick
                    }
                }
            }

            RotationAnimation on rotation {
                from: 0
                to: 360
                // design-ok: one turn per minute is a clock rate, not a motion token
                duration: 60000
                loops: Animation.Infinite
            }
        }

        // Fixed horizontal tertiary hand pointing right, on top of the face
        Rectangle {
            id: clockHand
            width: parent.width * 0.183
            height: 4
            color: Appearance.colors.colTertiary
            radius: Appearance.rounding.full
            z: 10 // Force rendering on top of everything
            opacity: 0.0

            // Positioned relative to clockCircle center using simple local coordinates:
            // Proportional and extends slightly outside the circle
            x: parent.width - width + (parent.width * 0.06)
            y: parent.height / 2 - height / 2

            EnterFade {
                id: clockHandAnim
                target: clockHand
                delay: Appearance.animation.staggerStep
            }
        }
    }



    // Right-side time & date information
    ColumnLayout {
        anchors {
            right: parent.right
            rightMargin: 24
            left: parent.left
            leftMargin: clockCircle.width + clockCircle.anchors.leftMargin + 34 // Ensure layout doesn't collide with the clock face dynamically
            verticalCenter: parent.verticalCenter
        }
        spacing: -10

        // Time row separating digits from AM/PM suffix
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            // Time digits (HH:MM) - Custom Maximum Bold Weight (1000 wght axis)
            StyledText {
                id: timeText
                text: {
                    const timeStr = DateTime.time;
                    const match = timeStr.match(/^(\d{1,2}:\d{2})(?:\s*(AM|PM|am|pm))?$/);
                    return match ? match[1] : timeStr;
                }
                font.pixelSize: Math.min(72, root.width * 0.17)
                font.family: Appearance.font.family.title
                font.variableAxes: ({
                        "wght": 800
                    }) // Maximum bold weight for variable font
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.0
                scale: 0.9

                ParallelAnimation {
                    id: timeAnim

                    EnterFade {
                        target: timeText
                        delay: Appearance.animation.staggerStep * 2
                    }
                    EnterMove {
                        target: timeText
                        property: "scale"
                        from: 0.9
                        to: 1
                        delay: Appearance.animation.staggerStep * 2
                    }
                }
            }

            // AM/PM suffix - Smaller & Thin (200 wght axis)
            StyledText {
                id: ampmText
                text: {
                    const timeStr = DateTime.time;
                    const match = timeStr.match(/^(\d{1,2}:\d{2})(?:\s*(AM|PM|am|pm))?$/);
                    return (match && match[2]) ? match[2] : "";
                }
                visible: text !== ""
                font.pixelSize: Math.min(20, root.width * 0.048) // Smaller size
                font.family: Appearance.font.family.title
                font.variableAxes: ({
                        "wght": 400
                    }) // Thin weight for variable font
                color: Appearance.colors.colOnPrimaryContainer
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: Math.min(14, root.width * 0.033) // Align baseline to bottom of time digits
                opacity: 0.0

                EnterFade {
                    id: ampmAnim
                    target: ampmText
                    delay: Appearance.animation.staggerStep * 3
                }
            }
        }

        // Date row centered underneath
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            StyledText {
                id: dayText
                property real translateX: root.enterTravel
                text: Qt.locale().toString(DateTime.clock.date, "dddd")
                font.pixelSize: Math.min(20, root.width * 0.048)
                font.family: Appearance.font.family.title
                font.weight: Font.Normal
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.0
                transform: Translate { x: dayText.translateX }

                ParallelAnimation {
                    id: dayAnim

                    EnterFade {
                        target: dayText
                        delay: Appearance.animation.staggerStep * 4
                    }
                    EnterMove {
                        target: dayText
                        property: "translateX"
                        from: root.enterTravel
                        delay: Appearance.animation.staggerStep * 4
                    }
                }
            }

            StyledText {
                id: dateText
                property real translateX: root.enterTravel
                text: Qt.locale().toString(DateTime.clock.date, "dd MMMM")
                font.pixelSize: Math.min(20, root.width * 0.048)
                font.family: Appearance.font.family.title
                font.weight: Font.Normal
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.0
                transform: Translate { x: dateText.translateX }

                ParallelAnimation {
                    id: dateAnim

                    EnterFade {
                        target: dateText
                        delay: Appearance.animation.staggerStep * 5
                    }
                    EnterMove {
                        target: dateText
                        property: "translateX"
                        from: root.enterTravel
                        delay: Appearance.animation.staggerStep * 5
                    }
                }
            }
        }
    }
}
