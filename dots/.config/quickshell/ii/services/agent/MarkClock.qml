import QtQuick
import QtMultimedia

/**
 * Which word of a read-aloud clip is being said, on time.
 *
 * MediaPlayer reports its position ten times a second (measured: 100 ms apart),
 * so a mark read straight off `position` moved up to 100 ms after its word began
 * -- past the ~45 ms at which a picture running behind its sound is noticed
 * (ITU-R BT.1359). Between reports this times the next mark itself: one
 * single-shot timer, set for when the next word is due.
 *
 * Due by the wall clock, not counted on from the last report: a report arrives
 * a little after the moment it describes, so the clip's start is taken as the
 * earliest one any report implies. Measured against a muted player, the mark
 * moved a median 76 ms after its word read off `position`, 26 ms timed from
 * each report, and 2 ms like this.
 */
QtObject {
    id: root

    property MediaPlayer player: null
    /** [[start_ms, offset], ...] for the clip playing, in order. */
    property var marks: []
    /** The player's position, carried forward to each mark as it falls due. */
    property real position: 0
    // Date.now() at the clip's position 0, or -1 until a report has said.
    property real origin: -1
    // The player's own last report, which only ever moves back on a seek.
    property real reported: 0
    // How often MediaPlayer reports its position, measured (Qt 6, FFmpeg backend).
    readonly property int reportInterval: 100

    /** Where the word being said starts in the clip's text, or -1 without marks. */
    readonly property int offset: {
        const marks = root.marks;
        if (marks.length === 0)
            return -1;
        let offset = marks[0][1];
        for (let i = 0; i < marks.length && marks[i][0] <= root.position; i++)
            offset = marks[i][1];
        return offset;
    }

    /**
     * The clip's position now, to the frame, for something drawn every frame:
     * the wall clock since the clip's start while it plays, `position` when it
     * does not or no report has said yet where the start was.
     */
    function now(): real {
        if (root.origin < 0 || root.player?.playbackState !== MediaPlayer.PlayingState)
            return root.position;
        return Math.max(root.position, Math.min(Date.now() - root.origin, root.player.duration || Infinity));
    }

    /**
     * The player was moved to `position` -- a seek, which may go back, where the
     * position otherwise only moves on. Timed afresh from the next report.
     */
    function jump(position: real): void {
        root.position = position;
        root.reported = position;
        root.origin = -1;
        root.schedule();
    }

    function schedule(): void {
        const next = root.marks.find(mark => mark[0] > root.position);
        if (!next || root.player?.playbackState !== MediaPlayer.PlayingState) {
            clock.stop();
            return;
        }
        clock.due = next[0];
        const now = Date.now();
        clock.interval = Math.max(1, root.origin >= 0 ? root.origin + next[0] - now : next[0] - root.position);
        clock.restart();
    }

    property Timer clock: Timer {
        id: clock
        property real due: 0
        onTriggered: {
            root.position = Math.max(root.position, clock.due);
            root.schedule();
        }
    }

    property Connections reports: Connections {
        target: root.player

        // Never backwards within a clip: a report read just before the timer
        // fired would step the mark back a word and on again. Unless the player
        // itself went back -- a report behind its own last one is a seek.
        function onPositionChanged(): void {
            const position = root.player.position;
            if (position < root.reported) {
                root.position = position;
                root.origin = -1;
            } else {
                root.position = Math.max(root.position, position);
            }
            root.reported = position;
            if (position > 0 && root.player.playbackState === MediaPlayer.PlayingState) {
                // A report more than one report interval later than the clock
                // expects is not delivery delay but a stall: start over from it.
                const origin = Date.now() - position;
                root.origin = root.origin < 0 || origin - root.origin > root.reportInterval ? origin : Math.min(root.origin, origin);
            }
            root.schedule();
        }
        // Stopped or paused, the wall clock no longer says where the clip is.
        function onPlaybackStateChanged(): void {
            root.origin = -1;
            root.schedule();
        }
        // A new clip starts from its own beginning.
        function onSourceChanged(): void {
            root.position = 0;
            root.reported = 0;
            root.origin = -1;
            root.schedule();
        }
    }

    onMarksChanged: root.schedule()
}
