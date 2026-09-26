pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A reasoning block: one colLayer3 card whose whole header is the button that
 * folds the thought open, once there is a finished one to read.
 *
 * No layer or OpacityMask. A layered item is skipped by Qt's cursor walk while
 * still receiving hover, so the header highlighted but never showed a pointing
 * hand. The fold crops through Revealer's own clip.
 */
Rectangle {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: true
    property var segmentContent: ({})
    // `{}` parses as an empty block, not an empty object, so this was undefined
    // and every read of it threw -- same fix as MessageTextBlock.qml.
    property var messageData: null
    property bool done: true
    property bool completed: false

    // Starts folded: the answer is what the turn is for, and the thought is kept
    // behind one line until asked for.
    property bool expanded: false

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer3

    FontMetrics {
        id: readingMetrics
        font.family: Appearance.font.family.reading
        font.pixelSize: Appearance.font.pixelSize.small
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        RippleButton {
            id: header
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + 8 * 2
            enabled: root.completed
            // Not disabled, just nothing to open yet: the 0.4 of a disabled
            // control (DESIGN.md 3.1) would dim the indicator saying it is working.
            opacity: 1
            buttonRadius: root.radius
            // Square under an open thought, so the film meets the body it opened.
            bottomLeftRadius: root.expanded ? Appearance.rounding.unsharpen : root.radius
            bottomRightRadius: root.expanded ? Appearance.rounding.unsharpen : root.radius
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            colStateLayer: Appearance.colors.colOnLayer3
            onClicked: root.expanded = !root.expanded

            RowLayout {
                id: headerRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                // Stands in for the icon while the model is still thinking, so
                // the label never has to fake motion with dots.
                MaterialLoadingIndicator {
                    visible: !root.completed
                    implicitSize: 20
                    loading: visible
                }
                MaterialSymbol {
                    visible: root.completed
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer3
                    text: "linked_services"
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    color: Appearance.colors.colOnLayer3
                    text: root.completed ? Translation.tr("Thought") : Translation.tr("Thinking")
                }
                MaterialSymbol {
                    visible: root.completed
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer3
                    text: "keyboard_arrow_down"
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }
        }

        Revealer {
            Layout.fillWidth: true
            vertical: true
            reveal: root.expanded

            // Set on the block itself, not as same-named properties on a wrapper:
            // bindings inside MessageTextBlock.qml resolve in that file's own
            // scope, so forwarding through a wrapper once ran the inner text with
            // `messageData: {}` and logged a TypeError on every think block.
            // A long thought stops at a dozen lines until asked for, so opening one
            // does not push the answer a screen away.
            ClampBox {
                width: parent.width
                height: implicitHeight + 8
                maxHeight: readingMetrics.lineSpacing * 12
                colBase: Appearance.colors.colLayer3
                colHover: Appearance.colors.colLayer3Hover
                colActive: Appearance.colors.colLayer3Active

                MessageTextBlock {
                    width: parent.width
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
