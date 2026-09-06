pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * The listening surface for the wake word: a pill that rises from the bottom of
 * the screen when the phrase is heard, shows the request going in as a live
 * waveform, and leaves once the answer is on its way.
 *
 * It is deliberately absent while merely armed. An always-on indicator for a
 * feature that is always on is just furniture - the microphone already has an
 * honest home in the privacy indicator, which shows it because it is a real
 * PipeWire stream. This appears only when the shell is actually listening *to
 * you*, which is the moment worth seeing.
 */
Scope {
    id: root

    // Only the hands-free cycle drives this. Without the latch a turn typed at
    // the keyboard would raise the pill too, because `responding` is shared.
    property bool startedByWake: false

    readonly property bool busy: root.startedByWake
        && (GlobalStates.wakeCapturing || HermesService.speech.transcribing || HermesService.busy)

    property bool shown: false

    readonly property string caption: {
        if (GlobalStates.wakeCapturing) return Translation.tr("Listening…");
        if (HermesService.speech.transcribing) return Translation.tr("Just a moment…");
        return Translation.tr("Thinking…");
    }

    /*
     * A rolling window of recent input levels. The detector reports one every
     * 80ms while capturing, so this is about three seconds of speech - enough
     * that the pauses between words are visible, which is what makes the strip
     * read as speech rather than as decoration.
     */
    readonly property int barCount: 36
    property var levels: []

    Connections {
        target: HermesService.wake

        function onWoke(phrase, score) {
            root.startedByWake = true;
            root.levels = [];
        }
    }

    onBusyChanged: {
        if (root.busy) {
            hideTimer.stop();
            root.shown = true;
        } else if (root.shown) {
            hideTimer.restart();
        }
    }

    Connections {
        target: GlobalStates

        function onWakeLevelChanged() {
            if (!GlobalStates.wakeCapturing) return;
            // Reassigned rather than mutated: a push() on a var property does not
            // fire a change, so the visualiser would never repaint.
            const next = root.levels.concat([GlobalStates.wakeLevel * 1000]);
            root.levels = next.length > root.barCount ? next.slice(next.length - root.barCount) : next;
        }
    }

    Timer {
        id: hideTimer
        // Long enough that the pill does not blink out between the transcript
        // landing and the agent starting to answer.
        interval: 1200
        onTriggered: {
            root.shown = false;
            root.startedByWake = false;
            root.levels = [];
        }
    }

    PanelWindow {
        id: wakeWindow

        readonly property real gutter: Appearance.sizes.hyprlandGapsOut

        // Stays mapped until the pill has finished leaving. Never while locked:
        // what someone asks the assistant is not lock screen content.
        visible: (root.shown || pill.opacity > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        color: "transparent"

        WlrLayershell.namespace: "quickshell:wakeOverlay"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0

        anchors {
            left: true
            right: true
            bottom: true
        }

        implicitHeight: pill.implicitHeight + wakeWindow.gutter * 2 + Appearance.sizes.elevationMargin

        mask: Region {
            item: pill.opacity > 0 ? pill : null
        }

        Rectangle {
            id: pill

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: wakeWindow.gutter

            implicitWidth: pillLayout.implicitWidth + pillLayout.anchors.margins * 2
            implicitHeight: pillLayout.implicitHeight + pillLayout.anchors.margins * 2
            width: implicitWidth
            height: implicitHeight

            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer1

            opacity: 0
            scale: 0.8
            // It rises from the bottom edge, so it grows out of it.
            transformOrigin: Item.Bottom

            // Widening as the waveform fills in is a resize, not an entrance.
            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            states: State {
                name: "shown"
                when: root.shown
            }

            transitions: [
                // Enter: decelerating on default spatial, the fade landing sooner
                // so the caption is readable while the pill is still growing.
                Transition {
                    to: "shown"
                    ParallelAnimation {
                        NumberAnimation {
                            target: pill
                            property: "scale"
                            to: 1
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            target: pill
                            property: "opacity"
                            to: 1
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                },
                // Exit: accelerating, on the fast effects spec - the answer is
                // already coming, so it leaves in a fraction of the time it took
                // to arrive.
                Transition {
                    from: "shown"
                    ParallelAnimation {
                        NumberAnimation {
                            target: pill
                            property: "scale"
                            to: 0.8
                            duration: Appearance.animation.elementMoveExit.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                        }
                        NumberAnimation {
                            target: pill
                            property: "opacity"
                            to: 0
                            duration: Appearance.animation.elementMoveExit.duration
                        }
                    }
                }
            ]

            RowLayout {
                id: pillLayout

                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                MaterialSymbol {
                    text: "graphic_eq"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                    Layout.leftMargin: 4
                }

                StyledText {
                    text: root.caption
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }

                // Only while there is something to draw: the strip would otherwise
                // sit flat and empty through the whole thinking phase.
                //
                // Wrapped rather than placed in the row directly: WaveVisualizer
                // anchors itself to its parent, and anchors on an item a layout is
                // managing is undefined behaviour - Qt warns about it by name. The
                // Item is the layout child; the visualiser fills the Item.
                Item {
                    visible: GlobalStates.wakeCapturing
                    Layout.preferredWidth: 132
                    Layout.preferredHeight: 28
                    Layout.rightMargin: 4

                    WaveVisualizer {
                        points: root.levels
                        maxVisualizerValue: 1000
                        color: Appearance.colors.colPrimary
                        live: GlobalStates.wakeCapturing
                        maxFps: 30
                    }
                }
            }
        }
    }
}
