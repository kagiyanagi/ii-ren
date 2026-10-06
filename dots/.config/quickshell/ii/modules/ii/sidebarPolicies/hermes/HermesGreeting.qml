pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import QtQuick
import QtQuick.Layouts
import "greeting.js" as Greeting

/**
 * The Hermes tab before the first message. The Hermes mark, a greeting for
 * the hour with the user's name on a line of its own in the page's one accent,
 * a question, then ways to start: the window you were in, what you copied, a
 * shell command, the command list. Centred and set low, so the eye ends just
 * above the composer it is about to use.
 *
 * Every open replays the entrance: the lines rise in one after another (2.8)
 * while the mark turns into place and the name's weight swells to rest. Leaving is a plain fade (2.5).
 */
Item {
    id: root

    property bool shown: true
    // "appId — title" of the window `@window` will name, or empty.
    property string windowName: ""
    property string commandPrefix: "/"

    // A starter lands in the composer rather than being sent: each one opens a
    // question that only the user can finish.
    signal compose(string text)
    signal quote(string text)

    // Read once per open, so a chip never changes under the pointer.
    property string clip: ""
    readonly property string windowTitle: {
        const cut = root.windowName.indexOf(" — ");
        const title = cut >= 0 ? root.windowName.slice(cut + 3).trim() : "";
        return title.length > 0 ? title : (cut >= 0 ? root.windowName.slice(0, cut) : root.windowName);
    }

    readonly property date now: DateTime.clock.date
    readonly property var parts: Greeting.parts(root.now, Greeting.displayName(SystemInfo.username))

    // The name is set heavier than the line before it, so it still stands out
    // under a near-grey palette where the accent alone barely shows. It swells
    // from body weight to twice title's step above it: 450 to 650.
    readonly property real bodyWeight: Appearance.font.variableAxes.main.wght
    readonly property real nameWeight: root.bodyWeight + 2 * (Appearance.font.variableAxes.title.wght - root.bodyWeight)
    property real swell: 1

    function replay(): void {
        if (!root.shown)
            return;
        root.clip = (Quickshell.clipboardText ?? "").trim();
        entrance.restart();
    }

    readonly property bool panelOpen: GlobalStates.policiesPanelOpen
    onPanelOpenChanged: {
        if (root.panelOpen)
            root.replay();
    }
    onShownChanged: root.replay()

    property AnimSpec opacitySpec: Appearance.animation.elementMoveFast
    opacity: {
        root.opacitySpec = root.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
        return root.shown ? 1 : 0;
    }
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation {
            duration: root.opacitySpec.duration
            easing.type: root.opacitySpec.type
            easing.bezierCurve: root.opacitySpec.bezierCurve
        }
    }

    // One line's way in: held for its place in the queue, then risen on the
    // spatial spec while it fades up on the effects one (2.3).
    component Rise: SequentialAnimation {
        id: rise
        required property Item line
        required property Translate shift
        property int order: 0

        PauseAnimation {
            duration: rise.order * Appearance.animation.staggerStep
        }
        ParallelAnimation {
            NumberAnimation {
                target: rise.shift
                property: "y"
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            NumberAnimation {
                target: rise.line
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
    }

    SequentialAnimation {
        id: entrance
        ScriptAction {
            script: {
                for (const line of [mark, leadLine, nameLine, promptLine, starters]) {
                    line.opacity = 0;
                    line.transform[0].y = 16;
                }
                mark.rotation = -70;
                root.swell = 0;
            }
        }
        ParallelAnimation {
            Rise { line: mark; shift: markShift; order: 0 }
            NumberAnimation { // The turn the empty page's mark always made: a transform, so spatial
                target: mark
                property: "rotation"
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            Rise { line: leadLine; shift: leadShift; order: 1 }
            Rise { line: nameLine; shift: nameShift; order: 2 }
            Rise { line: promptLine; shift: promptShift; order: 3 }
            Rise { line: starters; shift: startersShift; order: 4 }
            NumberAnimation {
                target: root
                property: "swell"
                to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
    }

    // A tonal chip, the composer's own suggestion chips' layer, with a glyph for
    // what it starts.
    component Starter: RippleButton {
        id: starter
        property string symbol
        property string label
        signal picked()

        width: Math.min(implicitWidth, starters.width)
        implicitHeight: 32
        horizontalPadding: 12
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        releaseAction: () => starter.picked()

        contentItem: RowLayout {
            spacing: 8
            MaterialSymbol {
                text: starter.symbol
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: starter.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
        }
    }

    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: parent.height / 32
            leftMargin: 24
            rightMargin: 24
        }
        spacing: 0

        MaterialShapeWrappedMaterialSymbol {
            id: mark
            Layout.alignment: Qt.AlignHCenter
            transform: Translate { id: markShift }
            text: "auto_awesome"
            shape: MaterialShape.Shape.PixelCircle
            rotateIconWithShape: true
            padding: 12
            iconSize: 56
        }

        StyledText {
            id: leadLine
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.topMargin: 24
            transform: Translate { id: leadShift }
            wrapMode: Text.Wrap
            text: root.parts.lead
            color: Appearance.colors.colOnLayer1
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.display
            font.variableAxes: ({ "wght": root.bodyWeight })
        }

        StyledText {
            id: nameLine
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: root.parts.name.length > 0
            transform: Translate { id: nameShift }
            elide: Text.ElideRight
            text: root.parts.name
            color: Appearance.colors.colPrimary
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.display
            font.variableAxes: ({ "wght": root.bodyWeight + (root.nameWeight - root.bodyWeight) * root.swell })
        }

        StyledText {
            id: promptLine
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.topMargin: 16
            transform: Translate { id: promptShift }
            wrapMode: Text.Wrap
            text: Greeting.subtitle(root.now)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.huge
        }

        Flow {
            id: starters
            Layout.fillWidth: true
            Layout.topMargin: 32
            transform: Translate { id: startersShift }
            spacing: 8
            // Flow only packs left; centre each row once it has placed them.
            onPositioningComplete: {
                const rows = {};
                for (const c of starters.children)
                    if (c.visible)
                        (rows[c.y] = rows[c.y] ?? []).push(c);
                for (const row of Object.values(rows)) {
                    const last = row[row.length - 1];
                    const shift = (starters.width - (last.x + last.width - row[0].x)) / 2;
                    for (const c of row)
                        c.x += shift;
                }
            }

            Starter {
                visible: root.windowTitle.length > 0
                symbol: "select_window"
                label: Translation.tr("Ask about %1").arg(root.windowTitle)
                onPicked: root.compose("@window ")
            }
            Starter {
                visible: root.clip.length > 0
                symbol: "content_paste"
                label: Translation.tr("Ask about what I copied")
                onPicked: root.quote(root.clip)
            }
            Starter {
                symbol: "terminal"
                label: Translation.tr("Run a command")
                onPicked: root.compose("!")
            }
            Starter {
                symbol: "bolt"
                label: Translation.tr("Commands")
                onPicked: root.compose(root.commandPrefix)
            }
        }
    }
}
