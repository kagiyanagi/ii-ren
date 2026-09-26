import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

/**
 * A ListView with animations.
 */
ListView {
    id: root
    spacing: 4
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
     * back, and gets it again by scrolling to the end, or through `jumpToEnd()`
     * or `scrollToEnd()`, which is what the Scroll to Bottom button calls.
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
     * The contentY that puts the end of the list at the bottom of the view --
     * exact only while the last row is built, since `contentHeight` counts every
     * row the view has not built at the average height of the ones it has.
     */
    readonly property real endY: Math.max(root.originY - root.topMargin,
        root.originY + root.contentHeight + root.bottomMargin - root.height)

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
     * By item, and only once the last row is built. positionViewAtEnd() on a row
     * the view has not built throws every row away and rebuilds them around a
     * guess, and a transcript turn is built short: its text wraps a frame later,
     * when its layout hands it a width. The rebuilt row straddling the top of the
     * view then grew, shoved the end back out of the view and out of the cache,
     * and the follow pinned again -- a rebuild every other frame for as long as
     * the reader left it, contentY racing thousands of px at a time over a blank
     * view, until a scroll broke it off wherever it had got to.
     *
     * So an end that is not built is walked to, a page a frame: every row the
     * walk reaches is built at the bottom of the view and has settled before it
     * can push anything on screen. From far off, one jump first puts the walk two
     * pages short, and the rows that jump builds are behind the walk as they grow.
     */
    function jumpToEnd(): void {
        scrollAnim.complete();
        root.followingEnd = true;
        if (root.itemAtIndex(root.count - 1)) {
            endWalk.running = false;
            scrollBehavior.enabled = false;
            root.positionViewAtEnd();
            scrollBehavior.enabled = true;
        } else if (root.count > 0 && !endWalk.running) {
            if (root.endY - root.contentY > root.height * 2)
                root.moveContentY(root.endY - root.height * 2);
            endWalk.running = true;
        }
    }

    /**
     * The same, for the Scroll to Bottom button: on the programmatic scroll spec
     * while the end is built and close, at once otherwise. 200ms across a dozen
     * pages is a smear, and across rows the view has not built it is aimed at a
     * guess.
     */
    function scrollToEnd(): void {
        if (!root.itemAtIndex(root.count - 1) || root.endY - root.contentY > root.height * 2) {
            root.jumpToEnd();
            return;
        }
        root.followingEnd = true;
        root.contentY = root.endY;
    }

    function moveContentY(y: real): void {
        scrollBehavior.enabled = false;
        root.contentY = y;
        scrollBehavior.enabled = true;
    }

    FrameAnimation {
        id: endWalk
        onTriggered: {
            // Only ever on the reader's behalf, so their own scroll ends it.
            if (!root.followingEnd) {
                running = false;
                return;
            }
            if (root.itemAtIndex(root.count - 1)) {
                running = false;
                root.jumpToEnd();
                return;
            }
            const y = Math.min(root.contentY + root.height, root.endY);
            // Parked on the estimate: the next growth re-pins and walks again,
            // rather than a frame clock left running on nothing.
            if (Math.abs(y - root.contentY) < 1) {
                running = false;
                return;
            }
            root.moveContentY(y);
        }
    }

    // Not gated on `atYEnd`: Flickable emits this before it updates that, so
    // here it still says where the view was before the content grew, and a turn
    // that grew while the view sat on the end was left hanging below it.
    onContentHeightChanged: {
        if (root.followsEnd && root.followingEnd)
            Qt.callLater(root.jumpToEnd);
    }

    /*
     * A drag, a flick, or a wheel that Flickable handled itself -- the reader's
     * hand either way, so the follow goes, and comes back only if they left the
     * view at the end.
     *
     * Unconditionally: a reader who scrolls back is at the end when they start,
     * so asking `atYEnd` here refused to let go of the one case that matters.
     * `movementStarted` is the reader alone; the view's own positioning does not
     * raise it.
     */
    onMovementStarted: root.followingEnd = false
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

    // Opacity and scale are split because they are different kinds of motion:
    // the scale is spatial and is meant to overshoot, the fade is effects and
    // clips if it does -- on one shared spatial spec the row finished fading at
    // ~60% of the duration and then sat there (2.1, 10.6).
    add: Transition {
        animations: !root.animateAppearance ? [] : [
            Appearance?.animation.elementMoveFast.numberAnimation.createObject(this, {
                property: "opacity",
                from: 0,
                to: 1,
            }),
        ].concat(!root.popin ? [] : [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "scale",
                from: 0,
                to: 1,
            }),
        ])
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

    // Leaving is the exit spec, not the enter one: faster, and monotone, so the
    // fade does not dip past 0 and blank the row before the slide lands (2.5).
    remove: Transition {
        animations: animateAppearance ? [
            Appearance?.animation.elementMoveExit.numberAnimation.createObject(this, {
                property: "x",
                to: root.width + root.removeOvershoot,
            }),
            Appearance?.animation.elementMoveExit.numberAnimation.createObject(this, {
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
