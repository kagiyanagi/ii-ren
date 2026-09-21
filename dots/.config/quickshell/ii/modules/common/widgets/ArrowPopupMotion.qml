pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/**
 * AOSP Launcher3 `ArrowPopup.animateOpen()` / `animateClose()`, assembled once.
 *
 * `Appearance.animationCurves.arrowPopup*` names the parts and says they are
 * "assembled by each caller" -- and four callers did assemble them, by hand.
 * One of them grew an inline bezier that way; another ended up running its
 * enter and its exit on the same spatial spec, which is not an exit at all.
 * This is that assembly, in one place (`.audit/DECISIONS.md` 14).
 *
 * The caller still owns two things, because both are per-surface:
 *
 *  - `transformOrigin` on the target, set to whatever opened the popup before
 *    `open()` is called. A scale with the wrong origin is wrong however good
 *    the timing is (DESIGN.md 2.6).
 *  - the target's resting values, `scale: Appearance.animationCurves.arrowPopupScale`
 *    and `opacity: 0`, so a surface that survives a close animates from a known
 *    state next time rather than from stale ones (2.7).
 *
 *     ArrowPopupMotion {
 *         id: motion
 *         target: card
 *         onClosed: root.active = false
 *     }
 */
QtObject {
    id: root

    /** The surface that scales and fades. Its `transformOrigin` is the caller's. */
    property Item target: null

    /** Emitted when the close has *finished*, not when it was asked for. */
    signal closed

    function open(): void {
        closeAnim.stop();
        openAnim.restart();
    }

    function close(): void {
        openAnim.stop();
        closeAnim.restart();
    }

    // animateOpen(): the scale overshoots and settles on its own curve, with
    // alpha riding underneath over a fifth of the time.
    readonly property ParallelAnimation openAnim: ParallelAnimation {
        SequentialAnimation {
            NumberAnimation {
                target: root.target
                property: "scale"
                from: Appearance.animationCurves.arrowPopupScale
                to: Appearance.animationCurves.arrowPopupOvershoot
                duration: Appearance.animationCurves.arrowPopupScaleDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
            NumberAnimation {
                target: root.target
                property: "scale"
                to: 1
                duration: Appearance.animationCurves.arrowPopupScaleDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: Appearance.animationCurves.arrowPopupSettle
            }
        }
        NumberAnimation {
            target: root.target
            property: "opacity"
            from: 0
            to: 1
            duration: Appearance.animationCurves.arrowPopupFadeDuration
        }
    }

    // animateClose(): accelerating, and shorter than the open so leaving does
    // not read as entering played backwards (DESIGN.md 2.5). The hold plus the
    // fade is the close duration exactly.
    readonly property ParallelAnimation closeAnim: ParallelAnimation {
        NumberAnimation {
            target: root.target
            property: "scale"
            to: Appearance.animationCurves.arrowPopupScale
            duration: Appearance.animationCurves.arrowPopupCloseDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        SequentialAnimation {
            PauseAnimation {
                duration: Appearance.animationCurves.arrowPopupFadeHold
            }
            NumberAnimation {
                target: root.target
                property: "opacity"
                to: 0
                duration: Appearance.animationCurves.arrowPopupFadeDuration
            }
        }
        onFinished: root.closed()
    }
}
