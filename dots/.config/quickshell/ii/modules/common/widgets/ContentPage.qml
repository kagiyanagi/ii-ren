import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A scrolling settings page. Give it a `title` and it renders the page header
 * — back arrow, then title — as the first thing in its column; leave the title
 * empty and the header is `visible: false`, which a ColumnLayout skips
 * entirely, so a page that had no header before is laid out exactly as it was.
 *
 * `showBackButton` and `goBack()` are what ConfigSubPageHost looks for when it
 * loads a sub-page, which is why they live here rather than in 61 copies.
 */
StyledFlickable {
    id: root
    // 600 left the two-up chip rows a few pixels short once the cards took
    // their padding, so every one of them wrapped a trailing chip onto row two.
    property real baseWidth: 660
    property bool forceWidth: false
    property real bottomContentPadding: 100

    // The page header. Empty title = no header at all.
    property string title: ""
    property bool showBackButton: false
    signal goBack

    default property alias contentData: contentColumn.data

    clip: true
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding // Add some padding at the bottom
    implicitWidth: contentColumn.implicitWidth

    ColumnLayout {
        id: contentColumn
        width: root.forceWidth ? root.baseWidth : Math.max(root.baseWidth, implicitWidth)
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            margins: 20
        }
        spacing: 32

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: root.title !== ""

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: Appearance.sizes.pageHeaderButtonSize
                visible: root.showBackButton
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                colStateLayer: Appearance.colors.colOnSecondaryContainer
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }

                StyledToolTip {
                    text: Translation.tr("Back")
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }

        }

    }

}
