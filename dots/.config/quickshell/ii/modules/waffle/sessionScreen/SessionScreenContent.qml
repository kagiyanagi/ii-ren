pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    signal closed()

    property bool show: false

    function run(action) {
        if (!GlobalStates.sessionOpen)
            return;
        GlobalStates.sessionOpen = false;
        action();
    }

    Component.onCompleted: {
        root.show = true;
        lockButton.forceActiveFocus();
    }

    Connections {
        target: GlobalStates
        function onSessionOpenChanged() {
            root.show = GlobalStates.sessionOpen;
            if (GlobalStates.sessionOpen) {
                lockButton.forceActiveFocus();
            }
        }
    }

    opacity: root.show ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation {
            duration: Looks.duration.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.show ? Looks.transition.easing.bezierCurve.easeIn : Looks.transition.easing.bezierCurve.easeOut
        }
    }

    onVisibleChanged: {
        if (!visible && !GlobalStates.sessionOpen)
            root.closed();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            event.accepted = true;
            GlobalStates.sessionOpen = false;
        }
    }

    // Scrim dimming background
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Appearance.m3colors.m3scrim

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onPressed: GlobalStates.sessionOpen = false
            onWheel: wheel => wheel.accepted = true
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => event.accepted = true
        }
    }

    // Center action buttons
    Item {
        id: centralContainer
        anchors.centerIn: parent
        implicitWidth: centralColumn.implicitWidth
        implicitHeight: centralColumn.implicitHeight
        transformOrigin: Item.Center
        scale: root.show ? 1.0 : 0.96
        Behavior on scale {
            NumberAnimation {
                duration: Looks.duration.fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.show ? Looks.transition.easing.bezierCurve.easeIn : Looks.transition.easing.bezierCurve.easeOut
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            id: centralColumn
            anchors.fill: parent
            spacing: 4

            WSessionScreenTextButton {
                id: lockButton
                Layout.fillWidth: true
                focus: true
                text: Translation.tr("Lock")
                onClicked: root.run(() => Session.lock())
                KeyNavigation.up: powerButton
                KeyNavigation.down: signOutButton
            }

            WSessionScreenTextButton {
                id: signOutButton
                Layout.fillWidth: true
                focus: true
                text: Translation.tr("Sign out")
                onClicked: root.run(() => Session.logout())
                KeyNavigation.up: lockButton
                KeyNavigation.down: changePasswordButton
            }

            WSessionScreenTextButton {
                id: changePasswordButton
                Layout.fillWidth: true
                focus: true
                text: Translation.tr("Change password")
                onClicked: root.run(() => Session.changePassword())
                KeyNavigation.up: signOutButton
                KeyNavigation.down: taskManagerButton
            }

            WSessionScreenTextButton {
                id: taskManagerButton
                Layout.fillWidth: true
                focus: true
                text: Translation.tr("Task Manager")
                onClicked: root.run(() => Session.launchTaskManager())
                KeyNavigation.up: changePasswordButton
                KeyNavigation.down: cancelButton
            }

            CancelButton {
                id: cancelButton
                Layout.fillWidth: true
                Layout.leftMargin: 0
                Layout.rightMargin: 0
                Layout.topMargin: 40
                onClicked: GlobalStates.sessionOpen = false
                KeyNavigation.up: taskManagerButton
                KeyNavigation.down: powerButton
                KeyNavigation.right: powerButton
            }
        }
    }

    RowLayout {
        anchors {
            bottom: parent.bottom
            right: parent.right
            bottomMargin: 24
            rightMargin: 32
        }
        PowerButton {
            id: powerButton
            KeyNavigation.up: cancelButton
            KeyNavigation.down: lockButton
            KeyNavigation.left: cancelButton
        }
    }

    component CancelButton: WBorderlessButton {
        id: cancelButtonComponent
        implicitHeight: 32
        colBackground: Looks.darkColors.bg1Base
        colBackgroundHover: Looks.darkColors.bg1Hover
        colBackgroundActive: Looks.darkColors.bg1Active
        colForeground: Looks.darkColors.fg

        property bool keyboardDown: false

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                keyboardDown = true;
                event.accepted = true;
            }
        }
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                keyboardDown = false;
                cancelButtonComponent.clicked();
                event.accepted = true;
            }
        }

        contentItem: WText {
            text: Translation.tr("Cancel")
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Looks.font.pixelSize.large
            color: cancelButtonComponent.colForeground
        }

        Rectangle {
            visible: cancelButtonComponent.focus
            anchors {
                fill: parent
                margins: -4
            }
            radius: cancelButtonComponent.radius + 4
            color: "transparent"
            border.width: 2
            border.color: Looks.darkColors.fg
        }
    }
}
