pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The consent prompt Hermes parks a turn on before running something it will not
 * run unasked.
 *
 * The gateway decides which scopes are on offer (a Smart-DENY override drops
 * "session" and "always"), so the buttons come from `choices` rather than being
 * hardcoded here. Silence is not consent upstream -- the turn stays blocked until
 * this is answered or it times out -- so the card is deliberately loud.
 */
Rectangle {
    id: root

    required property var request

    readonly property bool shown: root.request !== null && root.request !== undefined

    // The request goes null the instant it is answered, which would empty the card
    // mid-exit. Render from the last real one so the collapse animates on content
    // that is still there.
    property var latchedRequest: null
    onRequestChanged: {
        if (root.shown)
            root.latchedRequest = root.request;
    }

    readonly property var choices: root.latchedRequest?.choices ?? ["once", "deny"]
    readonly property string command: root.latchedRequest?.command ?? ""
    readonly property string description: root.latchedRequest?.description ?? ""

    function labelFor(choice: string): string {
        switch (choice) {
        case "once":
            return Translation.tr("Allow once");
        case "session":
            return Translation.tr("Allow this session");
        case "always":
            return Translation.tr("Always allow");
        case "deny":
            return Translation.tr("Deny");
        }
        return choice;
    }

    implicitHeight: root.shown ? contentColumn.implicitHeight + 12 * 2 : 0
    opacity: root.shown ? 1 : 0
    visible: implicitHeight > 0
    clip: true

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    // Enter decelerating on spatial, exit accelerating at about half the duration
    // (DESIGN.md 2.5). Height is spatial and may overshoot; opacity is effects and
    // must not, so the two run on different specs.
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
                color: Appearance.m3colors.m3error
                text: "gpp_maybe"
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer2
                text: Translation.tr("Hermes wants to run something")
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: root.description.length > 0
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: root.description
        }

        Rectangle { // The command itself, verbatim
            Layout.fillWidth: true
            visible: root.command.length > 0
            implicitHeight: commandText.implicitHeight + 8 * 2
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer3

            StyledText {
                id: commandText
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 8
                }
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colOnLayer3
                text: root.command
            }
        }

        FlowButtonGroup {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.choices

                delegate: RippleButton {
                    id: choiceButton
                    required property string modelData

                    readonly property bool destructive: choiceButton.modelData === "deny"

                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    horizontalPadding: 16

                    // "once" is the safe default, so it carries the filled emphasis.
                    toggled: choiceButton.modelData === "once"
                    colBackground: choiceButton.destructive ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer3
                    colBackgroundHover: choiceButton.destructive ? Appearance.colors.colErrorContainerHover : Appearance.colors.colLayer3Hover
                    colBackgroundActive: choiceButton.destructive ? Appearance.colors.colErrorContainerActive : Appearance.colors.colLayer3Active

                    releaseAction: () => HermesService.respondToApproval(choiceButton.modelData)

                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: choiceButton.destructive ? Appearance.m3colors.m3onErrorContainer : choiceButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer3
                        text: root.labelFor(choiceButton.modelData)
                    }
                }
            }
        }
    }
}
