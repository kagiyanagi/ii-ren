pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property QtObject scheme

    readonly property bool hasSynced: LyricsService.hasSyncedLines
    readonly property bool hasPlain: LyricsService.geniusHasLyrics && LyricsService.plainLyrics !== ""

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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ── Header ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                fill: 1
                text: "lyrics"
                color: root.scheme.onSurface
            }

            StyledText {
                text: Translation.tr("Lyrics")
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.large
                font.variableAxes: Appearance.font.variableAxes.title
                color: root.scheme.onSurface
            }

            Pill {
                implicitWidth: sourceBadge.implicitWidth + 20
                implicitHeight: 22
                color: ColorUtils.transparentize(root.scheme.container, 0.35)

                StyledText {
                    id: sourceBadge
                    anchors.centerIn: parent
                    text: {
                        if (root.hasSynced)
                            return Translation.tr("Synced");
                        if (root.hasPlain)
                            return Translation.tr("Plain");
                        return Translation.tr("None");
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.scheme.onContainer
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        // ── Body ─────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            LyricScroller {
                id: lyricScroller
                anchors.fill: parent
                visible: root.hasSynced
                defaultLyricsSize: Config.options.media.immersive.lyricSize
                useGradientMask: Config.options.media.immersive.useGradientMask
                halfVisibleLines: 3
                changeTextWeight: true
                rowHeight: Math.max(48, Math.min(Math.floor(height / 5), Config.options.media.immersive.lyricSize * 3))
            }

            StyledFlickable {
                anchors.fill: parent
                visible: !root.hasSynced && root.hasPlain
                contentWidth: width
                contentHeight: plainLyrics.implicitHeight

                StyledText {
                    id: plainLyrics
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: LyricsService.plainLyrics
                    font.family: Appearance.font.family.reading
                    font.pixelSize: Config.options.media.immersive.lyricSize
                    color: root.scheme.onSurface
                }
            }

            PagePlaceholder {
                shown: !root.hasSynced && !root.hasPlain
                icon: "music_note"
                title: Translation.tr("No lyrics")
                description: LyricsService.lyricsEnabled ? Translation.tr("Nothing found for this track") : Translation.tr("Lyrics are turned off in settings")
            }
        }
    }
}
