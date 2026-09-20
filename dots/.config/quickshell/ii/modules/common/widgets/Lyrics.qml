pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft

    implicitWidth: 200
    implicitHeight: 200

    // Called by PlayerControlsLyrics after a manual seek, and by the retry tap
    // below. Every value in this file is a plain binding on
    // LyricsService.currentIndex/statusText, so a position jump redraws on its
    // own -- there is nothing to redrive by hand.
    function restartLyrics() {}

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !LyricsService.hasSyncedLines

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 48
                    implicitHeight: 48
                    padding: 0
                    buttonRadius: Appearance.rounding.full
                    downAction: () => root.restartLyrics()

                    contentItem: MaterialLoadingIndicator {
                        loading: true
                        color: root.indicatorColor
                        shapeColor: root.indicatorShapeColor
                        implicitSize: 48
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    color: root.textColor
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: LyricsService.statusText
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.hasSyncedLines
            spacing: 6

            Repeater {
                model: 7
                delegate: StyledText {
                    id: lyricSlot
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: root.textAlignment
                    wrapMode: Text.WordWrap
                    readonly property int centerOffset: index - 3 // model: 7, center slot
                    readonly property int actualIndex: LyricsService.currentIndex + centerOffset
                    readonly property bool isValidLine: actualIndex >= 0 && actualIndex < LyricsService.syncedLines.length
                    text: isValidLine ? LyricsService.syncedLines[actualIndex].text : ""
                    readonly property int dist: Math.abs(centerOffset)
                    font.pixelSize: {
                        if (dist === 0) return Appearance.font.pixelSize.normal
                        if (dist === 1) return Appearance.font.pixelSize.small
                        return Appearance.font.pixelSize.smaller
                    }
                    opacity: {
                        if (dist === 0) return 1.0
                        if (dist === 1) return 0.6
                        if (dist === 2) return 0.35
                        return 0.15
                    }
                    color: dist === 0 ? root.activeColor : root.textColor
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
