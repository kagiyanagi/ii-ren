pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root

    property bool shown: false
    signal requestClose
    signal closed

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property var players: MprisController.players
    readonly property bool playing: root.player?.isPlaying ?? false

    readonly property var options: Config.options.media.immersive
    readonly property bool lyricsShown: root.options.showLyrics

    // ── Album art ────────────────────────────────────────────────────────────
    readonly property string artUrl: MprisController.artUrlFor(root.player)
    readonly property string artSource: CoverArt.source(root.artUrl)

    // ── Colour scheme ────────────────────────────────────────────────────────
    readonly property bool useDynamicColors: root.options.dynamicAlbumColors && root.artSource !== ""

    ColorQuantizer {
        id: colorQuantizer
        source: root.artSource
        depth: 0
        rescaleSize: 1
    }

    readonly property color artDominantColor: colorQuantizer.colors[0] ?? Appearance.colors.colPrimary
    readonly property QtObject adaptedScheme: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    readonly property QtObject scheme: QtObject {
        // Surfaces and text stay on the neutral semantic layers even with
        // dynamic colours on. Elsewhere an adapted scheme tints a card that
        // sits on the desktop; here the same album colour is already the
        // background, so tinting the card too collapses the contrast between
        // them and drags the body text halfway to the wallpaper. The album
        // hue rides on the accents instead, where it has a neutral card
        // behind it. Cards are layer 1 over layer 0 (DESIGN 6.1), taken from
        // the *Base* colour: colLayer1 carries alpha `1 - contentTransparency`
        // because it is meant to be painted over colLayer0Base, so thinning it
        // again for glass leaves the card at about 7% and invisible.
        readonly property color card: Appearance.colors.colLayer1Base
        readonly property color onSurface: Appearance.colors.colOnLayer0
        readonly property color subtext: Appearance.colors.colSubtext
        readonly property color accent: root.useDynamicColors ? root.adaptedScheme.colPrimary : Appearance.colors.colPrimary
        readonly property color accentHover: root.useDynamicColors ? root.adaptedScheme.colPrimaryHover : Appearance.colors.colPrimaryHover
        readonly property color accentActive: root.useDynamicColors ? root.adaptedScheme.colPrimaryActive : Appearance.colors.colPrimaryActive
        readonly property color onAccent: root.useDynamicColors ? root.adaptedScheme.colOnPrimary : Appearance.colors.colOnPrimary
        readonly property color container: root.useDynamicColors ? root.adaptedScheme.colSecondaryContainer : Appearance.colors.colSecondaryContainer
        readonly property color containerHover: root.useDynamicColors ? root.adaptedScheme.colSecondaryContainerHover : Appearance.colors.colSecondaryContainerHover
        readonly property color containerActive: root.useDynamicColors ? root.adaptedScheme.colSecondaryContainerActive : Appearance.colors.colSecondaryContainerActive
        readonly property color onContainer: root.useDynamicColors ? root.adaptedScheme.colOnSecondaryContainer : Appearance.colors.colOnSecondaryContainer
    }

    // MPRIS only pushes position on seek, so the sliders and lyrics need a tick.
    Timer {
        running: root.playing && root.shown
        interval: 500
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    // QML applies the initial state without running its transition, and `shown`
    // is already true when the window is constructed. Completing in the hidden
    // state and flipping this on the next tick is what makes the enter
    // animation actually play instead of snapping in.
    property bool entered: false

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
        root.entered = true;
    }

    // ── Keyboard ─────────────────────────────────────────────────────────────
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.requestClose();
            event.accepted = true;
        } else if (event.key === Qt.Key_Space) {
            MprisController.togglePlaying();
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            MprisController.next();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            MprisController.previous();
            event.accepted = true;
        } else if (event.key === Qt.Key_L) {
            Config.options.media.immersive.showLyrics = !root.lyricsShown;
            event.accepted = true;
        }
    }

    // ── Enter/exit (DESIGN 2.5, 2.6) ─────────────────────────────────────────
    states: [
        State {
            name: "shown"
            when: root.shown && root.entered
            PropertyChanges {
                contentRoot.opacity: 1
                contentRoot.contentScale: 1
            }
        },
        State {
            name: "hidden"
            when: !(root.shown && root.entered)
            PropertyChanges {
                contentRoot.opacity: 0
                contentRoot.contentScale: 0.94
            }
        }
    ]
    transitions: [
        Transition {
            to: "shown"
            // Scale is spatial and may overshoot, opacity is effects and may not,
            // so they run on their own specs at their own durations (DESIGN 2.1).
            // One NumberAnimation over both put the fade on a 500ms spatial curve.
            NumberAnimation {
                property: "contentScale"
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            NumberAnimation {
                property: "opacity"
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        },
        Transition {
            to: "hidden"
            // `elementMoveExit` is the fast-effects exit spec (DESIGN 2.5); this
            // used to hand-compute half the enter duration and pick a curve next
            // to the token that already names both.
            SequentialAnimation {
                NumberAnimation {
                    properties: "opacity,contentScale"
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                }
                ScriptAction {
                    script: if (!root.shown && root.entered) root.closed()
                }
            }
        }
    ]

    Item {
        id: contentRoot
        anchors.fill: parent

        property real contentScale: 0.94
        opacity: 0
        scale: contentRoot.contentScale
        // A fullscreen surface has no anchor to grow out of, so it grows from
        // its own centre (DESIGN 2.6).
        transformOrigin: Item.Center

        // ── Background ───────────────────────────────────────────────────────
        // Opaque base first: this is an immersive surface, not a scrim over
        // the desktop, and the art wash below needs something to sit on.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0Base
        }

        StyledImage {
            id: backgroundArt
            anchors.fill: parent
            visible: root.options.blurredArtBackground && root.artSource !== ""
            source: root.artSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: Math.round(root.width / 4)
            sourceSize.height: Math.round(root.height / 4)

            layer.enabled: backgroundArt.visible
            layer.effect: StyledBlurEffect {
                source: backgroundArt
            }
        }

        // Keeps the cards and their text legible over any album art.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colScrim
        }

        // Click-away dismiss, behind everything the user can actually press.
        MouseArea {
            anchors.fill: parent
            onClicked: root.requestClose()
        }

        // ── Foreground ───────────────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16

            ImmersiveMediaToolbar {
                Layout.fillWidth: true
                scheme: root.scheme
                player: root.player
                players: root.players
                lyricsShown: root.lyricsShown
                onToggleLyrics: Config.options.media.immersive.showLyrics = !root.lyricsShown
                onRequestClose: root.requestClose()
            }

            RowLayout {
                id: mediaRow
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                Item {
                    Layout.fillWidth: true
                    visible: !root.lyricsShown
                }

                ImmersiveNowPlayingPane {
                    id: nowPlaying
                    Layout.fillHeight: true
                    // As wide as the album art can be tall, because the art is
                    // square: a fixed width left ~180px of void above and below
                    // it on a 16:9 screen while the lyrics pane took 68% of the
                    // screen to centre a 350px line in it. The cap is what stops
                    // a tall screen from doing the same thing in reverse.
                    Layout.preferredWidth: Math.min(mediaRow.height - nowPlaying.chromeHeight + 32, root.width * (root.lyricsShown ? 0.45 : 0.6))
                    scheme: root.scheme
                    player: root.player
                    artSource: root.artSource
                }

                ImmersiveLyricsPane {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.lyricsShown
                    scheme: root.scheme
                }

                Item {
                    Layout.fillWidth: true
                    visible: !root.lyricsShown
                }
            }
        }
    }
}
