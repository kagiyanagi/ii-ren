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
import Quickshell.Io
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

    // DESIGN 2.5: a screen-sized surface enters on the default spatial duration
    // and leaves at about half of it. Both land on the MotionTokens.kt ladder.
    readonly property int enterDuration: Appearance.animation.elementMoveEnter.duration
    readonly property int exitDuration: Math.round(root.enterDuration / 2)

    // ── Album art ────────────────────────────────────────────────────────────
    readonly property string artUrl: MprisController.artUrlFor(root.player)
    readonly property bool isLocalArt: root.artUrl.startsWith("file://")
    readonly property string artFilePath: `${Directories.coverArt}/${Qt.md5(root.artUrl)}`
    property bool artDownloaded: false
    readonly property string artSource: {
        if (!root.artUrl)
            return "";
        if (root.isLocalArt)
            return root.artUrl;
        return root.artDownloaded ? Qt.resolvedUrl(root.artFilePath) : "";
    }

    onArtFilePathChanged: {
        if (!root.artUrl) {
            root.artDownloaded = false;
            return;
        }
        if (root.isLocalArt) {
            root.artDownloaded = true;
            return;
        }
        root.artDownloaded = false;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        command: ["bash", "-c", `[ -f '${root.artFilePath}' ] || (curl -4 -sSL '${root.artUrl}' -o '${root.artFilePath}.tmp' && mv '${root.artFilePath}.tmp' '${root.artFilePath}')`]
        onExited: root.artDownloaded = true
    }

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
            NumberAnimation {
                properties: "opacity,contentScale"
                duration: root.enterDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        },
        Transition {
            to: "hidden"
            SequentialAnimation {
                NumberAnimation {
                    properties: "opacity,contentScale"
                    duration: root.exitDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
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
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                Item {
                    Layout.fillWidth: true
                    visible: !root.lyricsShown
                }

                ImmersiveNowPlayingPane {
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.lyricsShown ? Math.min(540, root.width * 0.36) : Math.min(620, root.width * 0.6)
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
