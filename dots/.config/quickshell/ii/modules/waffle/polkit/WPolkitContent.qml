pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.services

Item {
    id: root

    // The dialog has finished leaving; the window is held mapped until then.
    signal closed()

    property bool show: false
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true

    // Copied out of the flow while it lives, not bound to it. The flow is deleted
    // on the frame it completes, before the exit plays, and a message bound to it
    // emptied on the exit's first frame and pulled the field up a line.
    property string message
    property string pamMessage
    property bool pamMessageIsError
    property bool failed
    readonly property string appIconName: PolkitService.flow?.iconName ?? ""

    function capture() {
        const flow = PolkitService.flow;
        if (!flow)
            return;
        root.message = PolkitService.cleanMessage;
        root.pamMessage = flow.supplementaryMessage;
        root.pamMessageIsError = flow.supplementaryIsError;
    }

    // Status display in the standard lock/polkit order:
    // 1. PAM lockout / faillock message
    // 2. Failure signal ("Incorrect password")
    // 3. Caps Lock notification ("Caps Lock is on")
    readonly property string status: {
        if (root.pamMessage.length > 0)
            return root.pamMessage;
        if (root.failed)
            return Translation.tr("Incorrect password");
        if (HyprlandXkb.capsLock)
            return Translation.tr("Caps Lock is on");
        return "";
    }
    readonly property bool statusIsError: root.pamMessage.length > 0 ? root.pamMessageIsError : root.failed

    function submit() {
        root.failed = false;
        PolkitService.submit(inputField.text);
    }

    function takeFocus() {
        // A disabled field drops focus; root must keep active focus so
        // Esc continues to work while pam_unix waits before reporting a failure.
        if (!PolkitService.interactionAvailable) {
            root.forceActiveFocus();
            return;
        }
        inputField.text = "";
        inputField.forceActiveFocus();
    }

    Component.onCompleted: {
        root.capture();
        HyprlandXkb.refreshLockKeys();
        root.takeFocus();
        root.show = true;
    }

    Connections {
        target: PolkitService
        function onFlowChanged() {
            if (!PolkitService.flow)
                return;
            root.failed = false;
            root.capture();
        }
        function onActiveChanged() {
            if (!PolkitService.active)
                root.show = false;
        }
        function onInteractionAvailableChanged() {
            root.takeFocus();
        }
    }

    Connections {
        target: PolkitService.flow
        function onSupplementaryMessageChanged() {
            root.capture();
        }
        function onSupplementaryIsErrorChanged() {
            root.capture();
        }
        function onAuthenticationFailed() {
            root.failed = true;
            shakeAnim.restart();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            event.accepted = true;
            PolkitService.cancel();
        } else if (event.key === Qt.Key_CapsLock && !event.isAutoRepeat) {
            HyprlandXkb.noteCapsLockPressed();
        }
    }

    opacity: root.show ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation {
            duration: root.show ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveFast.duration / 2
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.show ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
        }
    }

    onVisibleChanged: {
        if (!visible && !PolkitService.active)
            root.closed();
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Appearance.colors.m3scrim

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onPressed: PolkitService.cancel()
            onWheel: wheel => wheel.accepted = true
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => event.accepted = true
        }
    }

    PolkitDialog {
        id: dialog
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        transformOrigin: Item.Center
        scale: root.show ? 1.0 : 1.05
        Behavior on scale {
            NumberAnimation {
                duration: root.show ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveFast.duration / 2
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.show ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
            }
        }

        ErrorShakeAnimation {
            id: shakeAnim
            target: dialog
            distance: 12
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => event.accepted = true
        }
    }

    component PolkitDialog: WPane {
        borderColor: Looks.colors.ambientShadow

        contentItem: WPanelPageColumn {
            PolkitDialogHeader {
                Layout.fillWidth: true
            }
            BodyRectangle {
                id: dialogBody
                implicitHeight: bodyContent.implicitHeight + 48
                implicitWidth: 440
                color: Looks.colors.bg1Base

                ColumnLayout {
                    id: bodyContent
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        WAppIcon {
                            iconName: root.appIconName.length > 0 ? root.appIconName : "window-shield"
                            fallback: root.appIconName.length > 0 ? root.appIconName : `${Looks.iconsPath}/window-shield`
                            isMask: root.appIconName.length === 0
                            tryCustomIcon: false
                        }
                        WText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                            font.pixelSize: Looks.font.pixelSize.larger
                            font.weight: Looks.font.weight.strongest
                            text: {
                                const icon = root.appIconName;
                                if (!icon)
                                    return Translation.tr("Command-line-invoked Action");
                                const desktopEntry = DesktopEntries.applications.values.find(entry => {
                                    return entry.icon == icon;
                                });
                                return desktopEntry ? desktopEntry.name : Translation.tr("Unknown Application");
                            }
                        }
                    }

                    WText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignLeft
                        text: root.message
                    }

                    WTextField {
                        id: inputField
                        Layout.fillWidth: true
                        focus: true
                        enabled: PolkitService.interactionAvailable
                        placeholderText: PolkitService.cleanPrompt
                        echoMode: root.usePasswordChars ? TextInput.Password : TextInput.Normal
                        onAccepted: root.submit()

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                event.accepted = true;
                                PolkitService.cancel();
                            } else if (event.key === Qt.Key_CapsLock && !event.isAutoRepeat) {
                                HyprlandXkb.noteCapsLockPressed();
                            }
                        }
                    }

                    WIndeterminateProgressBar {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        visible: !PolkitService.interactionAvailable && PolkitService.active
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.status.length > 0

                        FluentIcon {
                            implicitSize: 14
                            icon: root.statusIsError ? "alert" : "shield"
                            color: root.statusIsError ? Looks.colors.danger : Looks.colors.subfg
                        }

                        WText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignLeft
                            font.pixelSize: Looks.font.pixelSize.normal
                            color: root.statusIsError ? Looks.colors.danger : Looks.colors.subfg
                            text: root.status
                        }
                    }
                }
            }
            BodyRectangle {
                implicitHeight: 80
                color: Looks.colors.bgPanelFooterBackground
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 8
                    uniformCellSizes: true

                    WButton {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        horizontalAlignment: Text.AlignHCenter
                        checked: true
                        enabled: PolkitService.interactionAvailable
                        text: Translation.tr("Yes")
                        onClicked: root.submit()
                    }
                    WButton {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        horizontalAlignment: Text.AlignHCenter
                        colBackground: Looks.colors.bg1
                        text: Translation.tr("No")
                        onClicked: PolkitService.cancel()
                    }
                }
            }
        }
    }

    component PolkitDialogHeader: BodyRectangle {
        implicitHeight: headerContent.implicitHeight
        color: Looks.colors.bg2Base

        DragHandler {
            target: null
            property real startX: dialog.x
            property real startY: dialog.y
            onActiveChanged: {
                if (!active) return;
                startX = dialog.x;
                startY = dialog.y;
            }
            xAxis.onActiveValueChanged: {
                dialog.x = Math.round(startX + xAxis.activeValue);
            }
            yAxis.onActiveValueChanged: {
                dialog.y = Math.round(startY + yAxis.activeValue);
            }
        }

        CloseButton {
            anchors {
                top: parent.top
                right: parent.right
            }
            radius: 0
            implicitWidth: 32
            implicitHeight: 32

            onClicked: PolkitService.cancel()
        }

        ColumnLayout {
            id: headerContent
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            spacing: 16

            WText {
                Layout.topMargin: 20
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                text: Translation.tr("Polkit")
            }
            WText {
                Layout.fillWidth: true
                Layout.bottomMargin: 12
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                text: Translation.tr("Do you want to allow this app to make changes to your device?")
                font.pixelSize: Looks.font.pixelSize.xlarger
                font.weight: Looks.font.weight.strongest
            }
        }
    }
}
