pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.ii.mediaControls
import "./widgets"

Item {
    id: root

    property bool isVertical: false

    readonly property real buttonSize: Appearance.sizes.dockButtonSize
    readonly property real dotMargin: (Config.options?.dock.height ?? 60) * 0.2
    readonly property real slotSize: buttonSize + dotMargin * 2
    readonly property real cardHeight: slotSize - Appearance.sizes.hyprlandGapsOut * 2
    property real cardWidth: 240
    readonly property real artSize: Math.round(cardHeight * 0.72)

    implicitWidth: isVertical ? slotSize : cardWidth
    implicitHeight: isVertical ? buttonSize + dotMargin * 1.3 : slotSize

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property string trackTitle: StringUtils.cleanMusicTitle(player?.trackTitle) || Translation.tr("Unknown Title")
    readonly property string trackArtist: player?.trackArtist || Translation.tr("Unknown Artist")
    readonly property string artUrl: MprisController.artUrlFor(player)

    // ColorQuantizer and the blur need a local file, so remote art gets cached first.
    readonly property bool isLocalArt: artUrl.startsWith("file://")
    readonly property string artFilePath: `${Directories.coverArt}/${Qt.md5(artUrl)}`
    property bool artDownloaded: false
    readonly property string artSource: {
        if (!artUrl) return "";
        if (isLocalArt) return artUrl;
        return artDownloaded ? Qt.resolvedUrl(artFilePath) : "";
    }

    onArtFilePathChanged: {
        if (!artUrl || isLocalArt) {
            artDownloaded = isLocalArt;
            return;
        }
        artDownloaded = false;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        command: ["bash", "-c", `[ -f '${root.artFilePath}' ] || (curl -4 -sSL '${root.artUrl}' -o '${root.artFilePath}.tmp' && mv '${root.artFilePath}.tmp' '${root.artFilePath}')`]
        onExited: root.artDownloaded = true
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.artSource
        depth: 0
        rescaleSize: 1
    }

    property color artDominantColor: ColorUtils.mix(colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.8)
    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    property bool mediaHovered: false

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton
        onEntered: root.mediaHovered = true
        onExited: root.mediaHovered = false
        onClicked: mouse => {
            if (mouse.button === Qt.BackButton) root.player?.previous();
            else if (mouse.button === Qt.ForwardButton) root.player?.next();
            else if (mouse.button === Qt.LeftButton && !root.popupOnHover) {
                if (root.popupShown) {
                    root.popupOpen = false;
                    if (root.shouldOpenFromShortcut) {
                        GlobalStates.mediaControlsOpen = false;
                    }
                } else {
                    root.popupOpen = true;
                    if (!GlobalStates.barMediaPresent) {
                        GlobalStates.mediaControlsOpen = true;
                    }
                }
            }
            else root.player?.togglePlaying();
        }
    }

    // Same controls the bar's media widget pops up, but anchored to the dock
    // like the window previews are - the bar-anchored one lands in the corner
    // when there is no bar widget to anchor to.
    readonly property bool popupOnHover: Config.options?.dock.mediaPopupOnHover ?? false
    readonly property string dockPos: dock.dockEffectivePosition
    property bool popupOpen: false
    property bool popupShown: false
    readonly property bool popupHovered: popupHover.hovered
    readonly property bool shouldOpenFromShortcut: !GlobalStates.barMediaPresent && GlobalStates.mediaControlsOpen
    readonly property bool popupShouldShow: !!root.player && (
        (root.popupOnHover && (root.mediaHovered || root.popupHovered)) ||
        root.popupOpen ||
        shouldOpenFromShortcut
    )
    // Only sampled while opening: mapToItem doesn't track the dock sliding in.
    property point popupCenter: Qt.point(0, 0)

    function updatePopupCenter() {
        popupCenter = root.mapToItem(null, root.width / 2, root.height / 2);
    }

    onPopupShouldShowChanged: {
        if (popupShouldShow) {
            updatePopupCenter();
            popupShown = true;
        } else {
            popupHideTimer.restart();
        }
    }

    onXChanged: if (popupShown) updatePopupCenter()
    onWidthChanged: if (popupShown) updatePopupCenter()

    onPopupShownChanged: {
        if (popupShown) {
            GlobalFocusGrab.addDismissable(mediaPopup);
        } else {
            GlobalFocusGrab.removeDismissable(mediaPopup);
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            root.popupOpen = false;
            if (!GlobalStates.barMediaPresent) {
                GlobalStates.mediaControlsOpen = false;
            }
        }
    }

    Component.onCompleted: {
        GlobalStates.dockMediaCount++;
    }

    Component.onDestruction: {
        GlobalFocusGrab.removeDismissable(mediaPopup);
        GlobalStates.dockMediaCount = Math.max(0, GlobalStates.dockMediaCount - 1);
    }

    Timer {
        id: popupHideTimer
        interval: 150
        onTriggered: root.popupShown = root.popupShouldShow
    }

    PopupWindow {
        id: mediaPopup
        visible: root.popupShown || playerCard.opacity > 0
        color: "transparent"
        implicitWidth: Appearance.sizes.mediaControlsWidth
        implicitHeight: playerCard.implicitHeight

        readonly property var dockWindow: root.QsWindow.window

        anchor {
            window: mediaPopup.dockWindow
            adjustment: PopupAdjustment.None

            rect {
                x: root.isVertical ? (root.dockPos === "left" ? (mediaPopup.dockWindow?.width ?? 0) : 0) : Math.max(0, Math.min(root.popupCenter.x - mediaPopup.implicitWidth / 2, (mediaPopup.dockWindow?.width ?? 0) - mediaPopup.implicitWidth))
                y: root.isVertical ? Math.max(0, Math.min(root.popupCenter.y - mediaPopup.implicitHeight / 2, (mediaPopup.dockWindow?.height ?? 0) - mediaPopup.implicitHeight)) : (root.dockPos === "top" ? (mediaPopup.dockWindow?.height ?? 0) : 0)
            }

            gravity: {
                if (root.dockPos === "left") return Edges.Right | Edges.Bottom;
                if (root.dockPos === "right") return Edges.Left | Edges.Bottom;
                if (root.dockPos === "top") return Edges.Bottom | Edges.Right;
                return Edges.Top | Edges.Right;
            }

            edges: Edges.Top | Edges.Left
        }

        PlayerControl {
            id: playerCard
            width: parent.width
            height: implicitHeight
            player: root.player
            visualizerPoints: Config.options.dock.enableMediaVisualizer ? CavaService.visualizerPoints : []
            radius: Appearance.rounding.large
            opacity: root.popupShown ? 1 : 0

            HoverHandler {
                id: popupHover
            }

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    component ArtImage: Rectangle {
        id: artRect
        color: ColorUtils.transparentize(root.blendedColors.colLayer1, 0.5)
        radius: Appearance.rounding.small

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: artRect.width
                height: artRect.height
                radius: artRect.radius
            }
        }

        StyledImage {
            id: artImg
            anchors.fill: parent
            source: root.artSource
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true
            sourceSize.width: artRect.width
            sourceSize.height: artRect.height
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: artImg.status !== Image.Ready
            text: "music_note"
            iconSize: artRect.width * 0.48
            color: root.blendedColors.colOnLayer1
        }
    }

    StyledRectangularShadow {
        target: card
        visible: !root.isVertical
    }

    Rectangle {
        id: card
        visible: !root.isVertical
        anchors.fill: parent
        anchors.margins: Appearance.sizes.hyprlandGapsOut
        radius: Appearance.rounding.normal
        color: "transparent"

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: card.width
                height: card.height
                radius: card.radius
            }
        }

        Rectangle {
            anchors.fill: parent
            color: root.blendedColors.colLayer0
        }

        Image {
            id: blurredArt
            // Overscan so the blur has pixels to pull from instead of fading at the edges.
            anchors.fill: parent
            anchors.margins: -card.height * 0.4
            source: root.artSource
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 64
                blur: 1
                saturation: 0.6
            }
        }

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize(root.blendedColors.colLayer0, 0.45)
        }

        Loader {
            anchors.fill: parent
            active: Config.options.dock.enableMediaVisualizer

            sourceComponent: WaveVisualizer {
                points: CavaService.visualizerPoints
                live: root.isPlaying
                color: root.blendedColors.colOnLayer0
                waveOpacity: 0.45
                smoothing: 2
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 7
            anchors.rightMargin: 4
            clip: true
            spacing: 8

            ArtImage {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.artSize
                implicitHeight: root.artSize
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: -2

                StyledText {
                    Layout.fillWidth: true
                    text: root.trackArtist
                    font.pixelSize: Appearance.font.pixelSize.small - 2
                    color: root.blendedColors.colSubtext
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.trackTitle
                    font.pixelSize: Appearance.font.pixelSize.normal - 4
                    color: root.blendedColors.colOnLayer0
                    elide: Text.ElideRight
                    opacity: 0.7
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: root.isPlaying ? Appearance.rounding.normal : implicitWidth / 2
                colBackground: root.isPlaying ? root.blendedColors.colPrimary : root.blendedColors.colSecondaryContainer
                colBackgroundHover: root.isPlaying ? root.blendedColors.colPrimaryHover : root.blendedColors.colSecondaryContainerHover
                colRipple: root.isPlaying ? root.blendedColors.colPrimaryActive : root.blendedColors.colSecondaryContainerActive
                downAction: () => root.player?.togglePlaying()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: root.isPlaying ? "pause" : "play_arrow"
                    iconSize: Appearance.font.pixelSize.large
                    fill: 1
                    color: root.isPlaying ? root.blendedColors.colOnPrimary : root.blendedColors.colOnSecondaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 28
                implicitHeight: 28
                colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
                colBackgroundHover: root.blendedColors.colSecondaryContainerHover
                colRipple: root.blendedColors.colSecondaryContainerActive
                downAction: () => root.player?.next()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "skip_next"
                    iconSize: Appearance.font.pixelSize.large
                    fill: 1
                    color: root.blendedColors.colOnSecondaryContainer
                }
            }
        }
    }

    ArtImage {
        visible: root.isVertical
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(root.buttonSize * 0.9)
        height: width
    }

    DockTooltip {
        parentItem: root
        text: root.trackTitle + " - " + root.trackArtist
        showTooltip: root.isVertical && root.mediaHovered
    }
}
