pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item { // Player instance
    id: root
    required property MprisPlayer player
    property var artUrl: MprisController.artUrlFor(player)
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property color artDominantColor: ColorUtils.mix((colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary), Appearance.colors.colPrimaryContainer, 0.8) || Appearance.m3colors.m3secondaryContainer
    property bool downloaded: false
    property list<real> visualizerPoints: []
    property real maxVisualizerValue: 1000 // Max value in the data points
    property int visualizerSmoothing: 2 // Number of points to average for smoothing
    property real radius

    readonly property real cardPadding: 12
    // The art is a square of whatever height the card's interior has.
    readonly property real artSize: Math.max(0, background.height - cardPadding * 2)

    implicitWidth: Appearance.sizes.mediaControlsWidth
    // Grows with the text instead of clipping it: a bigger UI font pushed the
    // row past a hardcoded 160 and knocked the art off centre.
    implicitHeight: Math.max(Appearance.sizes.mediaControlsHeight, infoColumn.implicitHeight + cardPadding * 2 + Appearance.sizes.elevationMargin * 2)

    property string displayedArtFilePath: root.downloaded ? Qt.resolvedUrl(artFilePath) : ""

    component TrackChangeButton: RippleButton {
        id: button
        property int buttonSize: 24
        property bool fill: true

        implicitWidth: buttonSize
        implicitHeight: buttonSize

        property var iconName
        colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: blendedColors.colSecondaryContainerHover
        colRipple: blendedColors.colSecondaryContainerActive

        contentItem: MaterialSymbol {
            iconSize: buttonSize
            fill: button.fill ? 1 : 0
            horizontalAlignment: Text.AlignHCenter
            color: blendedColors.colSecondary
            text: iconName

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    Timer { // Force update for revision
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: {
            root.player.positionChanged()
        }
    }

    onArtFilePathChanged: {
        if (root.artUrl.length == 0) {
            root.artDominantColor = Appearance.m3colors.m3secondaryContainer
            return;
        }

        // Binding does not work in Process
        coverArtDownloader.targetFile = root.artUrl 
        coverArtDownloader.artFilePath = root.artFilePath
        // Download
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Process { // Cover art downloader
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: [ "bash", "-c", `[ -f ${artFilePath} ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'` ]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0 // 2^0 = 1 color
        rescaleSize: 1 // Rescale to 1x1 pixel for faster processing
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }

    StyledRectangularShadow {
        target: background
    }
    Rectangle { // Background
        id: background
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        color: ColorUtils.applyAlpha(blendedColors.colLayer0, 1)
        radius: root.radius

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: background.width
                height: background.height
                radius: background.radius
            }
        }

        StyledImage {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true

            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(blendedColors.colLayer0, 0.3)
                radius: root.radius
            }
        }

        WaveVisualizer {
            id: visualizerCanvas
            anchors.fill: parent
            live: root.player?.isPlaying
            points: root.visualizerPoints
            maxVisualizerValue: root.maxVisualizerValue
            smoothing: root.visualizerSmoothing
            color: blendedColors.colPrimary
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: root.cardPadding
            spacing: 14

            Rectangle { // Art background
                id: artBackground
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.artSize
                implicitHeight: root.artSize
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize(blendedColors.colLayer1, 0.5)

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: artBackground.width
                        height: artBackground.height
                        radius: artBackground.radius
                    }
                }

                StyledImage { // Art image
                    id: mediaArt
                    anchors.fill: parent
                    source: root.displayedArtFilePath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    antialiasing: true
                    asynchronous: true
                    sourceSize.width: artBackground.width
                    sourceSize.height: artBackground.height
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: mediaArt.status !== Image.Ready
                    text: "music_note"
                    iconSize: artBackground.width * 0.4
                    color: blendedColors.colOnLayer1
                }
            }

            ColumnLayout { // Info & controls
                id: infoColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.rightMargin: 14 // room for the pin button
                spacing: 2

                Item { Layout.fillHeight: true }

                StyledText {
                    id: trackTitle
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: blendedColors.colOnLayer0
                    elide: Text.ElideRight
                    text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("Untitled")
                    animateChange: true
                    animationDistanceX: 6
                    animationDistanceY: 0
                }

                StyledText {
                    id: trackArtist
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: blendedColors.colSubtext
                    elide: Text.ElideRight
                    text: root.player?.trackArtist ?? ""
                    animateChange: true
                    animationDistanceX: 6
                    animationDistanceY: 0
                }

                Item { Layout.fillHeight: true }

                RowLayout { // Seek
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: blendedColors.colSubtext
                        text: StringUtils.friendlyTimeForSeconds(root.player?.position)
                    }

                    Item {
                        id: progressBarContainer
                        Layout.fillWidth: true
                        implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                        Loader {
                            id: sliderLoader
                            anchors.fill: parent
                            active: root.player?.canSeek ?? false
                            sourceComponent: StyledSlider {
                                configuration: StyledSlider.Configuration.Wavy
                                highlightColor: blendedColors.colPrimary
                                trackColor: blendedColors.colSecondaryContainer
                                handleColor: blendedColors.colPrimary
                                value: root.player?.position / root.player?.length
                                onMoved: {
                                    root.player.position = value * root.player.length;
                                }
                            }
                        }

                        Loader {
                            id: progressBarLoader
                            anchors {
                                verticalCenter: parent.verticalCenter
                                left: parent.left
                                right: parent.right
                            }
                            active: !(root.player?.canSeek ?? false)
                            sourceComponent: StyledProgressBar {
                                wavy: root.player?.isPlaying
                                highlightColor: blendedColors.colPrimary
                                trackColor: blendedColors.colSecondaryContainer
                                value: root.player?.position / root.player?.length
                            }
                        }
                    }

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: blendedColors.colSubtext
                        text: StringUtils.friendlyTimeForSeconds(root.player?.length)
                    }
                }

                RowLayout { // Transport
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 16

                    TrackChangeButton {
                        iconName: "skip_previous"
                        buttonSize: 28
                        downAction: () => root.player?.previous()
                    }

                    RippleButton {
                        id: playPauseButton
                        property real size: 40
                        implicitWidth: size
                        implicitHeight: size
                        downAction: () => root.player.togglePlaying()

                        buttonRadius: root.player?.isPlaying ? Appearance?.rounding.normal : size / 2
                        colBackground: root.player?.isPlaying ? blendedColors.colPrimary : blendedColors.colSecondaryContainer
                        colBackgroundHover: root.player?.isPlaying ? blendedColors.colPrimaryHover : blendedColors.colSecondaryContainerHover
                        colRipple: root.player?.isPlaying ? blendedColors.colPrimaryActive : blendedColors.colSecondaryContainerActive

                        contentItem: MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.huge
                            fill: 1
                            horizontalAlignment: Text.AlignHCenter
                            color: root.player?.isPlaying ? blendedColors.colOnPrimary : blendedColors.colOnSecondaryContainer
                            text: root.player?.isPlaying ? "pause" : "play_arrow"

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }

                    TrackChangeButton {
                        iconName: "skip_next"
                        buttonSize: 28
                        downAction: () => root.player?.next()
                    }
                }
            }
        }

        // Out of the centered stack: it picks the active player, it is not transport.
        TrackChangeButton {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            iconName: "keep"
            buttonSize: 18
            fill: MprisController.activePlayer == root.player
            downAction: () => MprisController.setActivePlayer(root.player)
        }
    }
}