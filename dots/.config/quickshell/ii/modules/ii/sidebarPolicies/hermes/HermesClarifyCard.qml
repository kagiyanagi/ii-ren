pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The agent's own question, from the `clarify` tool.
 *
 * The turn is parked until this is answered, so it is deliberately as loud as the
 * approval card. Choices come from the payload; a question with none takes a typed
 * answer instead, and one marked `multi_select` accumulates picks until confirmed.
 *
 * An M3 single- or multi-choice dialog laid inline: the choices are full-width
 * rows, a single choice answers on press, a multi-select row toggles its check.
 */
Rectangle {
    id: root

    required property var request

    readonly property bool shown: root.request !== null && root.request !== undefined

    // The request clears the instant it is answered, which would empty the card
    // mid-exit. Render from the last real one so the collapse animates on content.
    property var latched: null
    onRequestChanged: {
        if (root.shown) {
            root.latched = root.request;
            // A replaced batch starts at its first question, not where the
            // last one was left.
            root.questionIndex = 0;
            root.selected = [];
            answerField.text = "";
        }
    }

    // A batch asks several at once; this walks them one at a time.
    readonly property var questions: root.latched?.questions ?? []
    readonly property bool isBatch: root.questions.length > 0
    property int questionIndex: 0
    readonly property var current: root.isBatch ? (root.questions[root.questionIndex] ?? null) : root.latched

    readonly property string questionText: root.current?.question ?? ""
    readonly property var choices: root.current?.choices ?? []
    readonly property bool multiSelect: root.current?.multi_select ?? false
    readonly property string questionId: root.isBatch ? (root.current?.qid ?? "") : ""

    property var selected: []

    function answer(text: string): void {
        HermesService.respondToClarify(text, root.questionId);
        if (root.isBatch && root.questionIndex < root.questions.length - 1) {
            root.questionIndex++;
            root.selected = [];
            answerField.text = "";
        } else {
            root.questionIndex = 0;
        }
    }

    // A question with nothing to pick is answered by typing, so the caret goes
    // there. Visibility is checked because focus cannot land on a card that has
    // not started to open.
    function focusIfTyped(): void {
        if (root.visible && root.choices.length === 0)
            answerField.forceActiveFocus();
    }
    onCurrentChanged: root.focusIfTyped()
    onVisibleChanged: root.focusIfTyped()

    function toggleChoice(choice: string): void {
        root.selected = root.selected.includes(choice) ? root.selected.filter(item => item !== choice) : [...root.selected, choice];
    }

    property AnimSpec implicitHeightSpec: Appearance.animation.elementMoveEnter
    implicitHeight: {
        root.implicitHeightSpec = root.shown ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit;
        return root.shown ? contentColumn.implicitHeight + 12 * 2 : 0;
    }
    property AnimSpec opacitySpec: Appearance.animation.elementMoveFast
    opacity: {
        root.opacitySpec = root.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
        return root.shown ? 1 : 0;
    }
    visible: implicitHeight > 0
    clip: true

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    // Enter decelerating on spatial, exit accelerating at about half (DESIGN.md 2.5).
    Behavior on implicitHeight {
        NumberAnimation {
            duration: root.implicitHeightSpec.duration
            easing.type: root.implicitHeightSpec.type
            easing.bezierCurve: root.implicitHeightSpec.bezierCurve
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: root.opacitySpec.duration
            easing.type: root.opacitySpec.type
            easing.bezierCurve: root.opacitySpec.bezierCurve
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colPrimary
                text: "help"
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer2
                text: root.isBatch ? Translation.tr("Hermes is asking (%1 of %2)").arg(root.questionIndex + 1).arg(root.questions.length) : Translation.tr("Hermes is asking")
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer2
            text: root.questionText
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.choices.length > 0
            spacing: 4

            Repeater {
                model: root.choices

                delegate: RippleButton {
                    id: choiceButton
                    required property string modelData

                    Layout.fillWidth: true
                    implicitHeight: Math.max(40, choiceRow.implicitHeight + 8 * 2)
                    buttonRadius: Appearance.rounding.small

                    // Picked rows of a multi-select take the secondary container,
                    // the M3 selected-list-item colour; the rest sit a layer up.
                    toggled: root.multiSelect && root.selected.includes(choiceButton.modelData)
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colBackgroundActive: Appearance.colors.colLayer3Active
                    colRipple: Appearance.colors.colLayer3Active
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    colStateLayer: choiceButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3

                    releaseAction: () => {
                        if (root.multiSelect)
                            root.toggleChoice(choiceButton.modelData);
                        else
                            root.answer(choiceButton.modelData);
                    }

                    contentItem: RowLayout {
                        id: choiceRow
                        spacing: 12

                        MaterialSymbol {
                            Layout.leftMargin: 12
                            Layout.alignment: Qt.AlignVCenter
                            visible: root.multiSelect
                            text: choiceButton.toggled ? "check_box" : "check_box_outline_blank"
                            fill: choiceButton.toggled ? 1 : 0
                            iconSize: Appearance.font.pixelSize.larger
                            color: choiceButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.leftMargin: root.multiSelect ? 0 : 16
                            Layout.rightMargin: 16
                            Layout.alignment: Qt.AlignVCenter
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: choiceButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                            text: choiceButton.modelData
                        }
                    }
                }
            }
        }

        RowLayout { // Typed answer, and Confirm for a multi-select
            Layout.fillWidth: true
            spacing: 8

            MaterialTextField {
                id: answerField
                Layout.fillWidth: true
                visible: !root.multiSelect
                placeholderText: root.choices.length > 0 ? Translation.tr("…or type an answer") : Translation.tr("Type an answer")
                onAccepted: {
                    if (text.trim().length > 0)
                        root.answer(text.trim());
                }
            }

            RippleButton {
                id: confirmButton
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                horizontalPadding: 16
                toggled: true

                enabled: root.multiSelect ? root.selected.length > 0 : answerField.text.trim().length > 0

                releaseAction: () => {
                    if (root.multiSelect)
                        root.answer(root.selected.join(", "));
                    else if (answerField.text.trim().length > 0)
                        root.answer(answerField.text.trim());
                }

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onPrimary
                    text: Translation.tr("Send")
                }
            }
        }
    }
}
