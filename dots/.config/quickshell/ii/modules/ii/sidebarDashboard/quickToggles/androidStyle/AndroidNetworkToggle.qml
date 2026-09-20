import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root

    toggleModel: NetworkToggle {}

    tall1x2OverrideComponent: netTall1x2
    wide2x2OverrideComponent: netWide2x2

    backgroundIcon: Network.ethernet ? "" : "wifi"
    
    Component {
        id: netTall1x2

        Item {
            anchors.fill: parent
            anchors.margins: 4

            MouseArea {
                id: netTallIconMouseArea
                width: 54
                height: 54
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                hoverEnabled: true
                acceptedButtons: root.altAction ? Qt.LeftButton : Qt.NoButton
                cursorShape: Qt.PointingHandCursor

                onClicked: root.mainAction()

                MaterialShape {
                    id: netTallShape
                    anchors.fill: parent
                    shapeString: "Cookie7Sided"
                    // The state film is mixed into the fill rather than laid over it: the
                    // film was a Rectangle over a ShapeCanvas, so it painted a square
                    // and read a `radius` that does not exist there (3.1, 10.8).
                    readonly property color colBase: root.toggled
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer3
                    readonly property color colFilm: root.toggled
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnLayer3
                    color: !root.altAction ? colBase
                        : netTallIconMouseArea.containsPress ? ColorUtils.mix(colFilm, colBase, 0.10)
                        : netTallIconMouseArea.containsMouse ? ColorUtils.mix(colFilm, colBase, 0.08)
                        : colBase

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        visible: root.backgroundIcon !== ""
                        anchors.centerIn: parent
                        iconSize: 26
                        opacity: 0.3
                        color: root.toggled
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer3
                        text: root.backgroundIcon
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: root.toggled ? 1 : 0
                        iconSize: 26
                        color: root.toggled
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer3
                        text: root.buttonIcon

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }

            Column {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottomMargin: 8
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 0

                StyledText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: 600
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                    text: root.name
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledText {
                    visible: root.statusText !== ""
                    anchors.left: parent.left
                    anchors.right: parent.right
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: 100
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
                    elide: Text.ElideRight
                    text: root.statusText
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Component {
        id: netWide2x2

        ColumnLayout {
            spacing: 0
            anchors.fill: parent

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(root.height * 0.60)

                MouseArea {
                    id: netWideIconMouseArea
                    width: 66
                    height: 66
                    anchors.centerIn: parent
                    hoverEnabled: true
                    acceptedButtons: root.altAction ? Qt.LeftButton : Qt.NoButton
                    cursorShape: Qt.PointingHandCursor

                    onClicked: root.mainAction()

                    MaterialShape {
                        id: netWideShape
                        anchors.fill: parent
                        shapeString: "Cookie7Sided"
                        color: root.toggled
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colLayer3

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        MaterialSymbol {
                            visible: root.backgroundIcon !== ""
                            anchors.centerIn: parent
                            iconSize: 28
                            opacity: 0.3
                            color: root.toggled
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer3
                            text: root.backgroundIcon
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: root.toggled ? 1 : 0
                            iconSize: 28
                            color: root.toggled
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer3
                            text: root.buttonIcon

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }

                        Loader {
                        anchors.fill: parent
                        active: root.altAction
                        sourceComponent: Rectangle {
                            radius: netWideShape.radius
                            color: ColorUtils.transparentize(
                                root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3,
                                netWideIconMouseArea.containsPress ? 0.88 : netWideIconMouseArea.containsMouse ? 0.95 : 1
                            )
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                text: root.name
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                visible: root.statusText !== ""
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 4
                text: root.statusText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Thin
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
