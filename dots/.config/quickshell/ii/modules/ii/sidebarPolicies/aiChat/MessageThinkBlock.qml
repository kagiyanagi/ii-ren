pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: true
    property var segmentContent: ({})
    property var messageData: {}
    property bool done: true
    property bool completed: false

    property real thinkBlockBackgroundRounding: Appearance.rounding.small
    property real thinkBlockHeaderPaddingVertical: 3
    property real thinkBlockHeaderPaddingHorizontal: 10
    property real thinkBlockComponentSpacing: 2

    property var collapseAnimation: messageTextBlock.implicitHeight > 40 ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveFast
    property bool collapsed: true /* should be root.completed but its kinda buggy rn so nope */

    Layout.fillWidth: true
    implicitHeight: collapsed ? header.implicitHeight : columnLayout.implicitHeight
    // No layer/OpacityMask. A layered item is skipped by Qt's cursor walk while
    // still receiving hover, so the reveal header and expand button highlighted
    // but never showed a pointing hand. The corners are rounded on the header
    // and content rectangles themselves instead, like MessageCodeBlock, and the
    // collapse crop was already done by `clip: true` on the content item.

    Behavior on implicitHeight {
        enabled: root.completed ?? false
        NumberAnimation {
            duration: collapseAnimation.duration
            easing.type: collapseAnimation.type
            easing.bezierCurve: collapseAnimation.bezierCurve
        }
    }

    ColumnLayout {
        id: columnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        Rectangle { // Header background
            id: header
            color: Appearance.colors.colSurfaceContainerHighest
            topLeftRadius: thinkBlockBackgroundRounding
            topRightRadius: thinkBlockBackgroundRounding
            bottomLeftRadius: Appearance.rounding.unsharpen
            bottomRightRadius: Appearance.rounding.unsharpen
            Layout.fillWidth: true
            implicitHeight: thinkBlockTitleBarRowLayout.implicitHeight + thinkBlockHeaderPaddingVertical * 2

            MouseArea { // Click to reveal
                id: headerMouseArea
                enabled: root.completed
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    root.collapsed = !root.collapsed
                }
            }

            RowLayout { // Header content
                id: thinkBlockTitleBarRowLayout
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: thinkBlockHeaderPaddingHorizontal
                anchors.rightMargin: thinkBlockHeaderPaddingHorizontal
                spacing: 10

                MaterialSymbol {
                    Layout.fillWidth: false
                    Layout.topMargin: 7
                    Layout.bottomMargin: 7
                    Layout.leftMargin: 3
                    text: "linked_services"
                }
                StyledText {
                    id: thinkBlockLanguage
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignLeft
                    text: root.completed ? Translation.tr("Thought") : (Translation.tr("Thinking") + ".".repeat(Math.random() * 4))
                }
                Item { Layout.fillWidth: true }
                RippleButton { // Expand button
                    id: expandButton
                    visible: root.completed
                    implicitWidth: 22
                    implicitHeight: 22
                    colBackground: headerMouseArea.containsMouse ? Appearance.colors.colLayer2Hover
                        : ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active

                    onClicked: { root.collapsed = !root.collapsed }
                    
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "keyboard_arrow_down"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                        rotation: root.collapsed ? 0 : 180
                        Behavior on rotation {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }

                }
                
            }

        }

        Item {
            id: content
            Layout.fillWidth: true
            implicitHeight: collapsed ? 0 : contentBackground.implicitHeight + thinkBlockComponentSpacing
            clip: true

            Behavior on implicitHeight {
                enabled: root.completed ?? false
                NumberAnimation {
                    duration: collapseAnimation.duration
                    easing.type: collapseAnimation.type
                    easing.bezierCurve: collapseAnimation.bezierCurve
                }
            }

            Rectangle {
                id: contentBackground
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: messageTextBlock.implicitHeight
                color: Appearance.colors.colLayer2
                topLeftRadius: Appearance.rounding.unsharpen
                topRightRadius: Appearance.rounding.unsharpen
                bottomLeftRadius: thinkBlockBackgroundRounding
                bottomRightRadius: thinkBlockBackgroundRounding

                // Set on the block itself, not as same-named properties out here:
                // bindings inside MessageTextBlock.qml resolve in that file's own
                // scope, so declaring them on this Rectangle forwarded nothing and
                // the inner text ran with `messageData: {}` -- which is what logged
                // "Cannot read property 'done' of undefined" on every think block.
                MessageTextBlock {
                    id: messageTextBlock
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    segmentContent: root.segmentContent
                    editing: root.editing
                    renderMarkdown: root.renderMarkdown
                    enableMouseSelection: root.enableMouseSelection
                    messageData: root.messageData
                    done: root.done
                }
            }
        }
    }
}
