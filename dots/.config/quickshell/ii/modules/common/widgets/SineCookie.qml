import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.modules.common

Item {
    id: root
    
    property real sides: 12  
    property int implicitSize: 100
    property real amplitude: implicitSize / 50
    property int renderPoints: 360
    property color color: Appearance.colors.colLayer1
    property alias strokeWidth: shapePath.strokeWidth

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    Behavior on sides {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Shape {
        id: shape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: shapePath
            strokeWidth: 0
            fillColor: root.color
            pathHints: ShapePath.PathSolid & ShapePath.PathNonIntersecting

            PathPolyline {
                // 361 points, rebuilt in JS whenever `sides` moves. `constantlyRotate`
                // used to drive that off a FrameAnimation, every frame, forever -
                // DESIGN.md 8's "recomputed in JS per frame", for a knob no caller ever
                // set. CookieClock spins the container instead, which is a transform
                // and free; that is the way to do it.
                property var pointsList: {
                    var points = []
                    var cx = shape.width / 2   // center x
                    var cy = shape.height / 2  // center y
                    var steps = root.renderPoints
                    var radius = root.implicitSize / 2 - root.amplitude
                    for (var i = 0; i <= steps; i++) {
                        var angle = (i / steps) * 2 * Math.PI
                        var rotatedAngle = angle * root.sides + Math.PI / 2
                        var wave = Math.sin(rotatedAngle) * root.amplitude
                        var x = Math.cos(angle) * (radius + wave) + cx
                        var y = Math.sin(angle) * (radius + wave) + cy
                        points.push(Qt.point(x, y))
                    }
                    return points
                }

                path: pointsList
            }
            
        }
    }
}
