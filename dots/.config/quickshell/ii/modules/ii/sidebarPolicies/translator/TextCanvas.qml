import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * One translator card: a text area over a row of actions. The host splits the
 * page between two of them, so the text scrolls inside the card, and the caret
 * keeps itself in view. The output is a text area too, read-only, so part of a
 * translation can be selected.
 */
Rectangle {
    id: root
    property bool isInput: true
    property string placeholderText
    // The output's text; the input's lives in `textArea`.
    property string text: ""
    property bool error: false
    property bool busy: false
    // An empty card with an icon shows it as a placeholder, as Hermes does.
    property string emptyIcon: ""
    property string emptyTitle: ""
    property string emptyDescription: ""
    readonly property alias textArea: textArea
    default property alias actionButtons: actions.groupData
    // Leads the action row: the character count, or what the output fixes.
    property Component leading: null
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            TextArea.flickable: StyledTextArea {
                id: textArea
                readOnly: !root.isInput
                selectByMouse: true
                text: root.text
                placeholderText: root.placeholderText
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                color: root.error ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                padding: 16
                background: null
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 8
            spacing: 8

            Loader {
                Layout.preferredHeight: 40
                active: root.leading !== null
                visible: active
                sourceComponent: root.leading
            }
            Item { Layout.fillWidth: true }
            ButtonGroup {
                id: actions
            }
        }
    }

    PagePlaceholder {
        shown: root.emptyIcon.length > 0 && root.text.length === 0
        icon: root.emptyIcon
        shape: MaterialShape.Shape.Cookie12Sided
        rotateIconWithShape: true
        title: root.emptyTitle
        description: root.emptyDescription
        descriptionHorizontalAlignment: Text.AlignHCenter
        triggerAnimationOn: GlobalStates.policiesPanelOpen
        rotateToRight: GlobalStates.policiesOnLeft
    }

    // Enter on the fast effects spec, leave on the exit one, each assigned
    // inside the binding that fades (DESIGN.md 2.9).
    Loader {
        id: progress
        property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 4
            leftMargin: 16
            rightMargin: 16
        }
        opacity: {
            progress.fadeSpec = root.busy ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
            return root.busy ? 1 : 0;
        }
        active: opacity > 0
        visible: active
        Behavior on opacity {
            NumberAnimation {
                duration: progress.fadeSpec.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: progress.fadeSpec.bezierCurve
            }
        }
        sourceComponent: StyledIndeterminateProgressBar {}
    }
}
