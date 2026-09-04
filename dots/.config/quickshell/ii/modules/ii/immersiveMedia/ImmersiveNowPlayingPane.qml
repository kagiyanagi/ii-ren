pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Mpris

Rectangle {
    id: root

    required property QtObject scheme
    required property MprisPlayer player
    required property string artSource

    readonly property bool playing: root.player?.isPlaying ?? false
    readonly property real length: root.player?.length ?? 0

    // How far the glass controls and tracks are thinned against the card.
    readonly property real glassAlpha: 0.35

    radius: Appearance.rounding.verylarge
    color: ColorUtils.transparentize(root.scheme.card, 1 - Config.options.media.immersive.surfaceOpacityPercentage / 100)

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    // The panel dismisses on a click outside the cards; the card itself is not
    // outside, so it has to take the press rather than let it fall through.
    MouseArea {
        anchors.fill: parent
    }

    // Circular transport button. Sized square so the hit area is the visual.
    component TransportButton: RippleButton {
        id: transportButton
        property string iconName
        property real size: 48
        property bool accented: false

        implicitWidth: transportButton.size
        implicitHeight: transportButton.size
        buttonRadius: Appearance.rounding.full
        // The unaccented buttons are glass: hover and pressed keep the same
        // alpha so what reads is the M3 state layer, not a jump to a solid fill.
        colBackground: transportButton.accented ? root.scheme.accent : ColorUtils.transparentize(root.scheme.container, root.glassAlpha)
        colBackgroundHover: transportButton.accented ? root.scheme.accentHover : ColorUtils.transparentize(root.scheme.containerHover, root.glassAlpha)
        colBackgroundActive: transportButton.accented ? root.scheme.accentActive : ColorUtils.transparentize(root.scheme.containerActive, root.glassAlpha)
        colRipple: transportButton.accented ? root.scheme.accentActive : ColorUtils.transparentize(root.scheme.containerActive, root.glassAlpha)
        colBackgroundToggled: root.scheme.accent
        colBackgroundToggledHover: root.scheme.accentHover
        colRippleToggled: root.scheme.accentActive

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.huge
            fill: (transportButton.accented || transportButton.toggled) ? 1 : 0
            text: transportButton.iconName
            color: (transportButton.accented || transportButton.toggled) ? root.scheme.onAccent : root.scheme.onContainer

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on fill {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // ── Album art ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 160

            ClippingRectangle {
                id: artFrame
                anchors.centerIn: parent
                readonly property real side: Math.min(parent.width, parent.height)
                implicitWidth: artFrame.side
                implicitHeight: artFrame.side
                radius: Appearance.rounding.large
                color: ColorUtils.transparentize(root.scheme.container, 0.5)

                StyledImage {
                    anchors.fill: parent
                    visible: root.artSource !== ""
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: Math.round(artFrame.side)
                    sourceSize.height: Math.round(artFrame.side)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.artSource === ""
                    text: "music_note"
                    iconSize: Math.round(artFrame.side / 3)
                    color: root.scheme.subtext
                }
            }
        }

        // ── Track info ───────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Pill {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: root.width - 32
                visible: (root.player?.trackAlbum ?? "") !== ""
                implicitWidth: albumRow.implicitWidth + 24
                implicitHeight: 24
                color: ColorUtils.transparentize(root.scheme.container, root.glassAlpha)

                RowLayout {
                    id: albumRow
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 12
                    spacing: 4

                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.smallie
                        fill: 1
                        text: "album"
                        color: root.scheme.onContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.player?.trackAlbum ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.scheme.onContainer
                        elide: Text.ElideRight
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignHCenter
                text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("Nothing playing")
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.hugeass
                font.variableAxes: Appearance.font.variableAxes.title
                color: root.scheme.onSurface
                elide: Text.ElideRight
                animateChange: true
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.player?.trackArtist || Translation.tr("Unknown Artist")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: root.scheme.subtext
                elide: Text.ElideRight
                animateChange: true
            }
        }

        // ── Seek ─────────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(seekSlider.implicitHeight, seekProgress.implicitHeight)

                StyledSlider {
                    id: seekSlider
                    anchors.fill: parent
                    visible: root.player?.canSeek ?? false
                    configuration: StyledSlider.Configuration.Wavy
                    animateWave: root.playing
                    usePercentTooltip: false
                    tooltipContent: StringUtils.friendlyTimeForSeconds(value * root.length)
                    highlightColor: root.scheme.accent
                    trackColor: ColorUtils.transparentize(root.scheme.container, root.glassAlpha)
                    handleColor: root.scheme.accent
                    value: root.length > 0 ? (root.player?.position ?? 0) / root.length : 0
                    onMoved: {
                        if (root.player)
                            root.player.position = value * root.length;
                    }
                }

                StyledProgressBar {
                    id: seekProgress
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: !(root.player?.canSeek ?? false)
                    wavy: root.playing
                    highlightColor: root.scheme.accent
                    trackColor: ColorUtils.transparentize(root.scheme.container, root.glassAlpha)
                    value: root.length > 0 ? (root.player?.position ?? 0) / root.length : 0
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(root.player?.position ?? 0)
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.features: ({
                            "tnum": 1
                        })
                    color: root.scheme.subtext
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(root.length)
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.features: ({
                            "tnum": 1
                        })
                    color: root.scheme.subtext
                }
            }
        }

        // ── Transport ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            Item {
                Layout.fillWidth: true
            }

            TransportButton {
                iconName: "shuffle"
                enabled: MprisController.shuffleSupported
                toggled: MprisController.hasShuffle
                onClicked: MprisController.setShuffle(!MprisController.hasShuffle)

                StyledToolTip {
                    text: Translation.tr("Shuffle")
                }
            }

            TransportButton {
                iconName: "skip_previous"
                enabled: MprisController.canGoPrevious
                onClicked: MprisController.previous()
            }

            TransportButton {
                id: playPauseButton
                iconName: root.playing ? "pause" : "play_arrow"
                accented: true
                size: 64
                // M3 Expressive marks the active state with a shape change; the
                // resting circle morphs to a squircle while playing.
                buttonRadius: root.playing ? Appearance.rounding.large : Appearance.rounding.full
                enabled: MprisController.canTogglePlaying
                onClicked: MprisController.togglePlaying()
            }

            TransportButton {
                iconName: "skip_next"
                enabled: MprisController.canGoNext
                onClicked: MprisController.next()
            }

            TransportButton {
                id: loopButton
                readonly property var loopState: MprisController.loopState
                iconName: loopButton.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                enabled: MprisController.loopSupported
                toggled: loopButton.loopState !== MprisLoopState.None
                onClicked: {
                    if (loopButton.loopState === MprisLoopState.None)
                        MprisController.setLoopState(MprisLoopState.Playlist);
                    else if (loopButton.loopState === MprisLoopState.Playlist)
                        MprisController.setLoopState(MprisLoopState.Track);
                    else
                        MprisController.setLoopState(MprisLoopState.None);
                }

                StyledToolTip {
                    text: {
                        if (loopButton.loopState === MprisLoopState.Track)
                            return Translation.tr("Repeat track");
                        if (loopButton.loopState === MprisLoopState.Playlist)
                            return Translation.tr("Repeat playlist");
                        return Translation.tr("Repeat off");
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        // ── Player volume ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: MprisController.canChangeVolume
            spacing: 12

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                fill: 1
                text: (root.player?.volume ?? 0) <= 0 ? "volume_off" : "volume_up"
                color: root.scheme.subtext
            }

            StyledSlider {
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.XS
                highlightColor: root.scheme.accent
                trackColor: ColorUtils.transparentize(root.scheme.container, root.glassAlpha)
                handleColor: root.scheme.accent
                value: root.player?.volume ?? 0
                onMoved: {
                    if (root.player)
                        root.player.volume = value;
                }
            }
        }
    }
}
