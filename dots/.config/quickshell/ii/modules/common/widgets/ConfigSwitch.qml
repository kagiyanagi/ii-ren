import qs.modules.common.widgets
import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: root
    property string buttonIcon
    property alias iconSize: iconWidget.iconSize

    Layout.fillWidth: true
    readonly property bool wantsCard: true
    leftPadding: 8
    rightPadding: 8
    implicitHeight: contentItem.implicitHeight + 12 * 2
    buttonRadius: Appearance.rounding.verysmall
    font.pixelSize: Appearance.font.pixelSize.small
    
    // False for a switch that mirrors a service: its onClicked asks the service,
    // and the `checked` binding, left intact, shows what really happened (TASTE 3.1).
    property bool toggles: true
    onClicked: if (toggles) checked = !checked

    property color normalColor: ColorUtils.transparentize(Appearance?.colors.colLayer1Hover, 1) 
    property color highlightColor: Appearance.colors.colSecondaryContainer

    colBackground: normalColor

    SearchHandler {
        searchString: root.text
    }

    // The search flash has to cover the card, not the button: ContentGroup
    // makes the card 8px wider per side and rounds the ends of a run harder
    // than its seams, so a single buttonEffectiveRadius stopped short of the
    // card's edges and squared the corners it rounds (5.6, 10.13).
    HighlightOverlay {
        id: highlightOverlay
        x: -root.backgroundBleedLeft
        width: root.width + root.backgroundBleedLeft + root.backgroundBleedRight
        height: root.height
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        color: root.highlightColor
    }

    contentItem: RowLayout {
        spacing: 10
        // Disabled is 0.4 on the whole control and RippleButton already applies
        // it; dimming the children as well multiplied out to 0.16 while the
        // switch beside them sat at 0.4 (3.1).
        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: root.text
            font.pixelSize: root.font.pixelSize
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledSwitch {
            id: switchWidget
            down: root.down
            Layout.fillWidth: false
            checked: root.checked
            onClicked: root.clicked()
        }
    }
}