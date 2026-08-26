pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick

// Drop over any interactive content and bind the states you care about. Each
// layer fades independently, so hover -> press -> release stays continuous.
Rectangle {
    id: root

    property bool hover: false
    // Not named "focus": that is Item's own keyboard focus property, and binding a
    // visible tint to it fires on focus changes nothing asked for.
    property bool focused: false
    property bool press: false
    property bool drag: false

    property color contentColor: Appearance.m3colors.m3onBackground

    color: "transparent"

    Repeater {
        model: [
            {
                shown: root.hover,
                state: StateLayer.State.Hover
            },
            {
                shown: root.focused,
                state: StateLayer.State.Focus
            },
            {
                shown: root.press,
                state: StateLayer.State.Press
            },
            {
                shown: root.drag,
                state: StateLayer.State.Drag
            }
        ]

        delegate: FadeLoader {
            required property var modelData

            anchors.fill: parent
            shown: modelData.shown

            sourceComponent: StateLayer {
                layerState: modelData.state
                color: root.contentColor
                topLeftRadius: root.topLeftRadius
                topRightRadius: root.topRightRadius
                bottomLeftRadius: root.bottomLeftRadius
                bottomRightRadius: root.bottomRightRadius
            }
        }
    }
}
