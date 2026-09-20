pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root
    required property QsMenuHandle trayItemMenuHandle
    property string trayItemId: ""
    property real popupBackgroundMargin: 0

    signal menuClosed
    signal menuOpened(qsWindow: var) // Correct type is QsWindow, but QML does not like that

    color: "transparent"
    property real padding: Appearance.sizes.elevationMargin
    // Held open while the exit runs, so the window still has something to draw.
    property bool closing: false

    implicitHeight: {
        let result = 0;
        for (let child of stackView.children) {
            result = Math.max(child.implicitHeight, result);
        }
        return result + popupBackground.padding * 2 + root.padding * 2;
    }
    implicitWidth: {
        let result = 0;
        for (let child of stackView.children) {
            result = Math.max(child.implicitWidth, result);
        }
        return result + popupBackground.padding * 2 + root.padding * 2;
    }

    function open() {
        closeAnim.stop();
        root.closing = false;
        root.visible = true;
        openAnim.restart();
        root.menuOpened(root);
    }

    function close() {
        if (root.closing || !root.visible)
            return;
        root.closing = true;
        openAnim.stop();
        closeAnim.restart();
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if ((event.button === Qt.BackButton || event.button === Qt.RightButton) && stackView.depth > 1)
                stackView.pop();
        }

        StyledRectangularShadow {
            target: popupBackground
            // anchors.fill does not follow a scale transform, so without these the
            // shadow sits full size around a half-size card.
            opacity: popupBackground.opacity
            scale: popupBackground.scale
            transformOrigin: popupBackground.transformOrigin
        }

        Rectangle {
            id: popupBackground
            readonly property real padding: 6
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: Config.options.bar.vertical ? parent.verticalCenter : undefined
                top: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? undefined : parent.top
                bottom: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? parent.bottom : undefined
                margins: root.padding
            }

            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.large
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

            implicitWidth: stackView.implicitWidth + popupBackground.padding * 2
            implicitHeight: stackView.implicitHeight + popupBackground.padding * 2

            opacity: 0
            scale: Appearance.animationCurves.arrowPopupScale
            // ArrowPopup.setPivotForOpenCloseAnimation(): the card grows out of
            // the edge nearest the tray icon that opened it, which is whichever
            // edge `anchor.edges` in SysTrayItem stuck to the bar (DESIGN 2.6).
            transformOrigin: {
                if (Config.options.bar.vertical)
                    return Config.options.bar.bottom ? Item.Right : Item.Left;
                return Config.options.bar.bottom ? Item.Bottom : Item.Top;
            }

            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            // The §9 popup/context-menu recipe, from Appearance.animationCurves.arrowPopup*.
            ParallelAnimation {
                id: openAnim

                SequentialAnimation {
                    NumberAnimation {
                        target: popupBackground
                        property: "scale"
                        from: Appearance.animationCurves.arrowPopupScale
                        to: Appearance.animationCurves.arrowPopupOvershoot
                        duration: Appearance.animationCurves.arrowPopupScaleDuration
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                    NumberAnimation {
                        target: popupBackground
                        property: "scale"
                        to: 1
                        duration: Appearance.animationCurves.arrowPopupScaleDuration
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Appearance.animationCurves.arrowPopupSettle
                    }
                }
                NumberAnimation {
                    target: popupBackground
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Appearance.animationCurves.arrowPopupFadeDuration
                }
            }

            ParallelAnimation {
                id: closeAnim

                NumberAnimation {
                    target: popupBackground
                    property: "scale"
                    to: Appearance.animationCurves.arrowPopupScale
                    duration: Appearance.animationCurves.arrowPopupCloseDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                }
                SequentialAnimation {
                    PauseAnimation {
                        duration: Appearance.animationCurves.arrowPopupFadeHold
                    }
                    NumberAnimation {
                        target: popupBackground
                        property: "opacity"
                        to: 0
                        duration: Appearance.animationCurves.arrowPopupFadeDuration
                    }
                }

                onFinished: {
                    root.visible = false;
                    root.closing = false;
                    while (stackView.depth > 1)
                        stackView.pop();
                    root.menuClosed();
                }
            }

            StackView {
                id: stackView
                anchors {
                    fill: parent
                    margins: popupBackground.padding
                }
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}

                implicitWidth: currentItem.implicitWidth
                implicitHeight: currentItem.implicitHeight

                initialItem: SubMenu {
                    handle: root.trayItemMenuHandle
                }
            }
        }
    }

    component NoAnim: Transition {
        NumberAnimation {
            duration: 0
        }
    }

    // A menu row: the back and pin entries are the same button with a different
    // icon and label, and both need the same keyboard walk as the app's own rows.
    component MenuActionButton: RippleButton {
        id: actionButton
        property string symbolName: ""
        property string labelText: ""

        buttonRadius: popupBackground.radius - popupBackground.padding
        horizontalPadding: 12
        implicitWidth: actionRow.implicitWidth + horizontalPadding * 2
        implicitHeight: 36
        focusPolicy: Qt.StrongFocus
        Layout.fillWidth: true

        Keys.onUpPressed: actionButton.nextItemInFocusChain(false)?.forceActiveFocus(Qt.TabFocusReason)
        Keys.onDownPressed: actionButton.nextItemInFocusChain(true)?.forceActiveFocus(Qt.TabFocusReason)
        Keys.onReturnPressed: actionButton.releaseAction()
        Keys.onEnterPressed: actionButton.releaseAction()
        Keys.onSpacePressed: actionButton.releaseAction()

        contentItem: RowLayout {
            id: actionRow
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                right: parent.right
                leftMargin: actionButton.horizontalPadding
                rightMargin: actionButton.horizontalPadding
            }
            spacing: 8

            MaterialSymbol {
                iconSize: 20
                text: actionButton.symbolName
            }

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smallie
                text: actionButton.labelText
            }
        }
    }

    component SubMenu: ColumnLayout {
        id: submenu
        required property QsMenuHandle handle
        property bool isSubMenu: false
        property bool shown: false

        // DESIGN 2.9: a Behavior cannot read its own direction, so the spec is
        // picked inside the binding that drives it, which runs first.
        property real fadeDuration: Appearance.animation.elementMoveFast.duration
        opacity: {
            submenu.fadeDuration = submenu.shown ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveExit.duration;
            return submenu.shown ? 1 : 0;
        }

        Behavior on opacity {
            NumberAnimation {
                duration: submenu.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }

        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        // DESIGN 3.7. Hyprland's focus grab enters one of its whitelisted
        // surfaces (hyprland-focus-grab-v1), and SysTray already whitelists the
        // menu window, so the keystrokes reach here while the menu is up.
        // Nothing holds focus at first, so the first Down seeds it into the top
        // row; after that each row walks the chain itself.
        focus: true
        Keys.onEscapePressed: event => {
            root.close();
            event.accepted = true;
        }
        Keys.onDownPressed: submenu.nextItemInFocusChain(true)?.forceActiveFocus(Qt.TabFocusReason)
        Keys.onUpPressed: submenu.nextItemInFocusChain(false)?.forceActiveFocus(Qt.TabFocusReason)
        Keys.onLeftPressed: if (stackView.depth > 1)
            stackView.pop()

        QsMenuOpener {
            id: menuOpener
            menu: submenu.handle
        }

        spacing: 0

        Loader {
            Layout.fillWidth: true
            visible: submenu.isSubMenu
            active: visible
            sourceComponent: MenuActionButton {
                symbolName: "chevron_left"
                labelText: Translation.tr("Back")
                releaseAction: () => stackView.pop()
            }
        }

        MenuActionButton {
            symbolName: "push_pin"
            labelText: TrayService.isPinned(root.trayItemId) ? Translation.tr("Unpin") : Translation.tr("Pin")
            visible: root.trayItemId !== undefined && root.trayItemId.length > 0 && stackView.depth === 1
            // Whitespace, not a rule, separates the shell's own rows from the
            // app's (design law 11).
            Layout.bottomMargin: 4
            releaseAction: () => TrayService.togglePin(root.trayItemId)
        }

        Repeater {
            id: menuEntriesRepeater
            property bool iconColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].icon.length > 0)
                        return true;
                }
                return false;
            }
            property bool specialInteractionColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].buttonType !== QsMenuButtonType.None)
                        return true;
                }
                return false;
            }
            model: menuOpener.children
            delegate: SysTrayMenuEntry {
                required property QsMenuEntry modelData
                forceIconColumn: menuEntriesRepeater.iconColumnNeeded
                forceSpecialInteractionColumn: menuEntriesRepeater.specialInteractionColumnNeeded
                menuEntry: modelData

                buttonRadius: popupBackground.radius - popupBackground.padding

                onDismiss: root.close()
                onOpenSubmenu: handle => {
                    stackView.push(subMenuComponent.createObject(null, {
                        handle: handle,
                        isSubMenu: true
                    }));
                }
            }
        }
    }

    Component {
        id: subMenuComponent
        SubMenu {}
    }
}
