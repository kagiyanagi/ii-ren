import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

TabButton {
    id: root

    property bool toggled: TabBar.tabBar.currentIndex === TabBar.index
    property string buttonIcon
    property real buttonIconRotation: 0
    property string buttonText
    property bool _isInitialized: false
    Component.onCompleted: _isInitialized = true

    property bool expanded: false
    property bool showToggledHighlight: true
    // Width the rail gives this item when collapsed. The icon centres in it and
    // the label is cut to fit it, so a rail that wants room for longer names
    // raises this instead of letting them spill past its edge.
    property real collapsedWidth: baseSize

    /*
     * Expanding is a surface growing and collapsing is one leaving, so the two
     * do not share a spec (DESIGN.md 2.5): out on the default spatial one, back
     * in on the fast effects one at roughly a quarter the length. Both legs used
     * to be elementMoveFast, an effects spec driving an anchor, which 2.1 rules
     * out in either direction.
     *
     * The anchor halves get their direction from a state's `to:`, which is
     * unambiguous. The width has no state of its own -- it rides this binding --
     * so it takes 2.9's shape instead: the spec is assigned from inside the
     * binding that drives the animation, which by construction runs before the
     * write that starts it. Revealer is the worked example.
     */
    property AnimSpec railSpec: Appearance.animation.elementMove
    readonly property real visualWidth: {
        root.railSpec = root.expanded ? Appearance.animation.elementMove : Appearance.animation.elementMoveExit;
        return root.expanded ? root.baseSize + 20 + itemText.implicitWidth : root.collapsedWidth;
    }

    component RailEnter: Transition {
        AnchorAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    component RailExit: Transition {
        AnchorAnimation {
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
    }

    property real baseSize: 56
    property real baseHighlightHeight: 32
    property real iconSize: 24
    property real highlightCollapsedTopMargin: 8
    padding: 0

    // Selected, the item sits on the secondary container -- its own highlight or
    // the one NavigationRailTabArray slides behind it -- so the icon, the label
    // and the state film all take that container's content colour, not the
    // rail's. The label used to stay colOnLayer1 on top of the pill.
    readonly property color colContent: root.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

    // The navigation item’s target area always spans the full width of the
    // nav rail, even if the item container hugs its contents.
    Layout.fillWidth: true
    // implicitWidth: contentItem.implicitWidth
    implicitHeight: baseSize

    background: null
    PointingHandInteraction {}

    // Real stuff
    contentItem: Item {
        id: buttonContent
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: undefined
        }

        implicitWidth: root.visualWidth
        implicitHeight: root.expanded ? itemIconBackground.implicitHeight : itemIconBackground.implicitHeight + itemText.implicitHeight

        Rectangle {
            id: itemBackground
            anchors.top: itemIconBackground.top
            anchors.left: itemIconBackground.left
            anchors.bottom: itemIconBackground.bottom
            implicitWidth: root.visualWidth
            radius: Appearance.rounding.full
            color: toggled ?
                root.showToggledHighlight ?
                    (root.down ? Appearance.colors.colSecondaryContainerActive : root.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                    : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer) :
                (root.down ? Appearance.colors.colLayer1Active : root.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1))

            // Hover and pressed come off the layer's own Hover/Active siblings in
            // the colour above; focus is 3.1's fourth state and the one this
            // rail -- the keyboard-navigable half of the settings app -- never
            // had. A film composites over the highlight instead of replacing it.
            StateOverlay {
                anchors.fill: parent
                radius: parent.radius
                focused: root.visualFocus
                contentColor: root.colContent
            }

            states: State {
                name: "expanded"
                when: root.expanded
                AnchorChanges {
                    target: itemBackground
                    anchors.top: buttonContent.top
                    anchors.left: buttonContent.left
                    anchors.bottom: buttonContent.bottom
                }
            }
            transitions: [
                RailEnter {
                    to: "expanded"
                    enabled: root._isInitialized
                },
                RailExit {
                    to: ""
                    enabled: root._isInitialized
                }
            ]

            Behavior on implicitWidth {
                enabled: root._isInitialized

                NumberAnimation {
                    duration: root.railSpec.duration
                    easing.type: root.railSpec.type
                    easing.bezierCurve: root.railSpec.bezierCurve
                }
            }

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        Item {
            id: itemIconBackground
            implicitWidth: root.expanded ? root.baseSize : root.collapsedWidth
            implicitHeight: root.baseHighlightHeight
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            MaterialSymbol {
                id: navRailButtonIcon
                rotation: root.buttonIconRotation
                anchors.centerIn: parent
                iconSize: root.iconSize
                fill: toggled ? 1 : 0
                font.weight: (toggled || root.hovered) ? Font.DemiBold : Font.Normal
                text: buttonIcon
                color: root.colContent

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        StyledText {
            id: itemText
            states: [
                State {
                    name: "expanded"
                    when: root.expanded
                    AnchorChanges {
                        target: itemText
                        anchors {
                            top: undefined
                            horizontalCenter: undefined
                            left: itemIconBackground.right
                            verticalCenter: itemIconBackground.verticalCenter
                        }
                    }
                },
                State {
                    name: "minimized"
                    when: !root.expanded
                    AnchorChanges {
                        target: itemText
                        anchors {
                            left: undefined
                            verticalCenter: undefined
                            top: itemIconBackground.bottom
                            horizontalCenter: itemIconBackground.horizontalCenter
                        }
                    }
                }
            ]
            transitions: [
                RailEnter {
                    to: "expanded"
                    enabled: root._isInitialized
                },
                RailExit {
                    to: "minimized"
                    enabled: root._isInitialized
                }
            ]
            text: buttonText
            // Collapsed, the label sits under a baseSize-wide icon in a rail
            // that is only that wide, so a long name has to be cut rather than
            // spill out past the rail's edge.
            width: root.expanded ? implicitWidth : root.collapsedWidth
            elide: Text.ElideRight
            horizontalAlignment: root.expanded ? Text.AlignLeft : Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smallie
            // DESIGN.md 9: the label crossfades on the effects spec while the
            // highlight behind it moves on a spatial one.
            color: root.colContent

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

}
