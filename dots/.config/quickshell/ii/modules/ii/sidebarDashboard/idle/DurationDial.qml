pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Shapes

// Keep awake's durations on a dial: StyledSlider's track bent round a circle
// whose centre is the card's top-right corner, so a quarter of it crosses the
// card. The durations turn past a fixed thumb where the arc faces the
// bottom-left corner, and that corner holds the readout. The same track, stops,
// thumb and colours as the slider it replaced. Drag it round, tap a duration,
// scroll, or use the arrow keys. It turns with the drag and picks on release,
// as the slider did, so passing 6h on the way to 24h never starts a 6h one.
Item {
    id: root
    required property var durations
    // The one in use. Followed whenever the user is not turning the dial.
    required property int currentIndex
    signal picked(int index)

    readonly property int last: durations.length - 1
    // Where the dial is, in steps: fractional while it turns.
    property real pos: currentIndex
    readonly property int shown: Math.max(0, Math.min(last, Math.round(pos)))
    property bool dragging: false

    // Geometry. The thumb's angle is where the arc faces the bottom-left corner;
    // 0 is 3 o'clock and angles run clockwise, as in PathAngleArc.
    readonly property real cx: width
    readonly property real cy: 0
    readonly property real radius: Math.round(0.5 * Math.hypot(width, height))
    readonly property real thumbAngle: 135
    // Degrees between stops: five durations across the quarter, as in the reference.
    readonly property real step: 20
    readonly property real trackWidth: StyledSlider.Configuration.XS
    readonly property real thumbWidth: (mouse.pressed || dragging) ? 1.5 : 3 // StyledSlider's squeeze
    readonly property real thumbHeight: Math.max(33, trackWidth + 9) // StyledSlider's thumb
    readonly property real thumbMargins: 4
    // The track stops short of the thumb either side, round caps included.
    readonly property real gap: (thumbMargins + thumbWidth / 2 + trackWidth / 2) / radius * 180 / Math.PI

    function angleOf(i: real): real {
        return root.thumbAngle - (i - root.pos) * root.step;
    }
    function pointerAngle(x: real, y: real): real {
        return Math.atan2(y - root.cy, x - root.cx) * 180 / Math.PI;
    }
    function clamp(i: real): real {
        return Math.max(0, Math.min(root.last, i));
    }
    // Turns to a stop on the spatial spec, so it lands with the slider's settle.
    function settle(i: int): void {
        // A pick comes back as currentIndex; restarting would stall the turn.
        if (settleAnim.running && settleAnim.to === i) return;
        settleAnim.stop();
        settleAnim.to = i;
        settleAnim.start();
    }
    function pick(i: int): void {
        i = root.clamp(i);
        root.settle(i);
        if (i !== root.currentIndex) root.picked(i);
    }

    onCurrentIndexChanged: if (!mouse.pressed) root.settle(root.currentIndex)

    NumberAnimation {
        id: settleAnim
        target: root
        property: "pos"
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }

    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) root.pick(root.shown - 1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) root.pick(root.shown + 1);
        else return;
        event.accepted = true;
    }
    Accessible.role: Accessible.Slider
    Accessible.name: Translation.tr("Duration")
    Accessible.description: `${bigNumber.text} ${unit.text}`

    // The track: primary up to the thumb, secondary container after it.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Appearance.colors.colPrimary
            strokeWidth: root.pos * root.step > root.gap ? root.trackWidth : 0
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.angleOf(0)
                sweepAngle: -Math.max(0, root.pos * root.step - root.gap)
            }
        }
        ShapePath {
            strokeColor: Appearance.colors.colSecondaryContainer
            strokeWidth: (root.last - root.pos) * root.step > root.gap ? root.trackWidth : 0
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.thumbAngle - root.gap
                sweepAngle: -Math.max(0, (root.last - root.pos) * root.step - root.gap)
            }
        }
    }

    // A stop on the track and its duration inside the arc, both turning with it.
    Repeater {
        model: root.durations.length
        delegate: Item {
            id: stop
            required property int index
            readonly property real angle: root.angleOf(index)
            readonly property real rad: angle * Math.PI / 180
            // 0 at the thumb, 1 a whole step away.
            readonly property real away: Math.abs(index - root.pos)
            anchors.fill: parent

            Rectangle {
                readonly property real size: 4
                visible: Math.abs(stop.angle - root.thumbAngle) > root.gap
                x: root.cx + root.radius * Math.cos(stop.rad) - size / 2
                y: root.cy + root.radius * Math.sin(stop.rad) - size / 2
                width: size
                height: size
                radius: Appearance.rounding.full
                color: stop.index < root.pos ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSecondaryContainer
            }

            Item {
                // Inside the arc, clear of the track and the thumb.
                readonly property real r: root.radius - root.thumbHeight / 2 - 24
                x: root.cx + r * Math.cos(stop.rad) - width / 2
                y: root.cy + r * Math.sin(stop.rad) - height / 2
                width: label.implicitWidth
                height: label.implicitHeight
                // Upright at the thumb, leaning with the arc away from it.
                rotation: stop.angle - root.thumbAngle
                scale: 1 - 0.2 * Math.min(1, stop.away)
                opacity: Math.max(0, 1 - stop.away / 2.5)
                visible: opacity > 0

                readonly property int minutes: root.durations[stop.index]
                StyledText {
                    id: label
                    visible: parent.minutes > 0
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({})
                    font.features: ({ "tnum": 1 })
                    color: stop.index === root.shown ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    text: parent.minutes < 60 ? `${parent.minutes}m` : `${parent.minutes / 60}h`
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: parent.minutes === 0
                    iconSize: Appearance.font.pixelSize.huge
                    color: label.color
                    text: "all_inclusive"
                }
            }
        }
    }

    // The thumb: StyledSlider's bar, standing across the track, with the four
    // state films behind it as a round halo.
    Item {
        readonly property real rad: root.thumbAngle * Math.PI / 180
        x: root.cx + root.radius * Math.cos(rad) - width / 2
        y: root.cy + root.radius * Math.sin(rad) - height / 2
        width: 40
        height: 40

        StateOverlay {
            anchors.fill: parent
            radius: Appearance.rounding.full
            contentColor: Appearance.colors.colPrimary
            hover: mouse.containsMouse && !mouse.pressed
            focused: root.activeFocus
            press: mouse.pressed && !root.dragging
            drag: root.dragging
        }
        Rectangle {
            anchors.centerIn: parent
            width: root.thumbWidth
            height: root.thumbHeight
            // Along the radius, so it crosses the track as the slider's crosses its own.
            rotation: root.thumbAngle - 90
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary
            Behavior on width {
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }
        }
    }

    // The readout, in the corner the arc leaves free.
    Column {
        id: readout
        readonly property int minutes: root.durations[root.shown]
        // Where it ends if started now, or where the running one does.
        readonly property var end: {
            if (minutes === 0) return null;
            const running = Idle.inhibit && Idle.anchors.length === 0 && Idle.until > 0
                && minutes === (Persistent.states.idle.minutes ?? 0);
            return new Date(running ? Idle.until : DateTime.clock.date.getTime() + minutes * 60000);
        }
        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: 16
        }
        spacing: 0

        Item {
            implicitWidth: readout.minutes === 0 ? infinity.implicitWidth : bigNumber.implicitWidth
            implicitHeight: bigNumber.implicitHeight
            StyledText {
                id: bigNumber
                visible: readout.minutes > 0
                animateChange: !root.dragging
                font.pixelSize: Appearance.font.pixelSize.huge * 3
                font.family: Appearance.font.family.numbers
                font.variableAxes: ({})
                font.features: ({ "tnum": 1 })
                color: Appearance.colors.colOnSurface
                text: readout.minutes === 0 ? "" : readout.minutes < 60 ? `${readout.minutes}` : `${readout.minutes / 60}`
            }
            MaterialSymbol {
                id: infinity
                anchors.verticalCenter: parent.verticalCenter
                visible: readout.minutes === 0
                iconSize: Appearance.font.pixelSize.huge * 3
                color: Appearance.colors.colOnSurface
                text: "all_inclusive"
            }
        }
        StyledText {
            id: unit
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Medium
            color: Appearance.colors.colOnSurface
            text: readout.minutes === 0 ? Translation.tr("Always")
                : readout.minutes < 60 ? Translation.tr("minutes")
                : readout.minutes === 60 ? Translation.tr("hour") : Translation.tr("hours")
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: {
                const end = readout.end;
                if (!end) return Translation.tr("Until turned off");
                const time = Qt.formatTime(end, Config.options.time.format);
                return end.toDateString() === DateTime.clock.date.toDateString()
                    ? Translation.tr("Until %1").arg(time) : Translation.tr("Until %1 tomorrow").arg(time);
            }
        }
    }

    MouseArea {
        id: mouse
        property real lastAngle: 0
        property point pressPoint
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        onPressed: event => {
            root.forceActiveFocus();
            settleAnim.stop();
            pressPoint = Qt.point(event.x, event.y);
            lastAngle = root.pointerAngle(event.x, event.y);
        }
        // A drag past Qt's threshold turns the dial; anything less is a tap.
        onPositionChanged: event => {
            if (!pressed) return;
            if (!root.dragging && Math.hypot(event.x - pressPoint.x, event.y - pressPoint.y) < Application.styleHints.startDragDistance) return;
            root.dragging = true;
            const a = root.pointerAngle(event.x, event.y);
            const delta = ((a - lastAngle + 540) % 360) - 180;
            lastAngle = a;
            // The duration under the pointer stays under it. Clamped hard: no
            // stretch overscroll (TASTE 9).
            root.pos = root.clamp(root.pos + delta / root.step);
        }
        // A tap picks the duration nearest that angle; a drag, the one at the thumb.
        onReleased: event => {
            const i = root.dragging ? root.pos
                : root.pos + (root.thumbAngle - root.pointerAngle(event.x, event.y)) / root.step;
            root.dragging = false;
            root.pick(Math.round(i));
        }
        onCanceled: {
            root.dragging = false;
            root.settle(root.currentIndex);
        }
        // A notch a stop; a touchpad adds up to one.
        property real wheelSum: 0
        onWheel: event => {
            wheelSum += event.angleDelta.y;
            if (Math.abs(wheelSum) < 120) return;
            const d = wheelSum < 0 ? 1 : -1;
            wheelSum = 0;
            root.pick(root.shown + d);
        }
    }
}
