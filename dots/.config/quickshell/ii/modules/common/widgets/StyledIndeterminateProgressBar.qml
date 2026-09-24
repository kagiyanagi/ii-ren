pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import QtQuick.Controls

/**
 * Material 3 indeterminate linear progress indicator.
 *
 * This used to be three lines: a bare ProgressBar with `Material.accent`. The
 * shell runs on `QT_QUICK_CONTROLS_STYLE=Basic` (see shell.qml), where that
 * attached property is inert and the Basic delegate paints `palette.dark` on
 * `palette.midlight` - Qt's greys, on Qt's own block animation, with nothing
 * from Appearance and nothing from M3 in either.
 *
 * The two-segment sweep below is transcribed from AOSP `ProgressIndicator.kt`
 * (`LinearAnimationDuration` and the four head/tail windows). Each segment
 * spans [tail, head]; both endpoints run 0 -> 1 over their own window on
 * EasingEmphasizedAccelerateCubicBezier, and the head leads, so the segment
 * grows out of the left edge and is swallowed by the right.
 *
 * Determinate progress is `StyledProgressBar`. DESIGN.md 9: reach for this only
 * when the duration is genuinely unknown.
 */
ProgressBar {
    id: root
    indeterminate: true

    property real valueBarWidth: 120
    property real valueBarHeight: 4
    property color highlightColor: Appearance?.colors.colPrimary ?? "#685496"
    property color trackColor: Appearance?.m3colors.m3secondaryContainer ?? "#F1D3F9"

    // AOSP LinearAnimationDuration. One cycle; every window closes inside it.
    readonly property int cycleMs: 1750
    property real firstHead: 0
    property real firstTail: 0
    property real secondHead: 0
    property real secondTail: 0

    // One endpoint's window: hold at 0, sweep to 1, hold until the cycle ends.
    component Sweep: SequentialAnimation {
        id: sweep
        property string prop
        property int startMs
        property int spanMs

        PauseAnimation { duration: sweep.startMs }
        NumberAnimation {
            target: root
            property: sweep.prop
            from: 0
            to: 1
            duration: sweep.spanMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        PauseAnimation { duration: root.cycleMs - sweep.startMs - sweep.spanMs }
    }

    // A segment of the track, tail to head. AOSP `drawLinearIndicator` strokes it
    // with round caps and clamps both ends half a stroke inside the track, so a
    // segment entering or leaving is a dot at the edge. Sized as a bare
    // `(head - tail) * width`, it was nothing there instead: the track sat empty
    // for ~124ms at every loop seam, which reads as the sweep cutting out.
    component Segment: Rectangle {
        property real head: 0
        property real tail: 0
        readonly property real cap: height / 2
        readonly property real start: Math.max(cap, Math.min(parent.width - cap, tail * parent.width))
        readonly property real end: Math.max(cap, Math.min(parent.width - cap, head * parent.width))

        visible: head > tail
        y: 0
        height: parent.height
        x: start - cap
        width: end - start + height
        radius: Appearance.rounding.full
        color: root.highlightColor
    }

    ParallelAnimation {
        running: root.visible
        loops: Animation.Infinite

        // AOSP: FirstLineHead 1000 at 0, FirstLineTail 1000 at 250,
        // SecondLineHead 850 at 650, SecondLineTail 850 at 900.
        Sweep { prop: "firstHead";  startMs: 0;   spanMs: 1000 }
        Sweep { prop: "firstTail";  startMs: 250; spanMs: 1000 }
        Sweep { prop: "secondHead"; startMs: 650; spanMs: 850 }
        Sweep { prop: "secondTail"; startMs: 900; spanMs: 850 }
    }

    // Basic's own background paints palette.midlight; the track below replaces it.
    background: null

    contentItem: Item {
        implicitWidth: root.valueBarWidth
        implicitHeight: root.valueBarHeight

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: root.trackColor
        }

        Segment { head: root.firstHead;  tail: root.firstTail }
        Segment { head: root.secondHead; tail: root.secondTail }
    }
}
