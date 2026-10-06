import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.animations
import qs.services
import QtQuick
import QtQuick.Layouts

// The whole of what the bar's active window widget elides: the app, the full
// title, and where the window is, on one card. Rows are separated by
// whitespace, not a rule or a dot (TASTE 10).
StyledPopup {
    id: root
    stickyHover: true

    property string appClass
    property string appTitle
    property string address // "" when there is no window to name
    property string monitorName
    property int workspaceId

    contentItem: Rectangle {
        id: card
        // At least 350 so a short title still reads as a card; capped at 600
        // so a long one wraps instead of spanning the screen.
        implicitWidth: Math.max(350, Math.min(600, titleMetrics.width + 32))
        implicitHeight: contentLayout.implicitHeight + 32
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainerHigh

        readonly property bool startAnim: root.opened
        onStartAnimChanged: {
            if (startAnim)
                enterAnim.restart();
        }

        ParallelAnimation {
            id: enterAnim
            CardEnter {
                card: header
                shift: headerShift
                slot: 0
            }
            CardEnter {
                card: title
                shift: titleShift
                slot: 1
            }
            CardEnter {
                card: footer
                shift: footerShift
                slot: 2
            }
        }

        TextMetrics {
            id: titleMetrics
            text: root.appTitle
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Medium
        }

        ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                id: header
                Layout.fillWidth: true
                spacing: 8
                transform: Translate {
                    id: headerShift
                }

                Rectangle {
                    color: Appearance.colors.colPrimaryContainer
                    radius: Appearance.rounding.verysmall
                    implicitWidth: classText.implicitWidth + 16
                    implicitHeight: classText.implicitHeight + 8
                    Layout.maximumWidth: contentLayout.width * 0.7

                    StyledText {
                        id: classText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.Layout.maximumWidth - 16)
                        elide: Text.ElideRight
                        text: root.appClass
                        font.weight: Font.Bold
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    visible: root.address.length > 0
                    text: root.address
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colSubtext
                }
            }

            StyledText {
                id: title
                Layout.fillWidth: true
                transform: Translate {
                    id: titleShift
                }
                text: root.appTitle
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurface
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }

            RowLayout {
                id: footer
                Layout.topMargin: 4
                spacing: 12
                transform: Translate {
                    id: footerShift
                }

                FooterItem {
                    icon: "computer"
                    text: root.monitorName
                }
                FooterItem {
                    icon: "grid_view"
                    text: `${Translation.tr("Workspace")} ${root.workspaceId}`
                }
            }
        }
    }

    component FooterItem: RowLayout {
        property string icon
        property string text
        spacing: 6

        MaterialSymbol {
            text: parent.icon
            iconSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtext
        }
        StyledText {
            text: parent.text
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
