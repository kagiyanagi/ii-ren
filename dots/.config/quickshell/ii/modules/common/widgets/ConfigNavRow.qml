import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A settings row that opens a sub-page: icon, title, a one-line summary of what
 * is set there, and a chevron. Same metrics as ConfigSwitch, and carded the same
 * way, so it reads as one more row of the list rather than a different control.
 * It used to be copied by hand into four pages, and none of the copies opted
 * into the card, so each sat bare under a carded run.
 */
RippleButton {
    id: root
    property string buttonIcon
    property string summary
    property string searchString: text
    property color highlightColor: Appearance.colors.colSecondaryContainer

    Layout.fillWidth: true
    readonly property bool wantsCard: true
    leftPadding: 8
    rightPadding: 8
    implicitHeight: contentItem.implicitHeight + 12 * 2
    buttonRadius: Appearance.rounding.verysmall
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)

    SearchHandler {
        searchString: root.searchString
    }

    HighlightOverlay {
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

        OptionalMaterialSymbol {
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.text
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                elide: Text.ElideRight
                text: root.summary
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        MaterialSymbol {
            text: "chevron_right"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
        }
    }
}
