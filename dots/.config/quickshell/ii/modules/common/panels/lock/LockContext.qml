import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Scope {
    id: root

    enum ActionEnum { Unlock, Poweroff, Reboot }

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    // These properties are in the context and not individual lock surfaces
    // so all surfaces can share the same state.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false

    // ── Fingerprint ───────────────────────────────────────────────────────
    // Enrolled prints come from the Fingerprint service rather than a second
    // fprintd-list of our own, so the lock screen and the settings page can
    // never disagree about what is enrolled.
    readonly property bool fingerprintsConfigured: Config.options.lock.security.fingerprint.enable && Fingerprint.hasEnrolled
    readonly property int fingerprintMaxAttempts: Config.options.lock.security.fingerprint.maxAttempts
    property int fingerprintAttempts: 0
    // Errors are counted separately from failed matches and are what actually
    // guards the re-arm loop. A failed match costs a finger on the sensor; an
    // error costs nothing and returns instantly, so an unbounded re-arm on
    // error is a spin loop — which is exactly how this drove the reader into
    // "Device disabled to prevent overheating".
    property int fingerprintErrors: 0
    readonly property int fingerprintMaxErrors: 5
    readonly property bool fingerprintExhausted: root.fingerprintAttempts >= root.fingerprintMaxAttempts || root.fingerprintErrors >= root.fingerprintMaxErrors
    property bool fingerprintFailed: false

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    function resetClearTimer() {
        passwordClearTimer.restart();
    }

    function reset() {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
        stopFingerPam();
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        onTriggered: {
            root.reset();
        }
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) {
            showFailure = false;
            GlobalStates.screenUnlockFailed = false;
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        passwordClearTimer.restart();
    }

    function tryUnlock(alsoInhibitIdle = false) {
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.unlockInProgress = true;
        pam.start();
    }

    function tryFingerUnlock() {
        // Only ever while the screen is genuinely locked. Arming pam_fprintd
        // on an unlocked session claims the reader for nobody, blocks anything
        // else that wants it, and — with no one there to stop it — lets any
        // error it hits drive the re-arm loop unattended.
        if (!GlobalStates.screenLocked)
            return;
        if (!root.fingerprintsConfigured || root.fingerprintExhausted)
            return;
        if (fingerPam.active)
            return;
        fingerPam.start();
    }

    // Never leave the reader armed behind an unlocked screen, however the
    // unlock happened — password, fingerprint, or another surface.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked)
                root.stopFingerPam();
        }
    }

    function stopFingerPam() {
        if (fingerPam.active) {
            fingerPam.abort();
        }
    }

    /** Called when the screen locks, so every lock starts with a full budget. */
    function resetFingerprint() {
        root.fingerprintAttempts = 0;
        root.fingerprintErrors = 0;
        root.fingerprintFailed = false;
        fingerprintRearmTimer.stop();
        fingerprintRearmTimer.interval = root.fingerprintRearmDelay;
        // Prints are enrolled from the settings app, which is a separate
        // process, so the shell cannot be told — it has to ask again. Locking
        // is both the moment the answer matters and rare enough to re-probe
        // on. Without this a print enrolled after the shell started stays
        // invisible until the shell restarts.
        if (Config.options.lock.security.fingerprint.enable)
            Fingerprint.refresh();
        root.tryFingerUnlock();
    }

    // Arm the reader as soon as there is something to unlock with. Enrolling a
    // print in settings while the screen is locked is not possible, but
    // turning the feature on from another session is.
    onFingerprintsConfiguredChanged: {
        if (root.fingerprintsConfigured)
            root.tryFingerUnlock();
        else
            root.stopFingerPam();
    }

    PamContext {
        id: pam

        // pam_unix will ask for a response for the password prompt
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.currentText);
            }
        }

        // pam_unix won't send any important messages so all we need is the completion status.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                GlobalStates.screenUnlockFailed = true;
                root.showFailure = true;
            }
        }
    }

    PamContext {
        id: fingerPam

        configDirectory: "pam"
        config: "fprintd.conf"

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.fingerprintFailed = false;
                root.unlocked(root.targetAction);
                stopFingerPam();
                return;
            }

            // Failed is a finger that did not match, and is the only result
            // that spends a user-visible attempt. Error means the reader
            // refused the conversation — busy, disabled, overheated — and gets
            // its own, far more patient budget: retrying an error hard is what
            // cooks the sensor.
            if (result == PamResult.Failed || result == PamResult.MaxTries) {
                root.fingerprintAttempts++;
                root.fingerprintFailed = true;
                fingerprintFailureTimer.restart();
                fingerprintRearmTimer.interval = root.fingerprintRearmDelay;
            } else {
                root.fingerprintErrors++;
                // Back off further with each error rather than at a fixed
                // rate, so a reader that is genuinely unwell is left alone
                // instead of being polled until it gives up.
                fingerprintRearmTimer.interval = root.fingerprintRearmDelay * Math.pow(2, root.fingerprintErrors);
            }

            if (!root.fingerprintExhausted)
                fingerprintRearmTimer.restart();
        }
    }

    // pam_fprintd will not take a new conversation the instant the last one
    // ends; a beat between them is the difference between a working reader and
    // a spin of instant failures.
    readonly property int fingerprintRearmDelay: 400

    Timer {
        id: fingerprintRearmTimer
        interval: root.fingerprintRearmDelay
        onTriggered: root.tryFingerUnlock()
    }

    Timer {
        id: fingerprintFailureTimer
        interval: 2000
        onTriggered: root.fingerprintFailed = false
    }
}
