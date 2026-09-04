pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Fingerprint reader bridge, backed by fprintd.
 *
 * `scripts/fingerprint/fprintd_bridge.py` holds the D-Bus connection and
 * prints one JSON event per line; commands go back down its stdin. It has to
 * be one long-lived process because fprintd ties Claim() to the connection
 * that made it — see the script's docstring.
 *
 * This only manages the prints. Actually unlocking with one is PAM's job, via
 * `modules/common/panels/lock/pam/fprintd.conf`; the two never touch the
 * reader at the same time because the bridge claims it only while enrolling,
 * verifying or deleting, and the lock screen is not a place you can enroll.
 */
Singleton {
    id: root

    readonly property string bridgePath: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/fingerprint/fprintd_bridge.py"))

    // fprintd is optional. Without it nothing here is spawned, and the
    // settings page says so instead of showing an empty list.
    property bool installed: false
    // False until the first device report lands, so "no reader" and "haven't
    // looked yet" can be told apart on screen.
    property bool probed: false
    property bool deviceAvailable: false
    property string deviceName: ""
    property string scanType: "press"
    readonly property bool pressType: root.scanType !== "swipe"
    property int numEnrollStages: 5

    property list<string> enrolled: []
    property bool enrolledLoaded: false
    readonly property bool hasEnrolled: root.enrolled.length > 0
    property string lastError: ""

    // "" | "authorizing" | "scanning" | "done" | "failed"
    property string enrollPhase: ""
    property int enrollStage: 0
    property string enrollMessage: ""
    readonly property bool enrollActive: root.enrollPhase === "authorizing" || root.enrollPhase === "scanning"

    property string verifyFinger: ""
    property string verifyPhase: ""
    // "" | "match" | "no-match" | "error"
    property string verifyResult: ""
    property string verifyMessage: ""
    readonly property bool verifyActive: root.verifyPhase === "authorizing" || root.verifyPhase === "scanning"

    readonly property bool busy: root.enrollActive || root.verifyActive

    // Live sensor state, followed even while something else (pam_fprintd on
    // the lock screen) owns the reader. Best-effort: a driver is free to never
    // drive either, in which case both stay false and callers just get no
    // extra feedback rather than wrong feedback.
    property bool fingerNeeded: false
    property bool fingerPresent: false

    readonly property var fingerOrder: ["right-thumb", "right-index-finger", "right-middle-finger", "right-ring-finger", "right-little-finger", "left-thumb", "left-index-finger", "left-middle-finger", "left-ring-finger", "left-little-finger"]

    // ── Labels ────────────────────────────────────────────────────────────
    // fprintd stores a finger slot, not a name, so a custom label lives in the
    // shell's own config keyed by that slot.

    function defaultLabelFor(finger: string): string {
        const hand = finger.startsWith("left-") ? Translation.tr("Left") : Translation.tr("Right");
        const digit = finger.replace(/^(left|right)-/, "").replace(/-finger$/, "");
        const names = {
            "thumb": Translation.tr("thumb"),
            "index": Translation.tr("index finger"),
            "middle": Translation.tr("middle finger"),
            "ring": Translation.tr("ring finger"),
            "little": Translation.tr("little finger")
        };
        return `${hand} ${names[digit] ?? digit}`;
    }

    function customLabelFor(finger: string): string {
        return (labelsAdapter.labels ?? {})[finger] ?? "";
    }

    function labelFor(finger: string): string {
        const custom = root.customLabelFor(finger);
        return custom !== "" ? custom : root.defaultLabelFor(finger);
    }

    function setLabel(finger: string, label: string): void {
        // JsonAdapter only notices a whole new value, so the map is rebuilt
        // rather than mutated in place.
        const labels = Object.assign({}, labelsAdapter.labels ?? {});
        const trimmed = (label ?? "").trim();
        if (trimmed === "")
            delete labels[finger];
        else
            labels[finger] = trimmed;
        labelsAdapter.labels = labels;
        labelsFileView.writeAdapter();
    }

    // ── Commands ──────────────────────────────────────────────────────────

    function send(command: var): void {
        if (!bridgeProc.running) {
            // Nothing to write to yet: start the bridge and let it replay the
            // command once its stdin exists.
            root.pendingCommands.push(command);
            bridgeProc.running = true;
            return;
        }
        bridgeProc.write(JSON.stringify(command) + "\n");
    }

    property var pendingCommands: []

    function refresh(): void {
        root.lastError = "";
        root.send({
            cmd: "refresh"
        });
    }

    function startEnroll(finger: string): void {
        if (finger === "")
            return;
        root.lastError = "";
        root.enrollPhase = "authorizing";
        root.enrollStage = 0;
        root.enrollMessage = "";
        root.send({
            cmd: "enroll",
            finger: finger
        });
    }

    function cancelEnroll(): void {
        root.send({
            cmd: "cancel"
        });
        root.enrollPhase = "";
    }

    function resetEnrollState(): void {
        root.enrollPhase = "";
        root.enrollStage = 0;
        root.enrollMessage = "";
    }

    function startVerify(finger: string): void {
        if (finger === "")
            return;
        root.lastError = "";
        root.verifyFinger = finger;
        root.verifyPhase = "authorizing";
        root.verifyResult = "";
        root.verifyMessage = "";
        root.send({
            cmd: "verify",
            finger: finger
        });
    }

    /**
     * Drop any claim this process holds on the reader.
     *
     * fprintd ties a claim to the D-Bus connection that made it and does not
     * notice a client simply losing interest, so a settings page torn down
     * mid-enroll keeps the sensor — and with it pam_fprintd on the lock
     * screen — busy until fprintd is restarted. Nothing sends this from the
     * bridge's side, so the page has to say when it is done.
     */
    function releaseReader(): void {
        // Spawning the bridge purely to tell it to stop doing nothing would be
        // silly, and a bridge that is not running holds no claim anyway.
        if (!bridgeProc.running)
            return;
        root.send({
            cmd: "cancel"
        });
        root.resetEnrollState();
        root.verifyPhase = "";
        root.verifyResult = "";
        root.verifyMessage = "";
    }

    function cancelVerify(): void {
        root.send({
            cmd: "cancel"
        });
        root.verifyPhase = "";
        root.verifyResult = "";
        root.verifyMessage = "";
    }

    function deletePrint(finger: string): void {
        root.lastError = "";
        // Drop the label with the print, so re-enrolling that slot later does
        // not inherit a name from a fingerprint that is gone.
        root.setLabel(finger, "");
        root.send({
            cmd: "delete",
            finger: finger
        });
    }

    function deleteAll(): void {
        root.lastError = "";
        labelsAdapter.labels = ({});
        labelsFileView.writeAdapter();
        root.send({
            cmd: "delete-all"
        });
    }

    FileView {
        id: labelsFileView
        path: Directories.fingerprintLabelsPath
        // Absent until the first custom name is set, which is not an error —
        // and not a reason to create it either. writeAdapter() in setLabel()
        // makes the file when there is finally something to put in it.
        printErrors: false
        watchChanges: true
        onFileChanged: reload()

        adapter: JsonAdapter {
            id: labelsAdapter
            property var labels: ({})
        }
    }

    // ── Bridge ────────────────────────────────────────────────────────────

    Process {
        id: installCheckProc
        running: true
        command: ["bash", "-c", "busctl --system list --no-legend | grep -q net.reactivated.Fprint"]
        onExited: exitCode => {
            root.installed = (exitCode === 0);
            if (!root.installed) {
                root.probed = true;
                root.enrolledLoaded = true;
            }
        }
    }

    Process {
        id: bridgeProc
        running: false
        stdinEnabled: true
        command: ["python3", root.bridgePath]

        onRunningChanged: {
            if (!bridgeProc.running)
                return;
            const queued = root.pendingCommands;
            root.pendingCommands = [];
            queued.forEach(command => bridgeProc.write(JSON.stringify(command) + "\n"));
        }

        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "")
                    return;
                try {
                    root.handleEvent(JSON.parse(line));
                } catch (e) {
                    console.warn("[Fingerprint] Bad event:", line, e);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("[Fingerprint] Bridge exited with", exitCode);
            // An operation cannot survive the process that was running it.
            if (root.enrollActive)
                root.enrollPhase = "failed";
            if (root.verifyActive) {
                root.verifyPhase = "done";
                root.verifyResult = "error";
            }
            // Nothing is watching the sensor any more, so stop claiming to
            // know what it is doing.
            root.fingerNeeded = false;
            root.fingerPresent = false;
        }
    }

    function handleEvent(event: var): void {
        if (event.type === "device") {
            root.probed = true;
            root.deviceAvailable = event.available ?? false;
            root.deviceName = event.name ?? "";
            root.scanType = event.scanType ?? "press";
            root.numEnrollStages = Math.max(1, event.numEnrollStages ?? 5);
        } else if (event.type === "enrolled") {
            root.enrolled = (event.fingers ?? []).slice().sort((a, b) => root.fingerOrder.indexOf(a) - root.fingerOrder.indexOf(b));
            root.enrolledLoaded = true;
        } else if (event.type === "enroll") {
            root.enrollPhase = event.phase ?? "";
            root.enrollStage = event.stage ?? 0;
            root.enrollMessage = event.message ?? "";
        } else if (event.type === "verify") {
            root.verifyFinger = event.finger ?? root.verifyFinger;
            root.verifyPhase = event.phase ?? "";
            root.verifyResult = event.result ?? "";
            root.verifyMessage = event.message ?? "";
            if (root.verifyPhase === "done")
                verifyResultClearTimer.restart();
        } else if (event.type === "reader") {
            root.fingerNeeded = event.fingerNeeded ?? false;
            root.fingerPresent = event.fingerPresent ?? false;
        } else if (event.type === "error") {
            root.lastError = event.message ?? "";
        }
    }

    // The per-print result badge is feedback on a tap, not state — leave it up
    // long enough to read, then hand the row back to its normal label.
    Timer {
        id: verifyResultClearTimer
        interval: 3000
        onTriggered: {
            root.verifyResult = "";
            root.verifyPhase = "";
            root.verifyMessage = "";
        }
    }

    // Nothing has asked for the reader yet, but the lock screen still needs to
    // know whether any print exists before the first lock.
    //
    // Gated on the option because probing D-Bus activates fprintd, and someone
    // who turned fingerprint unlock off should not get a system daemon woken
    // on every shell start. Opening the settings page calls refresh() directly,
    // so the reader is still visible there while the option is off — otherwise
    // there would be no way to enrol a print before enabling it.
    onInstalledChanged: {
        if (root.installed && Config.options.lock.security.fingerprint.enable)
            root.refresh();
    }
}
