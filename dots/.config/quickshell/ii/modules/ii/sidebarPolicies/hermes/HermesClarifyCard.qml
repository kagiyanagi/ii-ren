pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The agent's own question, from the `clarify` tool.
 *
 * The turn is parked until this is answered, so it is deliberately as loud as the
 * approval card. Choices come from the payload; a question with none takes a typed
 * answer instead, and one marked `multi_select` accumulates picks until confirmed.
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

    function toggleChoice(choice: string): void {
        root.selected = root.selected.includes(choice) ? root.selected.filter(item => item !== choice) : [...root.selected, choice];
    }

    implicitHeight: root.shown ? contentColumn.implicitHeight + 12 * 2 : 0
    opacity: root.shown ? 1 : 0
    visible: implicitHeight > 0
    clip: true

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    // Enter decelerating on spatial, exit accelerating at about half (DESIGN.md 2.5).
    Behavior on implicitHeight {
        NumberAnimation {
            duration: root.shown ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shown ? Appearance.animation.elementMoveEnter.bezierCurve : Appearance.animation.elementMoveExit.bezierCurve
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: root.shown ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
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

        FlowButtonGroup {
            Layout.fillWidth: true
            visible: root.choices.length > 0
            spacing: 4

            Repeater {
                model: root.choices

                delegate: RippleButton {
                    id: choiceButton
                    required property string modelData

                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    horizontalPadding: 16

                    toggled: root.selected.includes(choiceButton.modelData)
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover

                    releaseAction: () => {
                        // A single-choice question is answered by the press itself;
                        // a multi-select one collects until Confirm.
                        if (root.multiSelect)
                            root.toggleChoice(choiceButton.modelData);
                        else
                            root.answer(choiceButton.modelData);
                    }

                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: choiceButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer3
                        text: choiceButton.modelData
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
