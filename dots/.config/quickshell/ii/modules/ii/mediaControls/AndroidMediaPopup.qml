pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    required property MprisPlayer player
    property bool showShadow: true
    property list<real> visualizerPoints: []

    readonly property bool playing: player ? player.playbackState === MprisPlaybackState.Playing : false
    // Of `player`, not of whatever is active. They are the same today because the
    // one caller passes the active player, and they stop being the same the moment
    // a second caller does not.
    readonly property string artUrl: MprisController.artUrlFor(player)
    readonly property string trackTitle: StringUtils.cleanMusicTitle(player?.trackTitle) || Translation.tr("No media")
    readonly property string trackArtist: player?.trackArtist || Translation.tr("Unknown Artist")
    readonly property string identity: player ? (player.identity ?? "") : ""

    property bool isLocalArt: artUrl.startsWith("file://")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    readonly property string artSource: {
        if (!artUrl) return "";
        if (isLocalArt) return artUrl;
        return artDownloaded ? Qt.resolvedUrl(artFilePath) : "";
    }

    onArtFilePathChanged: {
        if (!artUrl || artUrl.length === 0) {
            artDownloaded = false;
            return;
        }
        if (isLocalArt) {
            artDownloaded = true;
            return;
        }
        artDownloader.targetFile = artUrl;
        artDownloader.artFilePath = artFilePath;
        artDownloader.artTempPath = artFilePath + ".tmp";
        artDownloaded = false;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: exitCode => {
            artDownloaded = exitCode === 0;
        }
    }

    property string activeLyricText: ""
    property real lyricOpacity: 1.0
    property real lyricYOffset: 0.0

    property string displayArtist: root.trackArtist
    property real titleOpacity: 1.0
    property real titleYOffset: 0.0

    property real artVignetteBlur: root.playing ? 50 : 90

    // No album-derived scheme here. It was gated on
    // `Config.options.media.dynamicAlbumColors`, which is not a member of that
    // JsonObject -- it reads `undefined`, silently -- so the ColorQuantizer
    // rescaled the art to 1x1 and built a whole AdaptedMaterialScheme per track
    // change to feed fourteen ternaries that only ever took their else branch.
    // The controls are on the theme's own container roles, which is what was on
    // screen all along.

    readonly property color artTextColor: Appearance.colors.colOnSurface
    readonly property color artSubtextColor: Appearance.colors.colOnSurfaceVariant

    // A blur radius is an effect, so it settles rather than overshooting (2.1).
    Behavior on artVignetteBlur {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    readonly property string displaySongText: {
        if (LyricsService.hasSyncedLines && LyricsService.statusText !== "") {
            return LyricsService.statusText;
        }
        return root.trackTitle;
    }

    onDisplaySongTextChanged: {
        lyricTransitionAnimation.stop();
        lyricTransitionAnimation.start();
    }

    // The old line leaves before the new one arrives, so it is an exit followed by
    // an enter and takes those two specs rather than one duration used twice
    // (DESIGN.md 2.5). The slide and the fade run together; sequencing them made
    // the line arrive already in place.
    SequentialAnimation {
        id: lyricTransitionAnimation

        NumberAnimation {
            target: root
            property: "lyricOpacity"
            to: 0.0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        PropertyAction {
            target: root
            property: "activeLyricText"
            value: root.displaySongText
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "lyricYOffset"
                from: 16
                to: 0.0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
            NumberAnimation {
                target: root
                property: "lyricOpacity"
                to: 1.0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }
    }

    onTrackTitleChanged: {
        if (displayArtist === "") {
            displayArtist = root.trackArtist;
        }
    }

    Timer {
        running: root.playing && root.visible
        interval: 1000
        repeat: true
        onTriggered: if (root.player) root.player.positionChanged()
    }

    function getBarAmplitude(index) {
        if (!root.playing || root.visualizerPoints.length === 0)
            return 0.0;
        let indices = [2, 5, 9, 14, 20, 26, 32, 38];
        let idx = indices[index] || 0;
        if (idx >= root.visualizerPoints.length) {
            idx = root.visualizerPoints.length - 1;
        }
        let val = root.visualizerPoints[idx] / 1000.0;
        return Math.min(1.0, Math.max(0.0, val * 1.8));
    }

    implicitWidth: 380
    implicitHeight: 220

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
        root.activeLyricText = root.displaySongText;
    }

    Loader {
        active: root.showShadow
        sourceComponent: StyledRectangularShadow {
            target: mainBg
        }
    }

    Rectangle {
        id: mainBg
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.windowRounding
        clip: true

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: mainBg.width
                height: mainBg.height
                radius: mainBg.radius
            }
        }

        Item {
            anchors.fill: parent

            Image {
                id: artBlurredUnderlay
                anchors.fill: parent
                source: root.artSource
                fillMode: Image.PreserveAspectCrop
                visible: root.artSource !== ""
                layer.enabled: root.artVignetteBlur > 0
                layer.effect: MultiEffect {
                    blurEnabled: root.artVignetteBlur > 0
                    blurMax: 128
                    blur: root.artVignetteBlur / 128
                }
            }

            Item {
                id: vignetteMask
                anchors.fill: parent

                RadialGradient {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 1) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
                    }
                    horizontalRadius: width * 0.65
                    verticalRadius: height * 0.65
                }
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: vignetteMask
                }

                Image {
                    id: artExpanded
                    anchors.fill: parent
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0.85
                    visible: root.artSource !== ""
                }
            }
        }

        Item {
            anchors.fill: parent
            opacity: root.playing ? 0.55 : 0.75

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
                    GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.25) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.3)
                opacity: root.playing ? 0.0 : 0.5

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 12
            anchors.bottomMargin: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24

                MaterialShape {
                    implicitWidth: 24
                    implicitHeight: 24
                    shapeString: "Cookie12Sided"
                    color: "transparent"
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop

                    Loader {
                        id: appIconLoader
                        anchors.fill: parent
                        active: root.player && root.player.desktopEntry !== ""
                        sourceComponent: IconImage {
                            implicitSize: Appearance.font.pixelSize.huge
                            source: Quickshell.iconPath(root.player ? root.player.desktopEntry : "audio-x-generic", "audio-x-generic")
                        }
                    }

                    Loader {
                        anchors.fill: parent
                        active: !appIconLoader.active
                        sourceComponent: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "music_note"
                            iconSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }


                RippleButton {
                    id: audioPill
                    implicitHeight: 24
                    leftPadding: 8
                    rightPadding: 8
                    Layout.alignment: Qt.AlignTop
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colOnPrimaryContainer
                    buttonRadius: Appearance.rounding.full

                    readonly property string activeAudioDeviceName: Audio.sink ? (Audio.sink.description || "") : ""
                    readonly property string audioDeviceIcon: {
                        let desc = activeAudioDeviceName.toLowerCase();
                        if (desc.includes("headphone") || desc.includes("headset") || desc.includes("wired")) {
                            return "headphones";
                        }
                        return "volume_up";
                    }

                    onClicked: {
                        GlobalStates.openRightSidebar();
                        Qt.callLater(() => {
                            GlobalStates.requestVolumeDialog = true;
                        });
                    }

                    contentItem: RowLayout {
                        id: audioPillLayout
                        spacing: 4

                        MaterialSymbol {
                            text: audioPill.audioDeviceIcon
                            iconSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            text: audioPill.activeAudioDeviceName !== "" ? audioPill.activeAudioDeviceName : Translation.tr("Audio")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.bold: true
                            color: Appearance.colors.colOnPrimaryContainer
                            Layout.maximumWidth: 100
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Column {
                            id: lyricsContainer
                            width: parent.width
                            spacing: 0
                            y: lyricsContainer.baseY - lyricsContainer.rowHeight - lyricsContainer.scrollOffset
                            visible: LyricsService.hasSyncedLines

                            readonly property int rowHeight: Math.floor(parent.height / 2.5)
                            readonly property real baseY: (parent.height - rowHeight) / 2
                            readonly property int targetCurrentIndex: LyricsService.hasSyncedLines ? LyricsService.currentIndex : -1
                            property int lastIndex: -1
                            property bool isMovingForward: true
                            property real scrollOffset: 0
                            readonly property real animProgress: rowHeight > 0 ? Math.abs(scrollOffset) / rowHeight : 0

                            onTargetCurrentIndexChanged: {
                                if (targetCurrentIndex !== lastIndex && LyricsService.hasSyncedLines) {
                                    isMovingForward = targetCurrentIndex > lastIndex;
                                    lastIndex = targetCurrentIndex;
                                    scrollAnim.stop();
                                    scrollOffset = isMovingForward ? -rowHeight : rowHeight;
                                    scrollAnim.start();
                                }
                            }

                            NumberAnimation {
                                id: scrollAnim
                                target: lyricsContainer
                                property: "scrollOffset"
                                to: 0
                                duration: Appearance.animation.elementMoveEnter.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }

                            Repeater {
                                model: 3

                                Item {
                                    required property int index
                                    property int lineOffset: index - 1
                                    property int actualIndex: lyricsContainer.targetCurrentIndex + lineOffset
                                    property bool isValidLine: LyricsService.hasSyncedLines && actualIndex >= 0 && actualIndex < LyricsService.syncedLines.length

                                    width: parent.width
                                    height: lyricsContainer.rowHeight

                                    property int oldLineOffset: lyricsContainer.isMovingForward ? lineOffset + 1 : lineOffset - 1

                                    function getOpacityForOffset(offset) {
                                        let dist = Math.abs(offset);
                                        if (dist === 0) return 1.0;
                                        if (dist === 1) return 0.35;
                                        return 0.1;
                                    }
                                    property real targetOpacity: getOpacityForOffset(lineOffset)
                                    property real startOpacity: getOpacityForOffset(oldLineOffset)
                                    opacity: startOpacity + (targetOpacity - startOpacity) * (1.0 - lyricsContainer.animProgress)

                                    function getScaleForOffset(offset) {
                                        return Math.abs(offset) === 0 ? 1.0 : 0.9;
                                    }
                                    property real targetScale: getScaleForOffset(lineOffset)
                                    property real startScale: getScaleForOffset(oldLineOffset)
                                    scale: startScale + (targetScale - startScale) * (1.0 - lyricsContainer.animProgress)

                                    transformOrigin: Item.Center

                                    StyledText {
                                        anchors.fill: parent
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: Appearance.font.pixelSize.large
                                        font.weight: Math.abs(lineOffset) === 0 ? Font.Black : Font.Medium
                                        font.styleName: Math.abs(lineOffset) === 0 ? "Rounded" : "Regular"
                                        font.hintingPreference: Font.PreferNoHinting
                                        color: root.artTextColor
                                        text: isValidLine ? LyricsService.syncedLines[actualIndex].text : ""
                                        horizontalAlignment: Text.AlignLeft
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: !LyricsService.hasSyncedLines
                            anchors.fill: parent
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Black
                            font.styleName: "Rounded"
                            color: root.artTextColor
                            text: root.displaySongText
                            maximumLineCount: 3
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.artSubtextColor
                        text: root.displayArtist
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    id: playBtn
                    implicitWidth: 52
                    implicitHeight: 52
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                    onClicked: {
                        if (root.player) {
                            if (root.playing)
                                root.player.pause();
                            else
                                root.player.play();
                        }
                    }

                    contentItem: Item {
                        implicitWidth: 52
                        implicitHeight: 52
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.playing ? "pause" : "play_arrow"
                            iconSize: Appearance.font.pixelSize.hugeass
                            color: Appearance.colors.colOnPrimaryContainer
                            fill: 1
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 12
                Layout.alignment: Qt.AlignBottom

                RippleButton {
                    id: prevBtn
                    // 24px of glyph in a 32px target, which is the pointer minimum
                    // (DESIGN.md 3.4).
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1, 1)
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colPrimaryContainer

                    // Disabled is the control at 0.4, not a dimmed glyph over a
                    // button that still hovers, ripples and fires (DESIGN.md 3.1).
                    enabled: root.player?.canGoPrevious ?? false
                    opacity: enabled ? 1 : 0.4

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    onClicked: {
                        if (root.player)
                            root.player.previous();
                    }

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "skip_previous"
                        iconSize: Appearance.font.pixelSize.normal
                        fill: 1
                        color: Appearance.colors.colOnSurface
                    }
                }

                Item {
                    id: progressArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                    Layout.alignment: Qt.AlignVCenter

                    Loader {
                        id: sliderLoader
                        anchors.fill: parent
                        active: root.player ? (root.player.canSeek ?? false) : false
                        sourceComponent: StyledSlider {
                            configuration: StyledSlider.Configuration.Wavy
                            animateWave: root.playing && root.visible
                            highlightColor: Appearance.colors.colPrimaryContainer
                            trackColor: Appearance.colors.colSecondaryContainer
                            handleColor: Appearance.colors.colPrimaryContainer
                            value: (root.player && root.player.length > 0) ? (root.player.position / root.player.length) : 0
                            onMoved: if (root.player)
                                root.player.position = value * root.player.length
                        }
                    }

                    Loader {
                        id: progressBarLoader
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                        }
                        active: root.player ? !(root.player.canSeek ?? false) : false
                        sourceComponent: StyledProgressBar {
                            wavy: root.player ? root.playing : false
                            animateWave: root.playing && root.visible
                            highlightColor: Appearance.colors.colPrimaryContainer
                            trackColor: Appearance.colors.colSecondaryContainer
                            value: (root.player && root.player.length > 0) ? (root.player.position / root.player.length) : 0
                        }
                    }
                }

                RippleButton {
                    id: nextBtn
                    // 24px of glyph in a 32px target, which is the pointer minimum
                    // (DESIGN.md 3.4).
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1, 1)
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colPrimaryContainer

                    // Disabled is the control at 0.4, not a dimmed glyph over a
                    // button that still hovers, ripples and fires (DESIGN.md 3.1).
                    enabled: root.player?.canGoNext ?? false
                    opacity: enabled ? 1 : 0.4

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    onClicked: {
                        if (root.player)
                            root.player.next();
                    }

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "skip_next"
                        iconSize: Appearance.font.pixelSize.normal
                        fill: 1
                        color: Appearance.colors.colOnSurface
                    }
                }
            }
        }
    }
}
