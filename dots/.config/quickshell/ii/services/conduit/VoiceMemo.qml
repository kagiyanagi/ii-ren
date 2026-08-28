pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia

/**
 * A voice memo bubble: play/pause, a scrubbable waveform, elapsed time, size and
 * a speed cycle — the messaging-app player, because that is the shape everyone
 * already knows how to use.
 *
 * The waveform is the real peak envelope of the audio (see waveform.py), not a
 * decoration: pauses between sentences are visible, which is what makes dragging
 * to "just before that bit" work at all.
 */
Rectangle {
    id: root

    required property int messageId
    required property string path
    required property int bytes
    required property var bars

    /*
     * Autoplay is a claim taken from the service by *calling* this, and only by a
     * memo that is actually on screen.
     *
     * Deliberately a call and not a bound flag. The shell can leave older copies
     * of a page alive — its contentChildren binding builds new pages and never
     * destroys the ones it replaces — and a detached copy renders this same
     * message with working audio, so every copy played at once and it was heard as
     * an echo. Excluding them needs the claim consumed the instant it is taken,
     * and a bound flag cannot do that: writing the property the flag is bound to
     * is a binding loop, which QML then re-evaluates forever, autostarting the
     * memo again on every flap.
     *
     * () -> number: where to start from in ms, or -1 if this memo may not start. A
     * non-zero offset means it is taking over from playback already in progress
     * outside the panel.
     */
    property var claimAutoPlay: null
    readonly property bool attached: Window.window !== null
    // Which memo owns the speakers. Only one may play: two replies talking over
    // each other is noise, not two answers.
    property int activeId: -1
    signal claimed(int messageId)

    readonly property real barWidth: 3
    readonly property real barGap: 2
    readonly property real durationMs: player.duration
    readonly property real progress: root.durationMs > 0 ? Math.min(1, player.position / root.durationMs) : 0

    implicitHeight: layout.implicitHeight + 16
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2

    function clock(ms) {
        const total = Math.max(0, Math.round(ms / 1000));
        return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
    }

    function seekTo(fraction) {
        if (root.durationMs <= 0) return;
        player.setPosition(Math.max(0, Math.min(1, fraction)) * root.durationMs);
    }

    function autoStart() {
        if (!root.attached) return;
        /*
         * Waiting for the media, not just for a path: play() against a source that
         * is not loaded can be dropped, and a player that took the claim and then
         * stayed silent has spent it for good.
         *
         * Read here rather than through a bound property. play() moves the status
         * itself, so a property deriving from it is a binding loop.
         */
        if (player.mediaStatus !== MediaPlayer.LoadedMedia
            && player.mediaStatus !== MediaPlayer.BufferedMedia) return;
        if (!root.claimAutoPlay) return;
        const from = root.claimAutoPlay();
        if (from < 0) return;
        // play() stops whatever was playing it before this, so seek first.
        if (from > 0) player.setPosition(from);
        root.play();
        console.log(`[Conduit] Playing the memo for message ${root.messageId}${from > 0 ? ` from ${Math.round(from / 1000)}s` : ""}.`);
    }

    // Several triggers on purpose: the claim makes autoStart idempotent, and none of
    // these is reliably last. The window is not always resolved when the delegate
    // completes, and it flaps during layout.
    onPathChanged: root.autoStart()
    onAttachedChanged: root.autoStart()
    Component.onCompleted: root.autoStart()

    function play() {
        root.claimed(root.messageId);
        player.play();
    }

    // Another memo took over, so this one steps back rather than talking over it.
    onActiveIdChanged: if (root.activeId !== root.messageId && player.playing) player.pause()

    MediaPlayer {
        id: player
        source: root.path.length > 0 ? `file://${root.path}` : ""
        audioOutput: AudioOutput {}

        onMediaStatusChanged: root.autoStart()

        // Otherwise a memo that will never play is completely silent about it.
        onErrorOccurred: (error, errorString) => console.log(`[Conduit] Memo ${root.messageId} will not play: ${errorString} (${player.source})`)
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 8
        spacing: 10

        Rectangle { // Play / pause
            implicitWidth: 40
            implicitHeight: 40
            radius: width / 2
            color: playArea.pressed ? Appearance.colors.colPrimaryActive
                : playArea.containsMouse ? Appearance.colors.colPrimaryHover
                : Appearance.colors.colPrimary

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 24
                fill: 1
                text: player.playing ? "pause" : "play_arrow"
                color: Appearance.m3colors.m3onPrimary
            }

            MouseArea {
                id: playArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (player.playing) {
                        player.pause();
                    } else {
                        // Restarts from the top once it has run out, which is what a
                        // second press on a finished memo is always meant to do.
                        if (root.progress >= 0.999) player.setPosition(0);
                        root.play();
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Item { // Waveform
                id: waveArea
                Layout.fillWidth: true
                implicitHeight: 26

                // However many bars fit, resampled from the envelope — the strip has to
                // survive a narrow sidebar without clipping or squashing the bars.
                readonly property int count: Math.max(8, Math.floor((width + root.barGap) / (root.barWidth + root.barGap)))
                readonly property var shown: {
                    const source = root.bars ?? [];
                    if (source.length === 0) return [];
                    return Array.from({ length: waveArea.count }, (_, i) => source[Math.floor(i * source.length / waveArea.count)]);
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    height: waveArea.implicitHeight
                    spacing: root.barGap

                    Repeater {
                        model: waveArea.shown

                        delegate: Rectangle {
                            required property real modelData
                            required property int index

                            width: root.barWidth
                            height: Math.max(root.barWidth, modelData * waveArea.implicitHeight)
                            radius: width / 2
                            // y, not an anchor: Row refuses anchored children.
                            y: (waveArea.implicitHeight - height) / 2
                            color: (index + 1) / waveArea.count <= root.progress
                                ? Appearance.colors.colPrimary
                                : ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.65)

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }

                MouseArea { // Scrub — click anywhere, or drag along the strip
                    anchors.fill: parent
                    anchors.topMargin: -6 // The bars are thin; the hit area should not be
                    anchors.bottomMargin: -6
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: mouse => root.seekTo(mouse.x / width)
                    onPositionChanged: mouse => { if (pressed) root.seekTo(mouse.x / width); }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText { // Elapsed while playing, total when idle — as in Telegram
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: `${root.clock(player.position > 0 ? player.position : root.durationMs)}, ${(root.bytes / 1024).toFixed(1)} KB`
                }

                Item { Layout.fillWidth: true }

                Rectangle { // Speed
                    implicitWidth: speedText.implicitWidth + 12
                    implicitHeight: 20
                    radius: height / 2
                    color: speedArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1

                    StyledText {
                        id: speedText
                        anchors.centerIn: parent
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                        text: `${player.playbackRate}×`
                    }

                    MouseArea {
                        id: speedArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        readonly property var rates: [1, 1.5, 2, 0.75]
                        onClicked: {
                            const next = (rates.indexOf(player.playbackRate) + 1) % rates.length;
                            player.playbackRate = rates[next < 0 ? 0 : next];
                        }

                        // A tooltip parented to a plain Rectangle is visible forever:
                        // StyledToolTip reads `parent.hovered`, which does not exist there.
                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: speedArea.containsMouse
                            text: "Playback speed"
                        }
                    }
                }
            }
        }
    }
}
