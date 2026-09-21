import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

Rectangle {
    id: root
    required property var element
    required property int size
    required property color fill
    // Set while a search is narrowing the table: the tile stays in place so the
    // grid keeps its shape, and recedes instead of disappearing.
    property bool dimmed: false
    // False while the detail card is up. Disabling the grid is not enough on its
    // own: the pointer has not moved, so `containsMouse` stays latched and the
    // tooltip of whichever tile it was resting on draws on top of the card.
    property bool interactive: true

    signal activated

    readonly property int padding: 4
    readonly property color ink: ColorUtils.getContrastingTextColor(root.fill)

    width: root.size
    height: root.size
    radius: Appearance.rounding.verysmall
    color: root.fill
    opacity: root.dimmed ? 0.25 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    // Grows a little under the pointer and settles back on release (3.3). The
    // scale sits on a spatial spec; the state film over it is an effects one.
    scale: mouse.pressed ? 0.94 : mouse.containsMouse ? 1.08 : 1
    z: mouse.containsMouse ? 1 : 0
    Behavior on scale {
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
    }

    Rectangle { // hover / press film, at the tokenised state-layer alphas
        anchors.fill: parent
        radius: parent.radius
        color: root.ink
        opacity: mouse.pressed ? 0.10 : mouse.containsMouse ? 0.08 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    StyledText {
        anchors {
            top: parent.top
            left: parent.left
            margins: root.padding
        }
        color: root.ink
        opacity: 0.75
        font.pixelSize: Appearance.font.pixelSize.smallest
        text: root.element.number
    }

    StyledText {
        id: symbol
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -root.size * 0.05
        color: root.ink
        font.weight: Font.DemiBold
        // The symbol is the tile's headline and the tile is sized to the screen,
        // so this one tracks the tile rather than a fixed step.
        font.pixelSize: Math.max(Appearance.font.pixelSize.smallest, Math.round(root.size * 0.38))
        text: root.element.symbol
    }

    StyledText {
        // A width is what lets StyledText elide; eight names are wider than any
        // tile this table will ever draw.
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: root.padding
        }
        horizontalAlignment: Text.AlignHCenter
        color: root.ink
        opacity: 0.75
        font.pixelSize: Appearance.font.pixelSize.smallest
        text: root.element.name
        visible: root.size >= 44
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    StyledToolTip {
        extraVisibleCondition: root.interactive && mouse.containsMouse
        text: `${root.element.name} · ${root.element.category}\n`
            + `${root.element.configShort} · ${Translation.tr("group")} ${root.element.group}, `
            + `${Translation.tr("period")} ${root.element.period}, ${root.element.block}-${Translation.tr("block")}`
    }
}
