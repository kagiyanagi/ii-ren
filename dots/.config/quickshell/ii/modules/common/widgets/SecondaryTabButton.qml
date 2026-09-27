import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

TabButton {
    id: root
    property string buttonText
    property string buttonIcon
    property int rippleDuration: 225 // Compose RippleAnimation
    // A tab is a fixed cell -- TabBar hands every tab the same width -- so the
    // row inside it is capped and its label elides rather than drawing out past
    // the pill (DESIGN.md 10.17).
    property int tabContentWidth: Math.max(0, buttonBackground.width - buttonBackground.radius * 2)

    property color colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
    property color colRipple: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.95)

    component RippleAnim: NumberAnimation {
        duration: rippleDuration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animationCurves.standardDecel
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: (event) => {
            // This MouseArea swallows the press, so AbstractButton never sets its
            // own `down` -- which is what the press film and the colour ternaries
            // read. RippleButton drives it by hand for the same reason.
            root.down = true
            root.click() // Because the MouseArea already consumed the event
            const {x,y} = event
            const stateY = buttonBackground.y;
            rippleAnim.x = x;
            rippleAnim.y = y - stateY;

            const dist = (ox,oy) => ox*ox + oy*oy
            const stateEndY = stateY + buttonBackground.height
            rippleAnim.radius = Math.sqrt(Math.max(dist(0, stateY), dist(0, stateEndY), dist(width, stateY), dist(width, stateEndY)))

            rippleFadeAnim.complete();
            rippleAnim.restart();
        }
        onReleased: (event) => {
            root.down = false
            rippleFadeAnim.restart();
        }
        onCanceled: (event) => {
            root.down = false
            rippleFadeAnim.restart();
        }
    }

    RippleAnim {
        id: rippleFadeAnim
        duration: 150 // Compose RippleAnimation.FadeOutDuration
        easing.type: Easing.Linear
        target: ripple
        property: "opacity"
        to: 0
    }

    SequentialAnimation {
        id: rippleAnim

        property real x
        property real y
        property real radius

        PropertyAction {
            target: ripple
            property: "x"
            value: rippleAnim.x
        }
        PropertyAction {
            target: ripple
            property: "y"
            value: rippleAnim.y
        }
        PropertyAction {
            target: ripple
            property: "opacity"
            value: 1
        }
        ParallelAnimation {
            RippleAnim {
                target: ripple
                properties: "implicitWidth,implicitHeight"
                from: rippleAnim.radius * 2 * 0.6 // Android starts the ripple at 60% radius
                to: rippleAnim.radius * 2
            }
        }
    }

    background: Rectangle {
        id: buttonBackground
        anchors {
            fill: parent
            margins: 4
        }
        radius: Appearance?.rounding.normal
        implicitHeight: 42
        color: root.colBackground
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: buttonBackground.width
                height: buttonBackground.height
                radius: buttonBackground.radius
            }
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // All four of 3.1's states, composited rather than mixed into the
        // background. The old hover tint was a hand-rolled 0.05 of colOnSurface
        // that a checked tab turned off entirely, and focus and press had
        // nothing at all. The parent's OpacityMask clips this to the tab's
        // corners, so the film does not repeat them.
        StateOverlay {
            anchors.fill: parent
            hover: root.hovered && !root.down
            focused: root.visualFocus
            press: root.down
            contentColor: Appearance.colors.colOnLayer1
        }

        Item {
            id: ripple
            width: ripple.implicitWidth
            height: ripple.implicitHeight
            opacity: 0

            visible: width > 0 && height > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 75 // Compose RippleAnimation.FadeInDuration
                    easing.type: Easing.Linear
                }
            }

            RadialGradient {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.colRipple }
                    GradientStop { position: 0.3; color: root.colRipple }
                    GradientStop { position: 0.5 ; color: Qt.rgba(root.colRipple.r, root.colRipple.g, root.colRipple.b, 0) }
                }
            }

            transform: Translate {
                x: -ripple.width / 2
                y: -ripple.height / 2
            }
        }
    }

    contentItem: Item {
        anchors.centerIn: buttonBackground
        RowLayout {
            anchors.centerIn: parent
            width: Math.min(implicitWidth, root.tabContentWidth)
            spacing: iconLoader.active ? 8 : 0

            Loader {
                id: iconLoader
                active: buttonIcon?.length > 0
                sourceComponent: buttonIcon?.length > 0 ? materialSymbolComponent : null
            }

            Component {
                id: materialSymbolComponent
                MaterialSymbol {
                    verticalAlignment: Text.AlignVCenter
                    text: buttonIcon
                    iconSize: Appearance.font.pixelSize.huge
                    fill: root.checked ? 1 : 0
                    color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
            StyledText {
                id: buttonTextWidget
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                text: buttonText
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
    }
}
