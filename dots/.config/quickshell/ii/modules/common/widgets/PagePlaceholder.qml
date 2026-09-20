import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.animations

Item {
    id: root

    property bool shown: true

    // Both of the fade's directions are effects specs -- opacity clips if it
    // overshoots -- and leaving is the faster of the two (2.5). The icon's spin
    // is a transform, so entering is spatial.
    //
    // Each is assigned from inside the binding that drives it, not from a
    // binding of its own: a Behavior bakes its spec when that write happens,
    // and other bindings on `shown` are not necessarily current yet. Traced
    // here, `opacity` ran first and the exit took the enter's 200ms. See
    // Revealer and DESIGN.md 2.9.
    property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
    property AnimSpec iconSpec: Appearance.animation.elementMoveEnter

    property alias icon: shapeWidget.text
    property alias title: widgetNameText.text
    property alias description: widgetDescriptionText.text
    property alias shape: shapeWidget.shape
    property alias descriptionHorizontalAlignment: widgetDescriptionText.horizontalAlignment
    property alias rotateIconWithShape: shapeWidget.rotateIconWithShape

    property alias iconWidget: shapeWidget
    property alias titleWidget: widgetNameText
    property alias descriptionWidget: widgetDescriptionText

    property alias triggerAnimationOn: openingAnimation.trigger
    property alias rotateToRight: openingAnimation.rotateToRight
    PlaceholderOpeningAnimation {
        id: openingAnimation
        targetPlaceholder: root
    }

    opacity: {
        root.fadeSpec = root.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit
        return root.shown ? 1 : 0
    }
    visible: opacity > 0
    anchors {
        fill: parent
        // The travel rides the opacity animation rather than carrying its own,
        // so the placeholder rises into place as it fades in.
        topMargin: -32 * (1 - opacity)
        bottomMargin: 32 * (1 - opacity)
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.fadeSpec.duration
            easing.type: root.fadeSpec.type
            easing.bezierCurve: root.fadeSpec.bezierCurve
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        MaterialShapeWrappedMaterialSymbol {
            id: shapeWidget
            Layout.alignment: Qt.AlignHCenter
            padding: 12
            iconSize: 56
            rotation: {
                root.iconSpec = root.shown ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit
                return root.shown ? 0 : -70
            }

            Behavior on rotation {
                NumberAnimation {
                    duration: root.iconSpec.duration
                    easing.type: root.iconSpec.type
                    easing.bezierCurve: root.iconSpec.bezierCurve
                }
            }
        }

        StyledText {
            id: widgetNameText
            visible: title !== ""
            Layout.alignment: Qt.AlignHCenter
            // Same bound as the description: centerIn leaves the column free to
            // grow, so a long title would run past the panel instead of eliding.
            Layout.maximumWidth: root.width - 32
            font {
                family: Appearance.font.family.title
                pixelSize: Appearance.font.pixelSize.larger
                variableAxes: Appearance.font.variableAxes.title
            }
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
        }
        StyledText {
            id: widgetDescriptionText
            visible: description !== ""
            Layout.fillWidth: true
            // centerIn leaves the column unconstrained, so the text was setting
            // the layout's width and wrapMode never had a bound to wrap at --
            // a long description simply ran past the panel and clipped.
            Layout.maximumWidth: root.width - 32
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
        }
    }
}
