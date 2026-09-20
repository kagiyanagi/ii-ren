import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    Layout.alignment: Qt.AlignLeft
    implicitWidth: 40
    implicitHeight: 40
    Layout.leftMargin: 8
    downAction: () => {
        parent.expanded = !parent.expanded;
    }
    buttonRadius: Appearance.rounding.full
    property bool _isInitialized: false
    Component.onCompleted: _isInitialized = true

    /*
     * Rotation is spatial (2.1) and the two directions are not the same move
     * (2.5): the rail opening is a surface arriving, closing is one leaving at
     * about a quarter the length. It was one effects spec for both. The spec is
     * assigned from inside the binding that drives the rotation, because a
     * Behavior reading it from a binding of its own bakes whichever value is
     * current when the write lands -- DESIGN.md 2.9, Revealer is the example.
     */
    property AnimSpec turnSpec: Appearance.animation.elementMove
    rotation: {
        root.turnSpec = root.parent.expanded ? Appearance.animation.elementMove : Appearance.animation.elementMoveExit;
        return root.parent.expanded ? 0 : -180;
    }

    Behavior on rotation {
        enabled: root._isInitialized

        NumberAnimation {
            duration: root.turnSpec.duration
            easing.type: root.turnSpec.type
            easing.bezierCurve: root.turnSpec.bezierCurve
        }
    }

    contentItem: MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        iconSize: 24
        color: Appearance.colors.colOnLayer1
        text: root.parent.expanded ? "menu_open" : "menu"
    }
}
