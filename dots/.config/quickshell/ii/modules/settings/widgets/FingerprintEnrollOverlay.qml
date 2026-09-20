pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Guided fingerprint enrollment: pick a finger, then scan it.
 *
 * The ring is the determinate M3 circular progress indicator (DESIGN.md 9),
 * filled by completed enrollment stage. "How many more times do I touch this
 * thing" is the useful question during enrollment, and the stage counter under
 * the ring answers it exactly; the ring answers "am I nearly there" without
 * 16 hand-placed ticks and their trigonometry.
 */
Item {
    id: root

    property bool shown: false
    signal closed

    // pick | scan
    property string step: "pick"
    property string finger: ""

    readonly property bool scanning: Fingerprint.enrollActive && Fingerprint.enrollPhase !== "done"
    readonly property bool succeeded: Fingerprint.enrollPhase === "done"
    readonly property bool failed: Fingerprint.enrollPhase === "failed"
    readonly property bool readerMissing: Fingerprint.probed && !Fingerprint.deviceAvailable

    // fprintd sends "you moved too fast" down the same channel as real
    // progress: the phase stays "scanning", the stage holds where it was, and
    // only the message changes (fprintd_bridge.py's ENROLL_RETRY). The service
    // has no field for it, so it is derived here — otherwise a botched scan
    // reads exactly like a good one, and one of the retry codes,
    // enroll-remove-and-retry, carries the *same sentence* a passed stage does.
    property bool retrying: false
    // handleEvent() writes phase, then stage, then message, so a real advance
    // announces itself before the message describing it. Comparing against a
    // remembered stage does not work: two passed stages in a row carry an
    // identical message, so the message signal does not fire at all and the
    // remembered value goes stale. A latch cleared after the event does.
    property bool stageAdvanced: false
    // The run's first "Touch the reader" arrives with the stage still at 0 and
    // is not a retry, so a retry has to follow a message that was already
    // scanning.
    property bool sawScanning: false

    function clearStageAdvanced(): void {
        root.stageAdvanced = false;
    }

    function resetRetryState(): void {
        root.retrying = false;
        root.stageAdvanced = false;
        root.sawScanning = false;
    }

    // Opacity must not overshoot, so both directions are effects specs and the
    // exit takes the faster one (DESIGN.md 2.1, 2.5). Assigned from inside the
    // binding that writes opacity, per DESIGN.md 2.9 — a Behavior reading
    // `shown` bakes the spec one trigger late and exits on the enter's.
    property AnimSpec fadeSpec: Appearance.animation.elementMoveFast

    function open(preselected: string): void {
        Fingerprint.resetEnrollState();
        root.finger = preselected ?? "";
        root.step = "pick";
        root.resetRetryState();
        root.shown = true;
    }

    function close(): void {
        successCloseTimer.stop();
        if (Fingerprint.enrollActive)
            Fingerprint.cancelEnroll();
        Fingerprint.resetEnrollState();
        root.shown = false;
        root.closed();
    }

    function beginScan(): void {
        if (root.finger === "")
            return;
        root.step = "scan";
        root.resetRetryState();
        Fingerprint.startEnroll(root.finger);
    }

    Connections {
        target: Fingerprint

        function onEnrollStageChanged(): void {
            root.retrying = false;
            root.stageAdvanced = true;
            // Runs once the whole event has been applied, so the latch is up
            // for this event's message and down for the next one's.
            Qt.callLater(root.clearStageAdvanced);
        }

        function onEnrollMessageChanged(): void {
            root.retrying = !root.stageAdvanced && root.sawScanning && Fingerprint.enrollPhase === "scanning";
            root.sawScanning = Fingerprint.enrollPhase === "scanning";
        }
    }

    visible: opacity > 0
    opacity: {
        root.fadeSpec = root.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
        return root.shown ? 1 : 0;
    }
    enabled: root.shown

    Behavior on opacity {
        NumberAnimation {
            duration: root.fadeSpec.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.fadeSpec.bezierCurve
        }
    }

    // A modal closes on Escape (DESIGN.md 3.7). Unlike a click on the scrim,
    // which is refused mid-scan because it is easy to do by accident, Escape
    // is deliberate and close() cancels the enrollment cleanly.
    focus: root.shown
    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Escape)
            return;
        event.accepted = true;
        root.close();
    }

    // Close by itself once the success state has been on screen long enough
    // to register as a success rather than a flicker.
    Timer {
        id: successCloseTimer
        interval: 1600
        onTriggered: root.close()
    }

    onSucceededChanged: {
        if (root.succeeded && root.shown)
            successCloseTimer.restart();
    }

    // Scrim: also swallows clicks aimed at the page underneath.
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (!root.scanning)
                    root.close();
            }
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        implicitHeight: cardLayout.implicitHeight + 40
        height: implicitHeight
        radius: Appearance.rounding.verylarge
        // Opaque base, not colLayer1: the layer colours are solved against
        // contentTransparency so a panel on the desktop can show through, and
        // a modal card that shows the page it is blocking is unreadable.
        // WindowDialog does the same thing for the same reason. Children stay
        // on colLayer2, which is already solved against this exact surface.
        color: Appearance.colors.colLayer1Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        // A modal dims what it covers and belongs to no control on the page, so
        // it grows from its own centre (DESIGN.md 2.6).
        transformOrigin: Item.Center
        scale: root.shown ? 1 : 0.94

        // Scale is spatial, so it enters decelerating over the full spec and
        // leaves accelerating at half of it (DESIGN.md 2.5). Written from the
        // signal handler rather than bound, for the reason in DESIGN.md 2.9.
        Connections {
            target: root

            function onShownChanged(): void {
                cardScaleAnimation.duration = root.shown ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveFast.duration / 2;
                cardScaleAnimation.easing.bezierCurve = root.shown ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel;
            }
        }

        Behavior on scale {
            NumberAnimation {
                id: cardScaleAnimation
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        // Keep clicks on the card from reaching the scrim behind it.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }

        ColumnLayout {
            id: cardLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.step === "pick" ? Translation.tr("Choose a finger") : Fingerprint.labelFor(root.finger)
                font.pixelSize: Appearance.font.pixelSize.larger
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                visible: root.step === "pick"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Translation.tr("Pick the finger you want to use. Choosing one that is already enrolled replaces it.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            // ── Step 1: finger picker ──────────────────────────────────────
            FingerprintHandPicker {
                Layout.alignment: Qt.AlignHCenter
                visible: root.step === "pick"
                selectedFinger: root.finger
                onFingerPicked: finger => root.finger = finger
            }

            // ── Step 2: scanning ───────────────────────────────────────────
            // The ring is sized from the glyph it encircles rather than from a
            // number of its own: it exists to frame that symbol.
            CircularProgress {
                Layout.alignment: Qt.AlignHCenter
                visible: root.step === "scan"
                implicitSize: scanSymbol.iconSize * 2
                lineWidth: 8
                value: Fingerprint.numEnrollStages > 0 ? Fingerprint.enrollStage / Fingerprint.numEnrollStages : 0
                // Failure paints the whole ring, so the progress that was made
                // is not left looking like it still counts.
                colPrimary: root.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
                colSecondary: root.failed ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHighest

                MaterialSymbol {
                    id: scanSymbol

                    anchors.centerIn: parent
                    text: root.succeeded ? "check_circle" : root.failed ? "error" : "fingerprint"
                    iconSize: 76
                    fill: 1
                    // Four states, four reads: complete is primary, failed is
                    // error, a retry is tertiary — the "adjust and go again"
                    // role, deliberately not the failure one — and a scan in
                    // progress is plain content colour.
                    color: root.succeeded ? Appearance.colors.colPrimary : root.failed ? Appearance.colors.colError : root.retrying ? Appearance.colors.colTertiary : Appearance.colors.colOnLayer1

                    // A slow breath while waiting for a touch, so the dialog
                    // never looks frozen between stages. InOutSine rather than
                    // an Appearance curve because this is a symmetric
                    // oscillation, not a transition — every curve in the token
                    // table is one-directional and would make it lurch.
                    SequentialAnimation on opacity {
                        running: root.scanning && Fingerprint.enrollPhase !== "authorizing"
                        loops: Animation.Infinite
                        // Infinite loops make this "finish the current
                        // iteration", so the glyph always settles back at 1
                        // rather than stopping half faded.
                        alwaysRunToEnd: true

                        NumberAnimation {
                            to: 0.45
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            to: 1
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.step === "scan" && !root.succeeded && !root.failed
                text: `${Fingerprint.enrollStage} / ${Fingerprint.numEnrollStages}`
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                visible: root.step === "scan" && text !== ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Fingerprint.enrollMessage
                font.pixelSize: Appearance.font.pixelSize.small
                // Same four reads as the glyph. "Lift your finger and touch
                // again" after a good scan and "swipe was too short" after a
                // bad one are the same sentence shape; the colour is what
                // tells them apart.
                color: root.failed ? Appearance.colors.colError : root.succeeded ? Appearance.colors.colPrimary : root.retrying ? Appearance.colors.colTertiary : Appearance.colors.colOnLayer1
            }

            // A reader that is gone is not an enrollment failure, so it gets
            // the neutral notice rather than the error one — and it says so,
            // instead of only greying out the Start button.
            NoticeBox {
                Layout.fillWidth: true
                visible: root.step === "pick" && root.readerMissing
                materialIcon: "sensors_off"
                text: Translation.tr("No fingerprint reader is available, so nothing can be enrolled right now. The Reader section behind this dialog shows what fprintd reports.")
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                spacing: 8

                DialogButton {
                    visible: !root.succeeded
                    // "Stop" only means something while something is running;
                    // a failed enrollment already stopped itself.
                    buttonText: root.scanning ? Translation.tr("Stop") : Translation.tr("Cancel")
                    onClicked: root.close()
                }

                DialogButton {
                    visible: root.step === "pick"
                    enabled: root.finger !== "" && Fingerprint.deviceAvailable
                    buttonText: Fingerprint.enrolled.indexOf(root.finger) !== -1 ? Translation.tr("Replace") : Translation.tr("Start")
                    onClicked: root.beginScan()
                }

                DialogButton {
                    visible: root.failed
                    buttonText: Translation.tr("Try again")
                    onClicked: {
                        Fingerprint.resetEnrollState();
                        root.step = "pick";
                    }
                }

                DialogButton {
                    visible: root.succeeded
                    buttonText: Translation.tr("Done")
                    onClicked: root.close()
                }
            }
        }
    }
}
