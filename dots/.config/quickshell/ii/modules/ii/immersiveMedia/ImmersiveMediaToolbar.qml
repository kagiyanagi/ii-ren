pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

RowLayout {
    id: root

    required property QtObject scheme
    required property MprisPlayer player
    required property var players
    required property bool lyricsShown

    signal toggleLyrics
    signal requestClose

    // How far the glass controls are thinned against the art behind them.
    readonly property real glassAlpha: 0.4

    spacing: 12

    component ToolbarIconButton: RippleButton {
        id: iconButton
        property string iconName
        property bool active: false

        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        toggled: iconButton.active
        // Hover and pressed keep the rest alpha so the change the user sees is
        // the M3 state layer (0.08 / 0.10) and not a jump to a solid fill.
        colBackground: ColorUtils.transparentize(root.scheme.container, root.glassAlpha)
        colBackgroundHover: ColorUtils.transparentize(root.scheme.containerHover, root.glassAlpha)
        colBackgroundActive: ColorUtils.transparentize(root.scheme.containerActive, root.glassAlpha)
        colRipple: ColorUtils.transparentize(root.scheme.containerActive, root.glassAlpha)
        colBackgroundToggled: root.scheme.accent
        colBackgroundToggledHover: root.scheme.accentHover
        colRippleToggled: root.scheme.accentActive

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.larger
            fill: iconButton.active ? 1 : 0
            text: iconButton.iconName
            color: iconButton.active ? root.scheme.onAccent : root.scheme.onContainer

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on fill {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    StyledText {
        text: Translation.tr("Media Player")
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.scheme.subtext
    }

    RippleButton {
        id: playerChip
        readonly property int playerIndex: root.players.indexOf(root.player)
        readonly property bool canCycle: root.players.length > 1

        Layout.maximumWidth: 260
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 16
        buttonRadius: Appearance.rounding.full
        // Stays enabled with a single player: the chip is the current player's
        // label first and a switcher second, and 0.4 would hide the name.
        pointingHandCursor: playerChip.canCycle
        colBackground: root.scheme.container
        colBackgroundHover: root.scheme.containerHover
        colBackgroundActive: root.scheme.containerActive
        colRipple: root.scheme.containerActive

        onClicked: {
            if (!playerChip.canCycle)
                return;
            const next = (playerChip.playerIndex + 1) % root.players.length;
            MprisController.setActivePlayer(root.players[next]);
        }

        contentItem: RowLayout {
            spacing: 8

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.large
                fill: 1
                text: "graphic_eq"
                color: root.scheme.onContainer
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.player?.identity || Translation.tr("No player")
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.scheme.onContainer
                elide: Text.ElideRight
            }
        }

        StyledToolTip {
            text: playerChip.canCycle ? Translation.tr("Switch to the next player") : Translation.tr("No other players")
        }
    }

    Item {
        Layout.fillWidth: true
    }

    ToolbarIconButton {
        iconName: "lyrics"
        active: root.lyricsShown
        onClicked: root.toggleLyrics()

        StyledToolTip {
            text: Translation.tr("Lyrics (L)")
        }
    }

    ToolbarIconButton {
        iconName: "close"
        onClicked: root.requestClose()

        StyledToolTip {
            text: Translation.tr("Close (Esc)")
        }
    }
}
