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
        function onUnlockInProgressChanged() {
            // The field is disabled while PAM answers, and a disabled item loses
            // keyboard focus with nothing to give it back: a wrong password used
            // to eat every keystroke after it until the pointer moved.
            if (!root.context.unlockInProgress)
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

    // Init
    Component.onCompleted: {
        forceFieldFocus();
        // Caps Lock can already be on when the screen locks.
        HyprlandXkb.refreshLockKeys();
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
        if (event.key === Qt.Key_CapsLock) {
            // Hyprland has no event for this and flips the lock on the key
            // down, so the only moment worth asking at is right here.
            HyprlandXkb.refreshLockKeys();
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

    /*
     * Why the password cannot work, when there is a reason for it.
     *
     * PAM has first claim. After three wrong passwords pam_faillock refuses the
     * next ones before pam_unix ever sees them, for `unlock_time` seconds, and
     * it says so -- but into a conversation nothing was reading, so the screen
     * shook and said "Incorrect password" about a password it had not checked.
     * Caps Lock second: the ordinary reason, and the one a shake never explains
     * either.
     */
    readonly property string statusText: {
        if (root.context.authMessage.length > 0)
            return root.context.authMessage;
        if (HyprlandXkb.capsLock)
            return Translation.tr("Caps Lock is on");
        return "";
    }
    readonly property bool statusFromPam: root.context.authMessage.length > 0

    Rectangle {
        id: statusChip
        readonly property bool shown: root.statusText.length > 0
        // As wide as the row it belongs to, and never past the 8dp the screen
        // edge gets (5.3) on a display too narrow to hold that row.
        readonly property real maxWidth: Math.min(rightIsland.x + rightIsland.width - leftIsland.x, root.width - 16)

        anchors {
            horizontalCenter: mainIsland.horizontalCenter
            bottom: mainIsland.top
            bottomMargin: 10
        }
        implicitWidth: statusRow.implicitWidth + 24
        implicitHeight: statusRow.implicitHeight + 12

        // A pill while it is one line, and a card once it wraps: `full` on a
        // box three lines tall is an arc that eats the first and last of them
        // (5.6), which is exactly what faillock's two sentences did.
        radius: statusLabel.lineCount > 1 ? Appearance.rounding.large : Appearance.rounding.full

        // The error container for anything PAM says, whatever severity it
        // claims: faillock sends the lockout as info, and a lockout is not
        // information, it is the reason nothing the user types will work.
        color: root.statusFromPam ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainer
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // It is about the island below it, so it grows out of it (2.6). Enter
        // decelerating and spatial with the fade on the effects spec, exit
        // faster on the exit spec -- the same pair the islands use.
        transformOrigin: Item.Bottom
        opacity: 0
        scale: 0.9
        visible: opacity > 0

        onShownChanged: {
            chipEnter.stop();
            chipExit.stop();
            if (statusChip.shown)
                chipEnter.start();
            else
                chipExit.start();
        }

        ParallelAnimation {
            id: chipEnter
            NumberAnimation {
                target: statusChip
                property: "scale"
                to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            NumberAnimation {
                target: statusChip
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        ParallelAnimation {
            id: chipExit
            NumberAnimation {
                target: statusChip
                property: "scale"
                to: 0.9
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            NumberAnimation {
                target: statusChip
                property: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
        }

        RowLayout {
            id: statusRow
            anchors.centerIn: parent
            spacing: 8

            MaterialSymbol {
                id: statusIcon
                Layout.alignment: Qt.AlignVCenter
                fill: 1
                text: root.statusFromPam ? "error" : "keyboard_capslock"
                iconSize: Appearance.font.pixelSize.huge
                color: root.statusFromPam ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                id: statusLabel
                // Wrapped rather than elided: faillock's two sentences are
                // longer than the field, and half of "(9 minutes left to
                // unlock)" is worse than a second line.
                Layout.maximumWidth: statusChip.maxWidth - 24 - statusIcon.implicitWidth - statusRow.spacing
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: root.statusText
                color: root.statusFromPam ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    // Main toolbar: password box
    LockIsland {
        id: mainIsland
        staggerIndex: 0
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 20
        }

        // Fingerprint
        Loader {
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            Layout.alignment: Qt.AlignVCenter
            active: root.context.fingerprintsConfigured && Config.options.lock.security.fingerprint.showIndicator
            visible: active

            sourceComponent: ColumnLayout {
                spacing: 2

                // Balances the attempt dots below, so the icon sits on the
                // toolbar's centre line instead of riding high by half the
                // dot row. The dots keep their space whether or not they are
                // showing — otherwise the icon would hop the first time a
                // finger failed.
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 0
                    implicitHeight: attemptDots.implicitHeight
                }

                MaterialSymbol {
                    id: fingerprintIcon
                    Layout.alignment: Qt.AlignHCenter
                    fill: 1
                    text: root.context.fingerprintExhausted ? "fingerprint_off" : "fingerprint"
                    iconSize: Appearance.font.pixelSize.hugeass
                    // Tinted while the reader is actually listening, so the
                    // icon says "armed" rather than just "this laptop has a
                    // sensor". fingerNeeded is best-effort — a driver that
                    // never sets it simply leaves the icon in its resting
                    // colour, which is what it did before.
                    color: root.context.fingerprintFailed ? Appearance.colors.colError : root.context.fingerprintExhausted ? Appearance.colors.colSubtext : Fingerprint.fingerNeeded ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    // Swells while the sensor has a finger on it. This is the
                    // whole point of watching finger-present: a press reader
                    // takes a moment to decide, and without this the screen
                    // gives nothing back until PAM finally answers.
                    //
                    // Scale is spatial, so clickBounce's overshoot is wanted —
                    // it is the same acknowledgement a button press gets.
                    transformOrigin: Item.Center
                    scale: Fingerprint.fingerPresent ? 1.12 : 1

                    Behavior on scale {
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }

                    // Same shake the password field gets, so a finger that did
                    // not match reads the same as a password that did not.
                    ErrorShakeAnimation {
                        id: fingerprintShakeAnim
                        target: fingerprintIcon
                    }
                    Connections {
                        target: root.context
                        function onFingerprintFailedChanged() {
                            if (root.context.fingerprintFailed)
                                fingerprintShakeAnim.restart();
                        }
                    }
                }

                // One dot per attempt, spent ones going red. pam_fprintd stops
                // listening after the last one, and a reader that has quietly
                // stopped listening is worse than one that says so.
                RowLayout {
                    id: attemptDots
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4
                    opacity: root.context.fingerprintAttempts > 0 ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Repeater {
                        model: root.context.fingerprintMaxAttempts

                        delegate: Rectangle {
                            id: attemptDot
                            required property int index
                            readonly property bool spent: attemptDot.index >= (root.context.fingerprintMaxAttempts - root.context.fingerprintAttempts)

                            implicitWidth: 4
                            implicitHeight: 4
                            radius: Appearance.rounding.full
                            color: attemptDot.spent ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }
        }

        ToolbarTextField {
            id: passwordBox
            // The confirm icon already says power off; this still said "Enter
            // password", which made it the one part of the surface that lied
            // about what the key was about to do.
            placeholderText: {
                if (GlobalStates.screenUnlockFailed)
                    return Translation.tr("Incorrect password");
                if (root.context.targetAction === LockContext.ActionEnum.Poweroff)
                    return Translation.tr("Password to power off");
                if (root.context.targetAction === LockContext.ActionEnum.Reboot)
                    return Translation.tr("Password to restart");
                return Translation.tr("Enter password");
            }

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
            colBackgroundToggled: Appearance.colors.colPrimary

            // Busy is not disabled. `enabled: false` was here to stop a second
            // Enter landing while PAM answers the first, and it paid for that
            // with the 0.4 disabled treatment (3.1) over the only saturated
            // thing on the surface -- exactly when it has something to say. The
            // guard does that job and the fill stays up.
            onClicked: {
                if (root.context.unlockInProgress)
                    return;
                root.context.tryUnlock();
            }

            contentItem: Item {
                MaterialSymbol {
                    id: confirmIcon
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
                    color: Appearance.colors.colOnPrimary

                    opacity: root.context.unlockInProgress ? 0 : 1
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                // pam_unix sits on a wrong password for a couple of seconds, and
                // until it answered the surface gave back nothing at all. The
                // M3E indicator rather than CircularProgress: that one is the
                // shared tranche's single `layer.enabled`, and this surface has
                // already spent its one effect on the field's mask. The Loader
                // is inactive whenever PAM is not working, so it costs nothing
                // the rest of the time.
                Loader {
                    anchors.centerIn: parent
                    active: root.context.unlockInProgress
                    sourceComponent: MaterialLoadingIndicator {
                        implicitSize: confirmIcon.iconSize
                        color: "transparent"
                        shapeColor: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }

    // Left toolbar
    LockIsland {
        id: leftIsland
        staggerIndex: 1
        anchors {
            right: mainIsland.left
            top: mainIsland.top
            bottom: mainIsland.bottom
            rightMargin: 10
        }

        // Username
        IconAndTextPair {
            Layout.leftMargin: 8
            icon: "account_circle"
            text: SystemInfo.username
        }

        // Keyboard layout (Xkb)
        Row {
            Layout.rightMargin: 8
            Layout.fillHeight: true
            spacing: 8

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                fill: 1
                text: "keyboard_alt"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: HyprlandXkb.currentLayoutCode
                color: Appearance.colors.colOnSurfaceVariant
                animateChange: true
            }
        }

        // Keyboard layout (Fcitx)
        Bar.SysTray {
            Layout.rightMargin: 10
            Layout.alignment: Qt.AlignVCenter
            showOverflowMenu: false
            pinnedItems: SystemTray.items.values.filter(i => i.id == "Fcitx")
            visible: pinnedItems.length > 0
        }
    }

    // Right toolbar
    LockIsland {
        id: rightIsland
        staggerIndex: 1
        anchors {
            left: mainIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
            leftMargin: 10
        }

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

    /*
     * One island of the bottom row. All three move the same way and only differ
     * in when they start, so the recipe lives here rather than three times:
     *
     * - They are anchored to the bottom edge, so they grow out of it (2.6), not
     *   out of their own middle.
     * - Enter is spatial and decelerating and may overshoot; the fade under it
     *   is the effects spec and may not. The centre goes first and the flanks a
     *   stagger step later (2.8) -- the eye lands where the password goes.
     * - Exit is scale only, faster and without the stagger, because the user has
     *   already decided (2.5). The fade out belongs to the whole surface and is
     *   done once, by the Loader in LockScreen.qml, which is also what holds the
     *   compositor's session lock open long enough for this to be seen.
     */
    component LockIsland: Toolbar {
        id: island
        required property int staggerIndex

        transformOrigin: Item.Bottom
        scale: 0.9
        opacity: 0

        SequentialAnimation {
            id: islandEnter
            running: true

            PauseAnimation {
                duration: island.staggerIndex * Appearance.animation.staggerStep
            }
            ParallelAnimation {
                NumberAnimation {
                    target: island
                    property: "scale"
                    to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
                NumberAnimation {
                    target: island
                    property: "opacity"
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }

        NumberAnimation {
            id: islandExit
            target: island
            property: "scale"
            to: 0.9
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }

        Connections {
            target: GlobalStates
            function onScreenLockExitingChanged() {
                if (!GlobalStates.screenLockExiting)
                    return;
                islandEnter.stop();
                islandExit.start();
            }
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
