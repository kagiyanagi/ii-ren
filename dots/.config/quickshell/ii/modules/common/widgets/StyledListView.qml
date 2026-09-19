import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

/**
 * A ListView with animations.
 */
ListView {
    id: root
    spacing: 5
    property real removeOvershoot: 20 // Account for gaps and bouncy animations
    property int dragIndex: -1
    property real dragDistance: 0
    property bool popin: true
    property bool animateAppearance: true
    property bool animateMovement: false

    property alias scrollTargetY: wheelHandler.scrollTargetY
    property alias touchpadScrollFactor: wheelHandler.touchpadScrollFactor
    property alias mouseScrollFactor: wheelHandler.mouseScrollFactor
    property alias mouseScrollDeltaThreshold: wheelHandler.mouseScrollDeltaThreshold

    function resetDrag() {
        root.dragIndex = -1
        root.dragDistance = 0
    }

    /**
     * Keeps the end of the list under the view as content grows into it -- a
     * transcript during a streamed reply. Opt in with `followsEnd`.
     *
     * `followingEnd` is the live state: the reader takes it away by scrolling
     * back, and gets it again by scrolling to the end, or through `jumpToEnd()`,
     * which is what the Scroll to Bottom button calls.
     *
     * Decided from what the reader did, never from where the view ended up. A
     * view that recycles delegates moves contentY itself once it has laid one
     * out and can measure it, and re-estimates `contentHeight` as it goes, so
     * both of those -- and `atYEnd`, which is built from them -- wander on their
     * own while a reply streams. Reading any of them as intent dropped the
     * follow a frame after every jump to the end, and yanked a reader who was
     * scrolling back through a long answer down to the bottom again.
     */
    property bool followsEnd: false
    property bool followingEnd: true

    /**
     * Puts the end of the list at the bottom of the view, at once.
     *
     * A view that follows streamed content re-pins every time that content
     * grows. Letting each of those pins animate over `scroll.duration` -- which
     * `alwaysRunToEnd` will not cut short -- leaves it chasing a bottom it never
     * reaches, and permanently mid-animation. A scroll already in flight is
     * landed first, or it would go on dragging the view back to wherever it was
     * aimed for the rest of its duration.
     *
     * By item, not by contentY: `contentHeight` is an estimate for delegates the
     * view has not laid out, so from far up the list a computed contentY lands
     * past the real end, on nothing.
     */
    function jumpToEnd(): void {
        scrollAnim.complete();
        scrollBehavior.enabled = false;
        root.positionViewAtEnd();
        scrollBehavior.enabled = true;
        root.followingEnd = true;
    }

    onContentHeightChanged: {
        if (root.followsEnd && root.followingEnd && !root.atYEnd)
            Qt.callLater(root.jumpToEnd);
    }

    // A drag or a flick, which is the reader's hand either way.
    onMovementStarted: {
        if (!root.atYEnd)
            root.followingEnd = false;
    }
    onMovementEnded: {
        if (root.atYEnd)
            root.followingEnd = true;
    }

    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds
    ScrollBar.vertical: StyledScrollBar {
        onPressedChanged: {
            if (pressed && !root.atYEnd)
                root.followingEnd = false;
            else if (!pressed && root.atYEnd)
                root.followingEnd = true;
        }
    }

    WheelScrollHandler {
        id: wheelHandler
        flickable: root
        scrollAnim: scrollAnim

        // The clamp has already worked out whether this turn asked for the very
        // end, against the same extent it scrolled to, so re-attaching needs no
        // allowance for how far that end moved while the scroll played out.
        onScrolled: (up, toEnd) => {
            if (up)
                root.followingEnd = false;
            else if (toEnd)
                root.followingEnd = true;
        }
    }

    Behavior on contentY {
        id: scrollBehavior
        NumberAnimation {
            id: scrollAnim
            alwaysRunToEnd: true
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
        }
    }

    onContentYChanged: wheelHandler.syncTarget()

    // Android-style stretch overscroll: a uniform scale anchored at the far edge, which is
    // the 1:1 anchor in Android's StretchEffect. Transform only, so no layer, no FBO and no
    // shader -- yScale is 1 at rest, so this costs nothing until something overscrolls.
    contentItem.transform: Scale {
        origin.y: wheelHandler.overscroll < 0 ? root.contentY + root.height : root.contentY
        yScale: 1 + Math.abs(wheelHandler.overscroll) / Math.max(1, root.height)
    }

    add: Transition {
        animations: animateAppearance ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: popin ? "opacity,scale" : "opacity",
                from: 0,
                to: 1,
            }),
        ] : []
    }

    addDisplaced: Transition {
        animations: animateAppearance ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: popin ? "opacity,scale" : "opacity",
                to: 1,
            }),
        ] : []
    }
    
    displaced: Transition {
        animations: root.animateMovement ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: "opacity,scale",
                to: 1,
            }),
        ] : []
    }

    move: Transition {
        animations: root.animateMovement ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: "opacity,scale",
                to: 1,
            }),
        ] : []
    }
    moveDisplaced: Transition {
        animations: root.animateMovement ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: "opacity,scale",
                to: 1,
            }),
        ] : []
    }

    remove: Transition {
        animations: animateAppearance ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "x",
                to: root.width + root.removeOvershoot,
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "opacity",
                to: 0,
            })
        ] : []
    }

    // This is movement when something is removed, not removing animation!
    removeDisplaced: Transition { 
        animations: animateAppearance ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: "opacity,scale",
                to: 1,
            }),
        ] : []
    }
}
