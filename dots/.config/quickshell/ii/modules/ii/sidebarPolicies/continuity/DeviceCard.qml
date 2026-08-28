pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One connected thing: an icon, a name, a status line and a battery bar.
 * Used for both the phone and every connected bluetooth device so the two
 * never drift apart visually - they are the same object to the user.
 */
Rectangle {
    id: root
    required property string icon
    required property string name
    property string status: ""
    property int charge: -1
    property bool charging: false
    property bool prominent: false
    property bool dimmed: false
    property bool acceptsDrops: false
    // Tapping the card opens whatever page it fronts; the chevron is the only
    // hint the user gets, so it only appears when there is somewhere to go.
    property bool clickable: false
    property bool expanded: false
    signal filesDropped(var urls)
    signal clicked()
    default property alias extraContent: extraColumn.data

    readonly property bool hasBattery: root.charge >= 0
    // Android turns the bar red below 20 rather than colouring by percent all
    // the way down; anything else reads as an alarm that never stops.
    readonly property color chargeColor: !root.hasBattery ? Appearance.colors.colOutlineVariant
        : root.charging ? Appearance.m3colors.m3tertiary
        : root.charge <= 20 ? Appearance.m3colors.m3error
        : root.prominent ? Appearance.colors.colOnPrimaryContainer
        : Appearance.colors.colOnSecondaryContainer

    Layout.fillWidth: true
    implicitHeight: cardColumn.implicitHeight + 28
    radius: Appearance.rounding.large
    color: root.prominent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
    opacity: root.dimmed ? 0.55 : 1

    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

    readonly property color colText: root.prominent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2

    DropArea {
        anchors.fill: parent
        enabled: root.acceptsDrops
        onDropped: drop => {
            if (!drop.hasUrls) return;
            root.filesDropped(drop.urls);
            drop.accept();
        }
    }

    // Under the content column, so the action pills keep their own clicks.
    MouseArea {
        anchors.fill: parent
        enabled: root.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ColumnLayout {
        id: cardColumn
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShape {
                implicitSize: root.prominent ? 44 : 36
                shape: MaterialShape.Shape.Circle
                color: root.prominent ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.icon
                    iconSize: root.prominent ? 26 : 21
                    fill: 1
                    color: root.prominent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: root.name
                    elide: Text.ElideRight
                    font.pixelSize: root.prominent ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.colText
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.status !== ""
                    text: root.status
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.prominent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    opacity: 0.85
                }
            }

            RowLayout {
                visible: root.hasBattery
                spacing: 2
                MaterialSymbol {
                    visible: root.charging
                    text: "bolt"
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1
                    color: root.chargeColor
                }
                StyledText {
                    text: root.hasBattery ? `${root.charge}%` : ""
                    font.pixelSize: root.prominent ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: root.chargeColor
                }
            }

            MaterialSymbol {
                visible: root.clickable
                text: root.expanded ? "expand_less" : "expand_more"
                iconSize: Appearance.font.pixelSize.larger
                color: root.colText
            }
        }

        Rectangle { // Battery track
            visible: root.hasBattery
            Layout.fillWidth: true
            implicitHeight: root.prominent ? 8 : 6
            radius: Appearance.rounding.full
            // Transparentized rather than given an opacity: opacity would
            // fade the fill sitting inside it too.
            color: ColorUtils.transparentize(root.prominent ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant, 0.7)

            Rectangle {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: parent.width * Math.max(0, Math.min(100, root.charge)) / 100
                radius: parent.radius
                color: root.chargeColor
                Behavior on width { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            }
        }

        ColumnLayout {
            id: extraColumn
            Layout.fillWidth: true
            spacing: 8
        }
    }
}
