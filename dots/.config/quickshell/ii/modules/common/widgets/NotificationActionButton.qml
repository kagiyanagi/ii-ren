import qs.modules.common
import QtQuick
import Quickshell.Services.Notifications

RippleButton {
    id: button
    property string urgency

    // A notification action is a real text button, so DESIGN.md 9's standard 40
    // rather than its compact 30; it also clears the 32px hit minimum (3.4).
    implicitHeight: 40
    leftPadding: 16 // 5.2: 16 leading / 16 trailing on a small text button
    rightPadding: 16
    buttonRadius: Appearance.rounding.full

    // The service stores urgency as the enum's decimal string, so a bare ===
    // against the enum never matches. Number() reads both forms.
    readonly property bool critical: Number(button.urgency) === NotificationUrgency.Critical
    // Content takes the container's own pair: a secondary-container fill is read
    // with onSecondaryContainer, not onSurfaceVariant, and the semantic layer is
    // the one to ask (6.1).
    readonly property color colContent: button.critical ?
        Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer4

    colBackground: button.critical ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer4
    colBackgroundHover: button.critical ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer4Hover
    colRipple: button.critical ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer4Active
    // Focus and the pressed film come from RippleButton, but they are films of
    // the *content* colour, and this button is not on layer 1.
    colStateLayer: button.colContent

    contentItem: StyledText {
        horizontalAlignment: Text.AlignHCenter
        text: button.buttonText
        color: button.colContent
    }
}
