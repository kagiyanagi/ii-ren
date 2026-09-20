import qs.modules.common
import QtQuick

/**
 * Recreation of GTK revealer. Expects one single child.
 */
Item {
    id: root
    property bool reveal
    property bool vertical: false
    clip: true

    /**
     * Opening is the default spatial spec and may overshoot; closing is the
     * fast effects one, monotone and a quarter as long, so the size does not
     * dip below zero on the way out (2.5). Interruptible either way: reveal is
     * a toggle, so a reversal has to cut in (2.7).
     *
     * Assigned from inside the size bindings, which looks backwards and is the
     * only order that holds. A Behavior bakes its animation's duration and
     * curve at the instant the binding writes its property, and *other*
     * bindings on `reveal` have not necessarily been re-evaluated by then --
     * traced, `opacity`'s binding beat a spec property declared above it. Read
     * from a binding of its own, the exit therefore ran on the enter's curve:
     * measured on an 80px child, a 500ms collapse undershooting to -1.11
     * instead of 130ms monotone. Doing it here cannot be stale, because this
     * runs before the write that starts the animation. DESIGN.md 2.9.
     */
    property AnimSpec revealSpec: Appearance.animation.elementMove

    function pickRevealSpec(): void {
        root.revealSpec = root.reveal ? Appearance.animation.elementMove : Appearance.animation.elementMoveExit;
    }

    implicitWidth: {
        root.pickRevealSpec();
        return (root.reveal || root.vertical) ? root.childrenRect.width : 0;
    }
    implicitHeight: {
        root.pickRevealSpec();
        return (root.reveal || !root.vertical) ? root.childrenRect.height : 0;
    }
    visible: reveal || (implicitWidth > 0 && !vertical) || (implicitHeight > 0 && vertical)

    Behavior on implicitWidth {
        enabled: !root.vertical
        RevealAnim {}
    }
    Behavior on implicitHeight {
        enabled: root.vertical
        RevealAnim {}
    }

    component RevealAnim: NumberAnimation {
        alwaysRunToEnd: false
        duration: root.revealSpec.duration
        easing.type: root.revealSpec.type
        easing.bezierCurve: root.revealSpec.bezierCurve
    }
}
