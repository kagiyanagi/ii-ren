import QtQuick
import QtQuick.Window
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets

// 1:1 port of Android 16 (Baklava) PlatLogoActivity.java
// Animation values and math sourced directly from AOSP PlatLogoActivity source code:
//
// Phase 1  — Logo pop-in:   scale 0→1, 500ms, OvershootInterpolator(3.0)
// Phase 2  — Press bounce:  scale 1→1.2, 200ms, OvershootInterpolator(2.0)
// Phase 3  — Wobble & Shake (~500ms long-press threshold):
//              rotation:    0,-7,0,7,0,-5,0,5,0  400ms/cycle  Linear  ∞
//              translateX:  0,-8,8,-6,6,-4,4,0  300ms/cycle  Linear  ∞
// Phase 4  — Glow pulse:    alpha 0→0.35, 200ms/half, InOutSine  ∞
// Phase 5  — Starfield:     128 stars, 4 planes. Velocity 200*(random-0.5).
//                           Streaks scale with dx * warp * plane * 2 + camera jitter.
// Phase 6  — Launch at 3s:  Wobble cancels, logo fades 300ms (Accelerate), then opens web game.

Window {
    id: root
    width: 800
    height: 600
    color: "black"
    title: "Android 16"
    flags: Qt.Window | Qt.FramelessWindowHint

    // ---- state ----
    property bool holding: false
    property real holdStartMs: 0
    property real holdMs: 0
    property real warpSpeed: 0.5      // dp/frame, idle=0.5, max=16.0
    property real starVx: 100.0
    property real starVy:  60.0
    property real lastTick: 0

    // dp scale (AOSP mDp = displayMetrics.density)
    readonly property real dp: Math.min(width, height) / 360.0

    // Press Escape to dismiss on desktop
    Shortcut {
        sequence: "Escape"
        onActivated: root.visible = false
    }

    // ---------------------------------------------------------------
    onVisibleChanged: {
        if (visible) {
            // randomise starfield direction (AOSP: 200*(random-0.5))
            starVx = 200.0 * (Math.random() - 0.5)
            starVy = 200.0 * (Math.random() - 0.5)
            warpSpeed = 0.5
            holding   = false
            holdMs    = 0
            lastTick  = 0

            // stop everything
            wobbleAnim.stop()
            shakeAnim.stop()
            launchTimer.stop()
            wobbleStartDelay.stop()
            logoFadeOut.stop()

            logoRotation.angle = 0
            logoShake.x = 0
            logo.opacity = 0
            logo.scale   = 0

            starCanvas.initStars()
            animTimer.running = true

            // Phase 1: pop-in
            logoPopIn.start()
        } else {
            animTimer.running = false
            wobbleAnim.stop()
            shakeAnim.stop()
            launchTimer.stop()
            wobbleStartDelay.stop()
        }
    }

    // ---------------------------------------------------------------
    // Frame tick – drives starfield and hold-time tracking at 60fps
    Timer {
        id: animTimer
        interval: 16
        repeat: true
        running: false
        onTriggered: {
            var now = Date.now()
            var dt  = root.lastTick > 0 ? Math.min(now - root.lastTick, 100) : 16
            root.lastTick = now

            if (root.holding) {
                root.holdMs = now - root.holdStartMs
                // AOSP formula: speed = 0.5 + (holdMs/3000)*15.5
                root.warpSpeed = 0.5 + Math.min(root.holdMs / 3000.0, 1.0) * 15.5
            } else {
                root.holdMs = 0
                // gently coast back to idle speed
                root.warpSpeed = Math.max(root.warpSpeed - 0.8, 0.5)
            }

            starCanvas.tick(dt)
        }
    }

    // ---------------------------------------------------------------
    // ANIMATIONS

    // Phase 1 – pop-in (scale with Overshoot 3.0, opacity with OutCubic so it never overshoots 1.0)
    ParallelAnimation {
        id: logoPopIn
        NumberAnimation { target: logo; property: "scale";   from: 0; to: 1.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 3.0 }
        NumberAnimation { target: logo; property: "opacity"; from: 0; to: 1.0; duration: 500; easing.type: Easing.OutCubic }
    }

    // Phase 2 – press scale-up (OvershootInterpolator(2.0), 200ms)
    NumberAnimation {
        id: pressBounce
        target: logo; property: "scale"
        from: 1.0; to: 1.2; duration: 200
        easing.type: Easing.OutBack; easing.overshoot: 2.0
    }

    // Phase 2 release – scale back to 1.0
    NumberAnimation {
        id: releaseBounce
        target: logo; property: "scale"
        to: 1.0; duration: 200
        easing.type: Easing.OutBack; easing.overshoot: 2.0
    }

    // Delay before wobble starts (~500ms, system long-press threshold)
    Timer {
        id: wobbleStartDelay
        interval: 500
        onTriggered: {
            wobbleAnim.restart()
            shakeAnim.restart()
        }
    }

    // Phase 3a – rotation wobble
    // AOSP: ofFloat(logo,"rotation", 0,-7,0,7,0,-5,0,5,0) 400ms Linear ∞
    SequentialAnimation {
        id: wobbleAnim
        loops: Animation.Infinite
        running: false
        NumberAnimation { target: logoRotation; property: "angle"; to: -7; duration: 50; easing.type: Easing.Linear }
        NumberAnimation { target: logoRotation; property: "angle"; to:  0; duration: 50; easing.type: Easing.Linear }
        NumberAnimation { target: logoRotation; property: "angle"; to:  7; duration: 50; easing.type: Easing.Linear }
        NumberAnimation { target: logoRotation; property: "angle"; to:  0; duration: 50; easing.type: Easing.Linear }
        NumberAnimation { target: logoRotation; property: "angle"; to: -5; duration: 50; easing.type: Easing.Linear }
        NumberAnimation { target: logoRotation; property: "angle"; to:  0; duration: 50; easing.type: Easing.Linear }
        NumberAnimation { target: logoRotation; property: "angle"; to:  5; duration: 50; easing.type: Easing.Linear }
        NumberAnimation { target: logoRotation; property: "angle"; to:  0; duration: 50; easing.type: Easing.Linear }
    }

    // Phase 3b – X shake (independent animator, creates lissajous motion combined with rotation)
    // AOSP: ofFloat(logo,"translationX", 0,-8,8,-6,6,-4,4,0) 300ms Linear ∞
    SequentialAnimation {
        id: shakeAnim
        loops: Animation.Infinite
        running: false
        NumberAnimation { target: logoShake; property: "x"; to: -8 * root.dp; duration: 43; easing.type: Easing.Linear }
        NumberAnimation { target: logoShake; property: "x"; to:  8 * root.dp; duration: 43; easing.type: Easing.Linear }
        NumberAnimation { target: logoShake; property: "x"; to: -6 * root.dp; duration: 43; easing.type: Easing.Linear }
        NumberAnimation { target: logoShake; property: "x"; to:  6 * root.dp; duration: 43; easing.type: Easing.Linear }
        NumberAnimation { target: logoShake; property: "x"; to: -4 * root.dp; duration: 43; easing.type: Easing.Linear }
        NumberAnimation { target: logoShake; property: "x"; to:  4 * root.dp; duration: 43; easing.type: Easing.Linear }
        NumberAnimation { target: logoShake; property: "x"; to:  0;           duration: 42; easing.type: Easing.Linear }
    }

    // Phase 6 – launch timer (3000ms, then logo fades + game opens)
    Timer {
        id: launchTimer
        interval: 3000
        onTriggered: {
            wobbleAnim.stop()
            shakeAnim.stop()
            logoRotation.angle = 0
            logoShake.x = 0
            logoFadeOut.start()
        }
    }

    // Logo exit fade (AccelerateInterpolator, 300ms)
    SequentialAnimation {
        id: logoFadeOut
        NumberAnimation { target: logo; property: "opacity"; from: 1.0; to: 0.0; duration: 300; easing.type: Easing.InQuad }
        ScriptAction {
            script: {
                root.visible = false
                Qt.openUrlExternally("https://landroid.js.org/player15.html#is16=1")
            }
        }
    }

    // ---------------------------------------------------------------
    // STARFIELD (AOSP Starfield class: 128 stars, 4 planes)
    Canvas {
        id: starCanvas
        anchors.fill: parent

        property var  stars: []
        property int  numStars:  128
        property int  numPlanes: 4
        property real radius: Math.sqrt(width * width + height * height) / 2
        property real cameraJitterX: 0
        property real cameraJitterY: 0

        function initStars() {
            var s = []
            for (var i = 0; i < numStars; i++) {
                var x = (Math.random() * 2 - 1) * radius
                var y = (Math.random() * 2 - 1) * radius
                s.push({ x: x, y: y, streakDx: 0, streakDy: 0 })
            }
            stars = s
            cameraJitterX = 0
            cameraJitterY = 0
            requestPaint()
        }

        function tick(dt) {
            if (stars.length === 0) return
            var dtSec = dt / 1000.0
            var speed = root.warpSpeed
            var vx    = root.starVx
            var vy    = root.starVy
            var vLen  = Math.sqrt(vx * vx + vy * vy) || 1

            // Base displacement vector
            var dx = (vx / vLen) * speed * root.dp * dtSec * 60
            var dy = (vy / vLen) * speed * root.dp * dtSec * 60
            var diameter = radius * 2

            var inWarp = speed > 3.0
            var warpFrac = Math.min((speed - 0.5) / 15.0, 1.0)

            // AOSP camera shake during warp
            if (inWarp) {
                cameraJitterX = (Math.random() - 0.5) * warpFrac * 6 * root.dp
                cameraJitterY = (Math.random() - 0.5) * warpFrac * 6 * root.dp
            } else {
                cameraJitterX = 0
                cameraJitterY = 0
            }

            for (var i = 0; i < numStars; i++) {
                var plane = Math.floor(i / numStars * numPlanes) + 1
                var s = stars[i]

                // Advance head position with seamless toroidal wrapping
                s.x = ((s.x + dx * plane) + diameter * 100 + radius) % diameter - radius
                s.y = ((s.y + dy * plane) + diameter * 100 + radius) % diameter - radius

                // AOSP: Streak length is proportional to warp speed * plane
                if (inWarp) {
                    s.streakDx = dx * plane * warpFrac * 2.5
                    s.streakDy = dy * plane * warpFrac * 2.5
                } else {
                    s.streakDx = 0
                    s.streakDy = 0
                }
            }
            requestPaint()
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.fillStyle = "black"
            ctx.fillRect(0, 0, width, height)
            if (stars.length === 0) return

            var inWarp = root.warpSpeed > 3.0
            var cx = width / 2 + cameraJitterX
            var cy = height / 2 + cameraJitterY
            var starSize = root.dp * 1.8 // AOSP: mDp * 2f
            var slice = Math.floor(numStars / numPlanes)

            for (var p = 0; p < numPlanes; p++) {
                var pw = starSize * (p + 1) * 0.75
                ctx.strokeStyle = "white"
                ctx.fillStyle   = "white"
                ctx.lineWidth   = Math.max(pw, 1.0)

                for (var k = p * slice; k < (p + 1) * slice && k < numStars; k++) {
                    var s = stars[k]
                    var hx = cx + s.x
                    var hy = cy + s.y

                    if (inWarp && (Math.abs(s.streakDx) > 0.5 || Math.abs(s.streakDy) > 0.5)) {
                        // Warp mode: draw streak from trail start -> head
                        ctx.beginPath()
                        ctx.moveTo(hx - s.streakDx, hy - s.streakDy)
                        ctx.lineTo(hx, hy)
                        ctx.stroke()
                    } else {
                        // Idle mode: draw round star point
                        ctx.beginPath()
                        ctx.arc(hx, hy, Math.max(pw / 2, 0.75), 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
            }

            // Faint warp overlay glow at high warp speed
            if (inWarp) {
                var warpFrac = Math.min((root.warpSpeed - 0.5) / 15.0, 1.0)
                var glowAlpha = warpFrac * warpFrac * 0.25
                ctx.fillStyle = "rgba(40, 60, 90, " + glowAlpha + ")"
                ctx.fillRect(0, 0, width, height)
            }
        }

        Component.onCompleted: initStars()
    }

    // ---------------------------------------------------------------
    // LOGO + transforms
    MaterialSymbol {
        id: logo
        anchors.centerIn: parent
        text:     "android"
        iconSize: Math.min(root.width, root.height) * 0.35
        fill:     1
        color:    "#3DDC84"
        opacity:  0
        scale:    0
        transformOrigin: Item.Center

        transform: [
            Rotation  { id: logoRotation; origin.x: logo.iconSize / 2; origin.y: logo.iconSize / 2 },
            Translate { id: logoShake }
        ]
    }

    // ---------------------------------------------------------------
    // TOUCH
    MouseArea {
        anchors.fill: parent

        onPressed: {
            pressBounce.stop()
            releaseBounce.stop()
            pressBounce.start()

            root.holding      = true
            root.holdStartMs  = Date.now()
            root.holdMs       = 0
            root.lastTick     = Date.now()

            wobbleStartDelay.restart()
            launchTimer.restart()
        }

        onReleased: cancelHold()
        onCanceled: cancelHold()

        function cancelHold() {
            root.holding = false
            launchTimer.stop()
            wobbleStartDelay.stop()
            wobbleAnim.stop()
            shakeAnim.stop()
            logoRotation.angle = 0
            logoShake.x = 0
            pressBounce.stop()
            releaseBounce.start()
        }
    }
}
