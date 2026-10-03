pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.panels.lock
import qs.modules.waffle.looks
import qs.modules.waffle.sessionScreen as SessionScreen

LockScreen {
    id: root

    property bool passwordView: false

    lockSurface: Component {
        Item {
            id: lockSurfaceItem

            Component.onCompleted: {
                root.passwordView = false;
                HyprlandXkb.refreshLockKeys();
                lockSurfaceItem.forceActiveFocus();
            }

            Timer {
                id: returnToClockTimer
                interval: 15000
                running: root.passwordView && !root.context.unlockInProgress && root.context.currentText.length === 0
                onTriggered: {
                    root.passwordView = false;
                    lockSurfaceItem.forceActiveFocus();
                }
            }

            Keys.onPressed: event => {
                if (!root.passwordView) {
                    if (event.key === Qt.Key_Escape) return;
                    if (event.key === Qt.Key_CapsLock) {
                        if (!event.isAutoRepeat)
                            HyprlandXkb.noteCapsLockPressed();
                        return;
                    }
                    interactables.switchToFocusedView();
                    if (event.text && event.text.length > 0 && event.text >= " ") {
                        root.context.currentText = event.text;
                    }
                } else {
                    if (event.key === Qt.Key_CapsLock) {
                        if (!event.isAutoRepeat)
                            HyprlandXkb.noteCapsLockPressed();
                    } else if (event.key === Qt.Key_Escape) {
                        if (root.context.currentText.length > 0) {
                            root.context.clearText();
                        } else {
                            interactables.switchToUnfocusedView();
                            lockSurfaceItem.forceActiveFocus();
                        }
                    }
                }
            }

            StyledImage {
                id: bg
                z: 0
                anchors.fill: parent
                source: Config.options.background.wallpaperPath
                fillMode: Image.PreserveAspectCrop
            }

            FastBlur {
                id: blurredBg
                z: 1
                anchors.fill: bg
                source: bg
                radius: 64 // design-ok: FastBlur blur radius
                scale: root.passwordView ? 1.05 : 1
                opacity: root.passwordView ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Looks.duration.fast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: Looks.duration.normal
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
                    }
                }
            }

            Interactables {
                id: interactables
                z: 2
                anchors.fill: parent
            }
        }
    }

    component Interactables: Rectangle {
        id: interactablesComponent
        color: ColorUtils.transparentize(Appearance.m3colors.m3scrim, 0.8)

        function switchToFocusedView() {
            root.passwordView = true;
        }

        function switchToUnfocusedView() {
            root.passwordView = false;
        }

        Item {
            id: unfocusedContent
            width: parent.width
            height: parent.height
            visible: opacity > 0
            opacity: root.passwordView ? 0 : 1
            y: root.passwordView ? -height * 0.4 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Looks.duration.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: Looks.duration.normal
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: interactablesComponent.switchToFocusedView()
                onWheel: wheel => {
                    if (wheel.angleDelta.y > 0 || wheel.pixelDelta.y > 0)
                        interactablesComponent.switchToFocusedView();
                }
            }

            ClockTextGroup {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: Math.round(interactablesComponent.height * 0.1)
                }
            }

            RowLayout {
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                    bottomMargin: 24
                    rightMargin: 32
                }
                spacing: 8

                IconIndicator {
                    baseIcon: "wifi-1"
                    icon: WIcons.internetIcon
                }
                IconIndicator {
                    visible: Battery.available
                    baseIcon: WIcons.batteryIcon
                    icon: WIcons.batteryLevelIcon
                }
            }
        }

        Item {
            id: focusedContent
            anchors.fill: parent
            visible: opacity > 0
            opacity: root.passwordView ? 1 : 0
            y: root.passwordView ? 0 : 32

            Behavior on opacity {
                NumberAnimation {
                    duration: Looks.duration.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: Looks.duration.normal
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
                }
            }

            PasswordGroup {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }
            }

            RowLayout {
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                    bottomMargin: 24
                    rightMargin: 32
                }
                spacing: 8

                IconIndicator {
                    baseIcon: "wifi-1"
                    icon: WIcons.internetIcon
                }
                IconIndicator {
                    visible: Battery.available
                    baseIcon: WIcons.batteryIcon
                    icon: WIcons.batteryLevelIcon
                }
                SessionScreen.PowerButton {
                    id: powerButton
                }
            }
        }
    }

    component IconIndicator: Item {
        id: iconIndicator
        required property string baseIcon
        required property string icon
        default property alias indicatorData: iconWidget.data
        implicitWidth: 40
        implicitHeight: 40

        FluentIcon {
            id: iconWidget
            anchors.centerIn: parent
            icon: iconIndicator.baseIcon
            color: Looks.darkColors.inactiveIcon
            implicitSize: 20

            FluentIcon {
                anchors.fill: parent
                icon: iconIndicator.icon
            }
        }
    }

    component ClockTextGroup: Column {
        id: clockTextGroup
        spacing: -4

        WText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Looks.darkColors.fg
            font.pixelSize: 132 // design-ok: Windows 11 lock screen display clock
            font.weight: Looks.font.weight.strong
            text: {
                // Don't take am/pm
                // Match groups of digits separated by non-digit chars (e.g., "12:34", "12.34", "12-34")
                let match = DateTime.time.match(/(\d{1,2})\D+(\d{2})/);
                return match ? `${match[1]}${DateTime.time.match(/\D+/)[0]}${match[2]}` : DateTime.time;
            }
        }

        WText {
            id: dateLabel
            color: Looks.darkColors.fg
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Appearance.font.pixelSize.hugeass // design-ok: Windows 11 lock screen date style
            font.weight: Looks.font.weight.strong
            text: DateTime.collapsedCalendarFormat
        }
    }

    component PasswordGroup: ColumnLayout {
        id: passwordGroup
        spacing: 16

        readonly property string statusText: {
            if (root.context.authMessage.length > 0)
                return root.context.authMessage;
            if (root.context.showFailure)
                return Translation.tr("The password is incorrect. Please try again.");
            if (HyprlandXkb.capsLock)
                return Translation.tr("Caps Lock is on");
            return "";
        }
        readonly property bool statusIsError: root.context.authMessage.length > 0 || root.context.showFailure

        WUserAvatar {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 144
            implicitHeight: 144
            sourceSize: Qt.size(192, 192)
        }

        WText {
            Layout.alignment: Qt.AlignHCenter
            text: SystemInfo.username
            color: Looks.darkColors.fg
            font.pixelSize: Appearance.font.pixelSize.hugeass // design-ok: Windows 11 user header
            font.weight: Looks.font.weight.strong
        }

        Rectangle {
            id: passwordInputWrapper
            Layout.topMargin: 12
            Layout.alignment: Qt.AlignHCenter
            color: "transparent"
            implicitWidth: 296
            implicitHeight: 36
            border.width: 2
            border.color: Looks.applyContentTransparency(Looks.darkColors.bg1Border)
            radius: Looks.radius.medium

            ErrorShakeAnimation {
                id: shakeAnim
                target: passwordInputWrapper
                distance: 12
            }

            Rectangle {
                id: passwordInputBackground
                anchors.fill: parent
                anchors.margins: 2
                radius: Looks.radius.small + 1
                color: passwordInput.focus ? Looks.applyBackgroundTransparency(Looks.darkColors.bg1Base) : Looks.applyContentTransparency(Looks.darkColors.bg1)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    WTextInput {
                        id: passwordInput
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                        echoMode: passwordVisibilityButton.passwordVisible ? TextInput.Normal : TextInput.Password
                        color: Looks.darkColors.fg
                        enabled: !root.context.unlockInProgress
                        font.pixelSize: Appearance.font.pixelSize.smaller

                        WText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: passwordInput.text.length === 0
                            text: Translation.tr("Password")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Looks.darkColors.fg
                            opacity: 0.6
                        }

                        onTextChanged: {
                            if (root.context.currentText !== text)
                                root.context.currentText = text;
                        }
                        onAccepted: {
                            if (!root.context.unlockInProgress && passwordInput.text.length > 0) {
                                root.context.tryUnlock();
                            }
                        }

                        Connections {
                            target: root.context
                            function onCurrentTextChanged() {
                                if (passwordInput.text !== root.context.currentText)
                                    passwordInput.text = root.context.currentText;
                            }
                            function onShowFailureChanged() {
                                if (root.context.showFailure) {
                                    shakeAnim.restart();
                                }
                            }
                            function onShouldReFocus() {
                                if (root.passwordView) {
                                    passwordInput.forceActiveFocus();
                                }
                            }
                            function onUnlockInProgressChanged() {
                                if (!root.context.unlockInProgress && root.passwordView) {
                                    passwordInput.forceActiveFocus();
                                }
                            }
                        }

                        Connections {
                            target: root
                            function onPasswordViewChanged() {
                                if (root.passwordView) {
                                    passwordInput.forceActiveFocus();
                                }
                            }
                        }

                        Keys.onPressed: event => {
                            root.context.resetClearTimer();
                            if (event.key === Qt.Key_Escape) {
                                event.accepted = true;
                                if (passwordInput.text.length > 0) {
                                    root.context.clearText();
                                } else {
                                    interactables.switchToUnfocusedView();
                                }
                            } else if (event.key === Qt.Key_CapsLock) {
                                if (!event.isAutoRepeat) {
                                    HyprlandXkb.noteCapsLockPressed();
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            cursorShape: Qt.IBeamCursor
                        }
                    }

                    PasswordBoxButton {
                        id: passwordVisibilityButton
                        property bool passwordVisible: false
                        visible: passwordInput.text.length > 0
                        enabled: !root.context.unlockInProgress
                        onPressed: passwordVisible = true
                        onReleased: passwordVisible = false
                        onCanceled: passwordVisible = false
                        icon.name: passwordVisible ? "eye-off" : "eye"
                    }

                    PasswordBoxButton {
                        enabled: !root.context.unlockInProgress && passwordInput.text.length > 0
                        onClicked: {
                            root.context.tryUnlock();
                        }
                        icon.name: "arrow-right"
                    }
                }
            }

            Rectangle {
                id: activeIndicatorLine
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                implicitHeight: 2
                bottomLeftRadius: passwordInputWrapper.radius
                bottomRightRadius: passwordInputWrapper.radius
                topLeftRadius: 0
                topRightRadius: 0
                color: passwordInput.focus ? Looks.colors.accent : Looks.applyContentTransparency(Looks.darkColors.bg2Border)
            }
        }

        // Status & feedback row
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            Layout.bottomMargin: 104
            Layout.preferredWidth: passwordInputWrapper.implicitWidth
            spacing: 4

            WIndeterminateProgressBar {
                Layout.fillWidth: true
                visible: root.context.unlockInProgress
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                visible: passwordGroup.statusText.length > 0 && !root.context.unlockInProgress

                FluentIcon {
                    implicitSize: 14
                    icon: passwordGroup.statusIsError ? "warning" : "info"
                    color: passwordGroup.statusIsError ? Looks.darkColors.critical : Looks.darkColors.fg1
                }

                WText {
                    id: statusLabel
                    Layout.maximumWidth: passwordInputWrapper.implicitWidth - 24
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: passwordGroup.statusText
                    color: passwordGroup.statusIsError ? Looks.darkColors.critical : Looks.darkColors.fg1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }

    component PasswordBoxButton: WButton {
        id: pwBoxBtn
        implicitWidth: 28
        implicitHeight: 28
        horizontalPadding: 0
        verticalPadding: 0

        colBackground: "transparent"
        colBackgroundHover: Looks.applyContentTransparency(Looks.darkColors.bg2Hover)
        colBackgroundActive: Looks.applyContentTransparency(Looks.darkColors.bg2Active)
        fgColor: Looks.darkColors.fg

        contentItem: Item {
            FluentIcon {
                color: pwBoxBtn.fgColor
                anchors.centerIn: parent
                icon: pwBoxBtn.icon.name
                implicitSize: 16
            }
        }
    }
}
