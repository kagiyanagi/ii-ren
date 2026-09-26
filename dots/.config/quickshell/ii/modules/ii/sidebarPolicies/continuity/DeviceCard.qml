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
    // Out of reach. The card drops its accent rather than fading: it still
    // holds the pill that fixes it, and a ghosted control reads as disabled.
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
    readonly property bool accent: root.prominent && !root.dimmed
    readonly property real padding: 16
    // Android turns the bar red below 20 rather than colouring by percent all
    // the way down; anything else reads as an alarm that never stops.
    readonly property color chargeColor: root.charging ? Appearance.m3colors.m3tertiary
        : root.charge <= 20 ? Appearance.m3colors.m3error
        : root.accent ? Appearance.colors.colOnPrimaryContainer
        : Appearance.colors.colOnSecondaryContainer
    readonly property color colText: root.accent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2

    Layout.fillWidth: true
    implicitHeight: cardColumn.implicitHeight + root.padding * 2
    radius: Appearance.rounding.large
    color: root.accent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    DropArea {
        anchors.fill: parent
        enabled: root.acceptsDrops
        onDropped: drop => {
            if (!drop.hasUrls) return;
            root.filesDropped(drop.urls);
            drop.accept();
        }
    }

    StateOverlay {
        anchors.fill: parent
        radius: root.radius
        contentColor: root.colText
        hover: cardArea.containsMouse
        press: cardArea.pressed
    }

    // Under the content column, so the action pills keep their own clicks.
    MouseArea {
        id: cardArea
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ColumnLayout {
        id: cardColumn
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShape {
                implicitSize: root.prominent ? 48 : 40
                shape: MaterialShape.Shape.Circle
                color: root.accent ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.icon
                    iconSize: root.prominent ? 24 : 20
                    fill: 1
                    color: root.accent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.name
                    // Names come from the devices themselves; rich text would
                    // let one fetch an <img>.
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: root.prominent ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.colText
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.status !== ""
                    text: root.status
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.accent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
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
                text: "expand_more"
                iconSize: Appearance.font.pixelSize.larger
                color: root.colText
                // Spins to point up rather than swapping glyphs mid-tap. A
                // rotation is spatial, so it rides elementMove, not an effects spec.
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }

        StyledProgressBar {
            visible: root.hasBattery
            Layout.fillWidth: true
            value: Math.max(0, Math.min(100, root.charge)) / 100
            highlightColor: root.chargeColor
            // Transparentized rather than given an opacity: opacity would
            // fade the fill sitting inside it too.
            trackColor: root.accent ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7) : Appearance.colors.colSecondaryContainer
        }

        ColumnLayout {
            id: extraColumn
            Layout.fillWidth: true
            spacing: 8
        }
    }
}
