import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.animations
import qs.services
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    Layout.fillWidth: true
    implicitHeight: 64
    radius: Appearance.rounding.full
    color: LocalSend.serverRunning ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

    // Internal animation control
    property bool startAnim: false

    // Shape, label, action: one transform each, staggerStep apart (2.8).
    readonly property int enterTravel: 24

    onStartAnimChanged: {
        if (!root.startAnim) return;
        shapeTranslate.x = -root.enterTravel;
        statusText.opacity = 0.0;
        toggleBtn.scale = 0.8;
        toggleBtn.opacity = 0.0;
        Qt.callLater(() => {
            shapeAnim.restart();
            textAnim.restart();
            btnAnim.restart();
        });
    }

    component EnterFade: DelayedPropertyAnimation {
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    component EnterMove: DelayedPropertyAnimation {
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    Item {
        id: shapeContainer
        width: 40
        height: 40
        anchors {
            left: parent.left
            leftMargin: 12
            verticalCenter: parent.verticalCenter
        }
        
        transform: Translate {
            id: shapeTranslate
            x: 0
        }

        EnterMove {
            id: shapeAnim
            target: shapeTranslate
            property: "x"
            from: -root.enterTravel
        }

        MaterialShape {
            id: shapeItem
            shapeString: "Circle"
            implicitSize: 40
            color: LocalSend.serverRunning ? Appearance.colors.colPrimary : Appearance.colors.colError
            anchors.centerIn: parent

            MaterialSymbol {
                anchors.centerIn: parent
                text: "devices"
                iconSize: Appearance.font.pixelSize.huge
                color: LocalSend.serverRunning ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary
                fill: 1
            }
        }
    }

    RowLayout {
        anchors { left: parent.left; right: toggleBtn.left; verticalCenter: parent.verticalCenter; leftMargin: 64; rightMargin: 12 }

        StyledText {
            id: statusText
            Layout.fillWidth: true
            text: LocalSend.serverRunning ? Translation.tr("LocalSend • running") : Translation.tr("LocalSend • stopped")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            font.weight: Font.Bold
            color: LocalSend.serverRunning ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            horizontalAlignment: Text.AlignHCenter
            opacity: 1.0

            EnterFade {
                id: textAnim
                target: statusText
                delay: Appearance.animation.staggerStep
            }
        }
    }

    RippleButton {
        id: toggleBtn
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        colBackground: LocalSend.serverRunning ? Appearance.colors.colPrimary : Appearance.colors.colSecondary
        colBackgroundHover: LocalSend.serverRunning ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryHover
        scale: 1.0
        opacity: 1.0

        ParallelAnimation {
            id: btnAnim

            EnterFade {
                target: toggleBtn
                delay: Appearance.animation.staggerStep * 2
            }
            EnterMove {
                target: toggleBtn
                property: "scale"
                from: 0.8
                to: 1
                delay: Appearance.animation.staggerStep * 2
            }
        }


        onClicked: {
            if (LocalSend.serverRunning) LocalSend.stopServer()
            else LocalSend.startServer()
        }
        MaterialSymbol {
            anchors {
                verticalCenter: parent.verticalCenter
                verticalCenterOffset: 1 // QML whyyy, why do you need this
                horizontalCenter: parent.horizontalCenter
            }
            text: LocalSend.serverRunning ? "stop_circle" : "play_circle"
            iconSize: Appearance.font.pixelSize.huge
            color: LocalSend.serverRunning ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary
            fill: 1
        }

        StyledToolTip {
            text: LocalSend.serverRunning ? Translation.tr("Stop receiving") : Translation.tr("Start receiving")
        }
    }
}
