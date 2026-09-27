import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * The top button for the indicators that have no toggle row of their own --
 * player volume and keyboard brightness. Volume and the display indicators carry
 * their own connected button groups and never reach this.
 */
RippleButton {
    id: button

    property string currentIndicator: "volume"
    property real expandedProgress: 0.0
    property real buttonHeight: 56

    readonly property bool isKeyboard: currentIndicator === "keyboardBrightness"
    readonly property bool muted: (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false

    rippleEnabled: true

    toggled: isKeyboard ? GlobalStates.oskOpen : muted

    buttonRadius: buttonHeight / 2

    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundToggled: Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
    colRipple: Appearance.colors.colSecondaryContainerActive
    colRippleToggled: Appearance.colors.colPrimaryActive

    readonly property string currentIcon: isKeyboard ? "keyboard" : (muted ? "volume_off" : "volume_up")

    readonly property string currentText: {
        if (isKeyboard)
            return GlobalStates.oskOpen ? Translation.tr("Close keyboard") : Translation.tr("Open keyboard");
        return muted ? Translation.tr("Unmute output") : Translation.tr("Mute output");
    }

    readonly property color iconColor: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

    contentItem: RowLayout {
        spacing: 8 * button.expandedProgress
        anchors.fill: parent
        anchors.leftMargin: button.expandedProgress > 0.01 ? 16 : 0
        anchors.rightMargin: button.expandedProgress > 0.01 ? 16 : 0

        MaterialSymbol {
            id: buttonIcon
            text: button.currentIcon
            color: button.iconColor
            iconSize: Appearance.font.pixelSize.larger
            fill: button.toggled ? 1 : 0
            Layout.alignment: Qt.AlignVCenter | (button.expandedProgress > 0.01 ? Qt.AlignLeft : Qt.AlignHCenter)
        }

        StyledText {
            id: buttonText
            text: button.currentText
            color: button.iconColor
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            visible: button.expandedProgress > 0.5
            opacity: (button.expandedProgress - 0.5) * 2
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
        }
    }

    onClicked: {
        if (isKeyboard)
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        else
            Audio.toggleMute();
    }

    StyledToolTip {
        text: button.currentText
        extraVisibleCondition: button.hovered
    }
}
