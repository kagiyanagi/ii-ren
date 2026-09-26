pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick

/**
 * A row of attachment tiles: the picture for an image or a PDF's first page, the
 * file's icon and name for anything else. Over the composer, where each has an X,
 * and over a sent bubble, where it records what went with the turn.
 *
 * Takes HermesService's markers ({ kind, name, icon, thumb, ... }). One mask rounds
 * every tile: a layer per tile would be a layer per delegate.
 */
Item {
    id: root

    property var attachments: []
    property bool removable: false
    property color tileColor: Appearance.colors.colLayer3
    readonly property real tile: 64
    readonly property real spacing: 8

    signal removeRequested(var attachment)

    visible: attachments.length > 0
    implicitWidth: attachments.length * (tile + spacing) - spacing
    implicitHeight: tiles.implicitHeight

    Flow {
        id: tiles
        width: parent.width
        spacing: root.spacing
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: tileMask
        }

        Repeater {
            model: root.attachments

            delegate: Rectangle {
                id: tile
                required property var modelData
                width: root.tile
                height: root.tile
                color: root.tileColor

                // Fades in where it lands, as a transcript row does
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                StyledImage {
                    id: picture
                    anchors.fill: parent
                    visible: (tile.modelData.thumb ?? "").length > 0
                    source: visible ? Qt.resolvedUrl(tile.modelData.thumb) : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: width
                    sourceSize.height: height
                }

                Column {
                    visible: !picture.visible
                    anchors.centerIn: parent
                    width: parent.width - 8
                    spacing: 2

                    MaterialSymbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.modelData.icon ?? "draft"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        text: tile.modelData.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer3
                    }
                }

                Rectangle { // Remove
                    visible: root.removable
                    anchors {
                        top: parent.top
                        right: parent.right
                        margins: 4
                    }
                    width: 20
                    height: 20
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }

                    StateOverlay {
                        anchors.fill: parent
                        radius: parent.radius
                        hover: removeArea.containsMouse
                        press: removeArea.pressed
                        contentColor: Appearance.colors.colOnLayer2
                    }

                    MouseArea {
                        id: removeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeRequested(tile.modelData)
                    }
                }
            }
        }
    }

    Flow {
        id: tileMask
        visible: false
        width: tiles.width
        height: tiles.height
        spacing: root.spacing

        Repeater {
            model: root.attachments

            delegate: Rectangle {
                width: root.tile
                height: root.tile
                radius: Appearance.rounding.small
            }
        }
    }
}
