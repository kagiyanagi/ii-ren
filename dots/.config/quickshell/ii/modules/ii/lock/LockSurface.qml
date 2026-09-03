import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.ii.bar as Bar
import Quickshell
import Quickshell.Services.SystemTray

MouseArea {
    id: root
    required property LockContext context
    property bool active: false
    property bool showInputField: active || context.currentText.length > 0
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower

    // Force focus on entry
    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => {
        forceFieldFocus();
    }
    onPositionChanged: mouse => {
        forceFieldFocus();
    }

    // Toolbar appearing animation
    property real toolbarScale: 0.9
    property real toolbarOpacity: 0
    Behavior on toolbarScale {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }
    Behavior on toolbarOpacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Init
    Component.onCompleted: {
        forceFieldFocus();
        toolbarScale = 1;
        toolbarOpacity = 1;
    }

    // Key presses
    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
        } 
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false;
        }
        forceFieldFocus();
    }

    // ── Lock screen widget pointer ───────────────────────────────────────────
    // This surface is above every layer shell, so the desktop widgets never see
    // its pointer. One proxy per widget, sitting exactly over it, doing nothing
    // but forwarding the gesture into the widget's own - which already owns
    // clamping, the grid, snapping and the config commit. No position state
    // lives here; that is what used to fight the widget and snap it back on
    // release.
    //
    // A widget that is *used* on the lock screen rather than only moved (the
    // notification list, say) sets `lockInteractive` and gets first refusal on
    // every press through the same proxy. It hands the gesture back by
    // returning false from lockPointerMove, which is how a horizontal
    // swipe-to-dismiss and a drag of the widget itself can share one press.
    Repeater {
        model: Config.options?.background?.activeWidgets ?? []

        delegate: MouseArea {
            id: dragProxy
            required property var modelData

            readonly property Item target: {
                GlobalStates.lockDragTargetsVersion; // re-resolve as widgets come and go
                const targets = GlobalStates.lockDragTargets;
                const suffix = `|${dragProxy.modelData.id}`;
                const own = targets[`${root.QsWindow.window?.screen?.name ?? ""}${suffix}`];
                if (own)
                    return own;
                // Whichever output registered it. Driving another screen's copy
                // beats refusing the drag: the commit is per widget, not per
                // screen, so the position still lands where it was dropped.
                for (const key in targets) {
                    if (key.endsWith(suffix))
                        return targets[key];
                }
                return null;
            }

            // The widget's own rectangle in scene coordinates, so any transform
            // on the desktop plane (overview zoom, parallax, lock zoom) is
            // already accounted for. Both surfaces cover the whole output, so
            // its scene coordinates are also this one's.
            readonly property rect targetRect: {
                if (!dragProxy.target)
                    return Qt.rect(0, 0, 0, 0);
                dragProxy.target.x;
                dragProxy.target.y;
                dragProxy.target.width;
                dragProxy.target.height;
                dragProxy.target.scale;
                const topLeft = dragProxy.target.mapToItem(null, 0, 0);
                const bottomRight = dragProxy.target.mapToItem(null, dragProxy.target.width, dragProxy.target.height);
                return Qt.rect(topLeft.x, topLeft.y, bottomRight.x - topLeft.x, bottomRight.y - topLeft.y);
            }

            // Centred widgets are placed by the lock screen itself, so there is
            // nothing to drag; `draggable` already covers the desktop-wide lock.
            // `lock.lockWidgetPositions` is the lock-screen-only freeze, kept
            // separate so it does not also lock the desktop copy.
            readonly property bool dragAllowed: (dragProxy.target?.draggable ?? false)
                && !Config.options.lock.lockWidgetPositions
                && (dragProxy.modelData.lockBehavior === "keep" || dragProxy.modelData.lockBehavior === "lockOnly")
            // Interaction survives the freeze: frozen positions are the point
            // at which a widget stops being furniture and starts being used.
            readonly property bool interactAllowed: (dragProxy.target?.lockInteractive ?? false)
                && dragProxy.modelData.lockBehavior !== "hide"

            property bool interacting: false
            property bool dragging: false
            property real pressSceneX: 0
            property real pressSceneY: 0

            enabled: dragProxy.dragAllowed || dragProxy.interactAllowed
            visible: enabled

            x: targetRect.x
            y: targetRect.y
            width: targetRect.width
            height: targetRect.height

            hoverEnabled: true
            preventStealing: true
            acceptedButtons: dragProxy.interactAllowed ? (Qt.LeftButton | Qt.MiddleButton) : Qt.LeftButton
            cursorShape: {
                if (dragProxy.interactAllowed && !dragProxy.dragging)
                    return dragProxy.pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor;
                return dragProxy.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor;
            }

            onPressed: mouse => {
                if (!dragProxy.target) {
                    root.forceFieldFocus();
                    return;
                }
                const p = dragProxy.mapToItem(null, mouse.x, mouse.y);
                dragProxy.pressSceneX = p.x;
                dragProxy.pressSceneY = p.y;
                dragProxy.interacting = false;
                dragProxy.dragging = false;

                if (dragProxy.interactAllowed)
                    dragProxy.interacting = dragProxy.target.lockPointerPress(p.x, p.y, mouse.button, mouse.modifiers);
                if (dragProxy.interacting)
                    return;
                if (!dragProxy.dragAllowed)
                    return;
                dragProxy.dragging = true;
                dragProxy.target.beginDragAt(p.x, p.y, mouse.modifiers & Qt.ControlModifier);
            }
            onPositionChanged: mouse => {
                if (!dragProxy.target)
                    return;
                const p = dragProxy.mapToItem(null, mouse.x, mouse.y);
                if (!dragProxy.pressed) {
                    if (dragProxy.interactAllowed)
                        dragProxy.target.lockPointerHover(p.x, p.y);
                    return;
                }
                if (dragProxy.interacting) {
                    if (dragProxy.target.lockPointerMove(p.x, p.y))
                        return;
                    // The widget gave the gesture back: it turned out to be a
                    // move, not something the widget itself responds to.
                    dragProxy.target.lockPointerCancel();
                    dragProxy.interacting = false;
                    if (!dragProxy.dragAllowed)
                        return;
                    dragProxy.dragging = true;
                    // From the original press point, so the widget does not
                    // jump by the travel already spent.
                    dragProxy.target.beginDragAt(dragProxy.pressSceneX, dragProxy.pressSceneY, mouse.modifiers & Qt.ControlModifier);
                }
                if (dragProxy.dragging)
                    dragProxy.target.moveDragTo(p.x, p.y, mouse.modifiers & Qt.ControlModifier);
            }
            onReleased: mouse => {
                if (!dragProxy.target)
                    return;
                const p = dragProxy.mapToItem(null, mouse.x, mouse.y);
                if (dragProxy.interacting) {
                    dragProxy.interacting = false;
                    dragProxy.target.lockPointerRelease(p.x, p.y, mouse.button);
                    root.forceFieldFocus();
                    return;
                }
                const moved = dragProxy.target.isDragging;
                dragProxy.dragging = false;
                dragProxy.target.endDrag(mouse.modifiers & Qt.ControlModifier);
                if (!moved)
                    root.forceFieldFocus();
            }
            onCanceled: {
                if (dragProxy.interacting) {
                    dragProxy.interacting = false;
                    dragProxy.target?.lockPointerCancel();
                }
                if (dragProxy.dragging) {
                    dragProxy.dragging = false;
                    dragProxy.target?.cancelDrag();
                }
            }
            onExited: {
                if (dragProxy.interactAllowed)
                    dragProxy.target?.lockPointerExit();
            }

            // "You can move this" - so it is wrong over a widget whose own
            // content answers the pointer with its own state layers.
            StateOverlay {
                anchors.fill: parent
                radius: Appearance.rounding.normal
                contentColor: Appearance.colors.colOnSurface
                hover: dragProxy.containsMouse && !dragProxy.pressed && !dragProxy.interactAllowed
                press: dragProxy.pressed && !dragProxy.interacting
            }

            // ── Resize grip ──────────────────────────────────────────────────
            // Same story as the drag proxy above: the widget's own resize grip
            // (AbstractBackgroundWidget's `resizeHandle`) never sees this
            // surface's pointer, so its corner gets its own small proxy here,
            // sized and positioned to match that grip exactly, forwarding into
            // the same beginResizeGesture/updateResizeGesture/endResizeGesture
            // the desktop grip drives.
            MouseArea {
                id: resizeProxy
                readonly property rect handleRect: {
                    if (!dragProxy.target)
                        return Qt.rect(0, 0, 0, 0);
                    dragProxy.target.x;
                    dragProxy.target.y;
                    dragProxy.target.width;
                    dragProxy.target.height;
                    dragProxy.target.scale;
                    // Matches resizeHandle's own anchors: right/bottom margin
                    // -6, 40x40, hanging off the widget's corner.
                    return dragProxy.target.mapToItem(null, dragProxy.target.width - 34, dragProxy.target.height - 34, 40, 40);
                }

                enabled: dragProxy.dragAllowed && (dragProxy.target?._scaleHandleAvailable ?? false)
                visible: enabled

                x: handleRect.x - dragProxy.x
                y: handleRect.y - dragProxy.y
                width: handleRect.width
                height: handleRect.height
                z: 1

                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.SizeFDiagCursor

                onPressed: mouse => {
                    if (!dragProxy.target)
                        return;
                    const p = resizeProxy.mapToItem(null, mouse.x, mouse.y);
                    dragProxy.target.beginResizeGesture(p.x, p.y, mouse.modifiers & Qt.ShiftModifier);
                }
                onPositionChanged: mouse => {
                    if (!dragProxy.target)
                        return;
                    const p = resizeProxy.mapToItem(null, mouse.x, mouse.y);
                    dragProxy.target.updateResizeGesture(p.x, p.y, mouse.modifiers & Qt.ShiftModifier);
                }
                onReleased: dragProxy.target?.endResizeGesture()
                onCanceled: dragProxy.target?.endResizeGesture()
                onDoubleClicked: dragProxy.target?.resetScaleFromHandle()

                Rectangle {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -3
                    anchors.verticalCenterOffset: -3
                    width: 22
                    height: 22
                    radius: Appearance.rounding.verysmall
                    color: (resizeProxy.pressed || resizeProxy.containsMouse)
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSecondaryContainer
                    opacity: (dragProxy.containsMouse || resizeProxy.containsMouse || resizeProxy.pressed) ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "open_in_full"
                        iconSize: 13
                        color: (resizeProxy.pressed || resizeProxy.containsMouse)
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }

    // Main toolbar: password box
    Toolbar {
        id: mainIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 20
        }
        Behavior on anchors.bottomMargin {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        // Fingerprint
        Loader {
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            Layout.alignment: Qt.AlignVCenter
            active: root.context.fingerprintsConfigured
            visible: active

            sourceComponent: MaterialSymbol {
                id: fingerprintIcon
                fill: 1
                text: "fingerprint"
                iconSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        ToolbarTextField {
            id: passwordBox
            Layout.rightMargin: -Layout.leftMargin
            placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")

            // Style
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
            selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

            // Password
            enabled: !root.context.unlockInProgress
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData

            // Synchronizing (across monitors) and unlocking
            onTextChanged: root.context.currentText = this.text
            onAccepted: {
                root.context.tryUnlock(ctrlHeld);
            }
            Connections {
                target: root.context
                function onCurrentTextChanged() {
                    passwordBox.text = root.context.currentText;
                }
            }

            Keys.onPressed: event => {
                root.context.resetClearTimer();
            }
            
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: passwordBox.width - 8
                    height: passwordBox.height
                    radius: height / 2
                }
            }

            // Shake when wrong password
            ErrorShakeAnimation {
                id: wrongPasswordShakeAnim
                target: passwordBox
            }
            Connections {
                target: GlobalStates
                function onScreenUnlockFailedChanged() {
                    if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
                }
            }

            // We're drawing dots manually
            property bool materialShapeChars: Config.options.lock.materialShapeChars
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
            Loader {
                active: passwordBox.materialShapeChars
                anchors {
                    fill: parent
                    leftMargin: passwordBox.padding
                    rightMargin: passwordBox.padding
                }
                sourceComponent: PasswordChars {
                    length: root.context.currentText.length
                    selectionStart: passwordBox.selectionStart
                    selectionEnd: passwordBox.selectionEnd
                    cursorPosition: passwordBox.cursorPosition
                }
            }
        }

        ToolbarButton {
            id: confirmButton
            implicitWidth: height
            toggled: true
            enabled: !root.context.unlockInProgress
            colBackgroundToggled: Appearance.colors.colPrimary

            onClicked: root.context.tryUnlock()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: 24
                text: {
                    if (root.context.targetAction === LockContext.ActionEnum.Unlock) {
                        return root.ctrlHeld ? "local_cafe" : "arrow_right_alt";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                        return "power_settings_new";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                        return "restart_alt";
                    }
                }
                color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }
        }
    }

    // Left toolbar
    Toolbar {
        id: leftIsland
        anchors {
            right: mainIsland.left
            top: mainIsland.top
            bottom: mainIsland.bottom
            rightMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        // Username
        IconAndTextPair {
            Layout.leftMargin: 8
            icon: "account_circle"
            text: SystemInfo.username
        }

        // Keyboard layout (Xkb)
        Loader {
            Layout.rightMargin: 8
            Layout.fillHeight: true

            active: true
            visible: active

            sourceComponent: Row {
                spacing: 8

                MaterialSymbol {
                    id: keyboardIcon
                    anchors.verticalCenter: parent.verticalCenter
                    fill: 1
                    text: "keyboard_alt"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnSurfaceVariant
                }
                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: StyledText {
                        text: HyprlandXkb.currentLayoutCode
                        color: Appearance.colors.colOnSurfaceVariant
                        animateChange: true
                    }
                }
            }
        }

        // Keyboard layout (Fcitx)
        Bar.SysTray {
            Layout.rightMargin: 10
            Layout.alignment: Qt.AlignVCenter
            showSeparator: false
            showOverflowMenu: false
            pinnedItems: SystemTray.items.values.filter(i => i.id == "Fcitx")
            visible: pinnedItems.length > 0
        }
    }

    // Right toolbar
    Toolbar {
        id: rightIsland
        anchors {
            left: mainIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
            leftMargin: 10
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        IconAndTextPair {
            visible: Battery.available
            icon: Battery.isCharging ? "bolt" : "battery_android_full"
            text: Math.round(Battery.percentage * 100)
            color: (Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
        }

        IconToolbarButton {
            id: sleepButton
            onClicked: Session.suspend()
            text: "dark_mode"
        }

        PasswordGuardedIconToolbarButton {
            id: powerButton
            text: "power_settings_new"
            targetAction: LockContext.ActionEnum.Poweroff
        }

        PasswordGuardedIconToolbarButton {
            id: rebootButton
            text: "restart_alt"
            targetAction: LockContext.ActionEnum.Reboot
        }
    }

    component PasswordGuardedIconToolbarButton: IconToolbarButton {
        id: guardedBtn
        required property var targetAction

        toggled: root.context.targetAction === guardedBtn.targetAction

        onClicked: {
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedBtn.targetAction);
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }

    component IconAndTextPair: Row {
        id: pair
        required property string icon
        required property string text
        property color color: Appearance.colors.colOnSurfaceVariant

        spacing: 4
        Layout.fillHeight: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: pair.icon
            iconSize: Appearance.font.pixelSize.huge
            animateChange: true
            color: pair.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: pair.text
            color: pair.color
        }
    }
}
