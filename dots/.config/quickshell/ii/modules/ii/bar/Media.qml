import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.modules.common.utils
import QtQuick.Effects

Item {
    id: root
    Layout.fillHeight: true

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    
    property int customSize: Config.options.bar.mediaPlayer.customSize
    property int lyricsCustomSize: Config.options.bar.mediaPlayer.lyrics.customSize

    property bool useFixedSize: Config.options.bar.mediaPlayer.useFixedSize
    readonly property bool lyricsEnabled: Config.options.bar.mediaPlayer.lyrics.enable
    readonly property bool useGradientMask: Config.options.bar.mediaPlayer.lyrics.useGradientMask
    readonly property string lyricsStyle: Config.options.bar.mediaPlayer.lyrics.style
    readonly property bool artworkEnabled: Config.options.bar.mediaPlayer.artwork.enable

    readonly property int progressButtonSize: 20
    readonly property int artworkBoxSize: artworkEnabled ? Math.min(25, Appearance.sizes.barHeight - 8) : 0
    readonly property int artworkContentPadding: artworkEnabled ? 6 : 0

    property int textMetricsSpacing: artworkEnabled ? 70 : 50 // text metrics returns width without spacing
    property int textMetricsAdvance: Math.min(textMetrics.advanceWidth + textMetricsSpacing, Config.options.bar.mediaPlayer.maxSize)
    readonly property int classicWidth: LyricsService.hasSyncedLines && root.lyricsEnabled ? lyricsCustomSize : useFixedSize ? customSize : textMetricsAdvance
    implicitWidth: root.material ? (materialPill.item?.implicitWidth ?? 0) : classicWidth
    implicitHeight: Appearance.sizes.barHeight

    // The bar slot's width is size, not a tint: the resize spec, not the
    // effects one it used to borrow (2.3).
    Behavior on implicitWidth {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(root)
    }

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
        GlobalStates.barMediaCount++;
    }
    Component.onDestruction: {
        GlobalStates.barMediaCount = Math.max(0, GlobalStates.barMediaCount - 1);
    }

    function updatePopupRect() {
        var globalPos = root.mapToItem(null, 0, 0);
        Persistent.states.media.popupX = globalPos.x;
        Persistent.states.media.popupY = globalPos.y;
        Persistent.states.media.popupWidth = root.width;
        Persistent.states.media.popupHeight = root.height;
    }

    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen) {
                root.updatePopupRect();
            }
        }
    }

    readonly property string artSource: MprisController.artUrlFor(activePlayer)

    // Material style (bar.barGroupStyle 3): the dock's media card as a bar pill
    // (DockMediaWidget) -- blurred art under the bar's own layer, title over
    // artist, play/pause on a primary pill and next beside it. Theme colours,
    // not the dock's art-derived scheme: bright art turned that scheme's text
    // and fill the same light tint.
    readonly property bool material: Config.options.bar.barGroupStyle === 3
    readonly property bool isPlaying: activePlayer?.isPlaying ?? false
    // As the dock: title and artist until the first lyric plays, then the lyric alone.
    readonly property bool lyricsMode: lyricsEnabled && LyricsService.hasSyncedLines && LyricsService.currentIndex >= 0
    // "static" is the one line below; "scroller" swaps it for the classic bar's scroller.
    readonly property bool scrollerLyrics: lyricsMode && lyricsStyle === "scroller"

    Item {
        id: artworkItem
        visible: artworkEnabled && !root.material
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: artworkEnabled ? artworkBoxSize : 0
        height: artworkEnabled ? artworkBoxSize : 0

        // ClippingRectangle rounds the artwork with the scene graph's own
        // clip, where this used to spend a framebuffer and an OpacityMask pass
        // per frame on a 25px circle (8: native radii before a mask).
        ClippingRectangle {
            anchors.fill: parent
            color: Appearance.colors.colPrimaryContainer
            radius: Appearance.rounding.full

            Image {
                anchors.fill: parent
                source: root.artSource
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                sourceSize.width: width
                sourceSize.height: height
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.artSource.length === 0
                fill: 1
                text: "music_note"
                iconSize: Math.max(12, artworkItem.width * 0.5)
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton) {
                activePlayer.togglePlaying();
            } else if (event.button === Qt.BackButton) {
                activePlayer.previous();
            } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
                activePlayer.next();
            } else if (event.button === Qt.LeftButton) {
                root.updatePopupRect();
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            }
        }   
    }

    Item {
        id: mediaCircProgSlot
        visible: !root.material
        width: root.progressButtonSize
        height: root.progressButtonSize
        anchors.verticalCenter: parent.verticalCenter
        x: artworkEnabled ? root.width - width : 0

        ClippedFilledCircularProgress {
            id: mediaCircProg
            anchors.fill: parent
            implicitSize: root.progressButtonSize

            lineWidth: Appearance.rounding.unsharpen
            value: activePlayer?.position / activePlayer?.length
            colPrimary: Appearance.colors.colOnSecondaryContainer
            enableAnimation: false

            Item {
                anchors.centerIn: parent
                width: mediaCircProg.implicitSize
                height: mediaCircProg.implicitSize
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: activePlayer?.isPlaying ? "pause" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    TextMetrics {
        id: textMetrics
        text: `${cleanedTitle}${activePlayer?.trackArtist ? ' • ' + activePlayer.trackArtist : ''}`
    }

    StyledText {
        visible: (!LyricsService.hasSyncedLines || !lyricsEnabled) && !root.material
        anchors {
            horizontalCenter: parent.horizontalCenter
            horizontalCenterOffset: artworkEnabled ? 0 : mediaCircProgSlot.width / 2
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: 1 // to vertically center it
        }
        horizontalAlignment: Text.AlignHCenter
        width: artworkEnabled ? parent.implicitWidth - (artworkItem.width + mediaCircProgSlot.width + artworkContentPadding + 16) : parent.implicitWidth - mediaCircProgSlot.width - 16
        elide: Text.ElideRight
        color: Appearance.colors.colOnLayer1
        text: `${cleanedTitle}${activePlayer?.trackArtist ? ' • ' + activePlayer.trackArtist : ''}`
    }

    Loader {
        id: lyricsItemLoader 
        active: lyricsEnabled && !root.material

        width: artworkEnabled ? parent.width - (artworkItem.width + mediaCircProg.implicitSize * 2) : parent.width - mediaCircProg.implicitSize * 2
        height: parent.height
        
        anchors.left: parent.left
        anchors.leftMargin: artworkEnabled ? mediaCircProg.implicitSize * 1.5 + artworkContentPadding : mediaCircProg.implicitSize * 1.5

        sourceComponent: Item {
            id: lyricsItem
            visible: lyricsEnabled
            
            anchors.centerIn: parent

            Loader {
                active: lyricsStyle == "static"
                anchors.fill: parent
                anchors.centerIn: parent
                sourceComponent: LyricsStatic {
                    anchors.fill: parent
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Loader {
                active: lyricsStyle == "scroller"
                anchors.fill: parent
                sourceComponent: LyricScroller {
                    id: lyricScroller
                    
                    anchors.fill: parent
                    visible: lyricsStyle == "scroller" && LyricsService.hasSyncedLines
                    
                    defaultLyricsSize: Appearance.font.pixelSize.smallest
                    useGradientMask: root.useGradientMask
                    halfVisibleLines: 1
                    downScale: 0.98
                    rowHeight: 10
                    gradientDensity: 0.25
                }
            }
        }   
    }

    Loader {
        id: materialPill
        active: root.material
        anchors.centerIn: parent
        sourceComponent: ClippingRectangle {
            id: pill
            readonly property string art: CoverArt.source(root.artSource)
            readonly property int maxWidth: root.useFixedSize ? root.customSize
                : root.lyricsMode ? root.lyricsCustomSize : Config.options.bar.mediaPlayer.maxSize

            implicitHeight: Appearance.sizes.baseBarHeight - 8
            // Fixed under lyrics, or every new line would resize the pill.
            implicitWidth: root.useFixedSize || root.lyricsMode ? maxWidth : Math.min(pillRow.implicitWidth + 12 + 4, maxWidth)
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            // The pill's one effect. Overscanned so the blur has pixels to
            // pull from at the edges; the ClippingRectangle trims it.
            Image {
                anchors.fill: parent
                anchors.margins: -pill.height * 0.4
                visible: pill.art.length > 0
                source: pill.art
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: true
                sourceSize.width: pill.maxWidth
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 32
                    blur: 1
                    saturation: 0.6
                }
            }
            Rectangle {
                anchors.fill: parent
                visible: pill.art.length > 0
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45)
            }

            StateOverlay {
                anchors.fill: parent
                radius: pill.radius
                contentColor: Appearance.colors.colOnLayer0
                hover: mouseArea.containsMouse
                press: mouseArea.pressed
            }

            RowLayout {
                id: pillRow
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 4
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: !root.scrollerLyrics
                    spacing: -2

                    StyledText {
                        Layout.fillWidth: true
                        text: root.lyricsMode ? (LyricsService.syncedLines[LyricsService.currentIndex]?.text ?? "") : root.cleanedTitle
                        animateChange: root.lyricsEnabled
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !root.lyricsMode && text.length > 0
                        text: root.activePlayer?.trackArtist ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: root.scrollerLyrics
                    visible: active
                    sourceComponent: LyricScroller {
                        defaultLyricsSize: Appearance.font.pixelSize.smallest
                        useGradientMask: root.useGradientMask
                        halfVisibleLines: 1
                        downScale: 0.98
                        rowHeight: 10
                        gradientDensity: 0.25
                        // Off the pill's left edge like the title it replaces.
                        textAlign: "left"
                    }
                }

                // The accent: BarMaterialPill's 4 in from the end, a pill while
                // playing, a circle while paused, as the dock's button morphs.
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: pill.height - 8
                    implicitWidth: root.isPlaying ? implicitHeight + 16 : implicitHeight
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    colStateLayer: Appearance.colors.colOnPrimary
                    downAction: () => root.activePlayer?.togglePlaying()
                    Behavior on implicitWidth {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: root.isPlaying ? "pause" : "play_arrow"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: Appearance.colors.colOnPrimary
                    }
                    PopupToolTip {
                        text: root.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: pill.height - 8
                    implicitWidth: implicitHeight
                    buttonRadius: Appearance.rounding.full
                    colBackgroundHover: Appearance.colors.colLayer0Hover
                    colRipple: Appearance.colors.colLayer0Active
                    colStateLayer: Appearance.colors.colOnLayer0
                    downAction: () => root.activePlayer?.next()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "skip_next"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: Appearance.colors.colOnLayer0
                    }
                    PopupToolTip {
                        text: Translation.tr("Next")
                    }
                }
            }
        }
    }
}
