import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// a base file for context menu that holds the common logic like functions and preadded things..

Loader {
    id: root

    property Item anchorItem: parent
    property bool isClosing: false
    property string headerText: ""
    property string headerSymbol: ""
    property Component headerIcon: null
    
    readonly property string dockPos: dock.dockEffectivePosition

    signal closed()

    function open() {
        if (active && !isClosing) return
        isClosing = false
        active = true
        if (root.item) root.item.startOpenAnimation()
    }

    function close() {
        if (!active || isClosing) return
        isClosing = true
        if (root.item) root.item.startCloseAnimation()
        else root.active = false
    }

    onActiveChanged: {
        if (!root.active) root.closed()
    }

    active: false
    visible: active

    sourceComponent: PopupWindow {
        id: popupWindow
        visible: true
        color: "transparent"

        property real dockMargin: -16
        property real shadowMargin: 20

        anchor {
            adjustment: PopupAdjustment.None
            window: root.anchorItem?.QsWindow.window
            onAnchoring: {
                const item = root.anchorItem
                if (!item) return
                const pos = root.dockPos
                const win = item.QsWindow.window
                const mapped = item.mapToItem(null, item.width / 2, item.height / 2)
                const dm = popupWindow.dockMargin
                const dockSize = (pos === "left" || pos === "right") ? win.width / 2 : win.height / 2

                if (pos === "bottom") {
                    anchor.rect.x = mapped.x - popupWindow.implicitWidth / 2
                    anchor.rect.y = mapped.y - dockSize - popupWindow.implicitHeight - dm
                } else if (pos === "top") {
                    anchor.rect.x = mapped.x - popupWindow.implicitWidth / 2
                    anchor.rect.y = mapped.y + dockSize + dm
                } else if (pos === "left") {
                    anchor.rect.x = mapped.x + dockSize + dm
                    anchor.rect.y = mapped.y - popupWindow.implicitHeight / 2
                } else {
                    anchor.rect.x = mapped.x - dockSize - popupWindow.implicitWidth - dm
                    anchor.rect.y = mapped.y - popupWindow.implicitHeight / 2
                }
            }
        }

        implicitWidth: menuContent.implicitWidth + popupWindow.shadowMargin * 2
        implicitHeight: menuContent.implicitHeight + popupWindow.shadowMargin * 2

        function startOpenAnimation() {
            motion.open()
        }

        function startCloseAnimation() {
            motion.close()
        }

        HyprlandFocusGrab {
            active: root.active && !root.isClosing
            windows: [popupWindow]
            onCleared: root.close()
        }

        StyledRectangularShadow {
            target: menuContent
            opacity: menuContent.opacity
            visible: menuContent.visible
        }

        Rectangle {
            id: menuContent
            property real menuMargin: 8
            anchors.centerIn: parent
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal

            implicitWidth: menuColumn.implicitWidth + (headerRow.Layout.leftMargin * 2) + (menuMargin * 2)
            implicitHeight: menuColumn.implicitHeight + headerRow.Layout.topMargin + menuMargin * 2

            opacity: 0.0
            scale: Appearance.animationCurves.arrowPopupScale

            // The menu belongs to the icon it was opened from, and the icon is
            // against the dock's edge, so it grows out of that edge -- the same
            // pivot DockTooltip and DockFolderPopup take (DESIGN.md 2.6). This
            // used to be Item.Center on a pair of Behaviors that ran the enter
            // and the exit on one spatial spec, which is not an exit at all (2.5).
            transformOrigin: {
                if (root.dockPos === "top") return Item.Top
                if (root.dockPos === "left") return Item.Left
                if (root.dockPos === "right") return Item.Right
                return Item.Bottom
            }

            ArrowPopupMotion {
                id: motion
                target: menuContent
                onClosed: {
                    root.active = false
                    root.isClosing = false
                }
            }

            Component.onCompleted: startOpenAnimation()

            // No Keys handler here on purpose: this is an xdg popup on the
            // dock's layer surface, which takes no keyboard focus, so Escape
            // never arrives. Giving it one means becoming an OnDemand panel of
            // its own, which is exactly what DockFolderPopup had to do and says
            // so at the top of that file. The focus grab handles the click.

            ColumnLayout {
                id: menuColumn
                anchors.fill: parent
                anchors.leftMargin: menuContent.menuMargin
                anchors.rightMargin: menuContent.menuMargin
                anchors.topMargin: menuContent.menuMargin / 2
                anchors.bottomMargin: menuContent.menuMargin
                spacing: 0

                Item {
                    id: headerRow
                    Layout.fillWidth: true
                    Layout.topMargin: menuContent.menuMargin
                    // 16dp, the law-11 gap that replaced the rule below.
                    Layout.bottomMargin: menuContent.menuMargin * 2
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    implicitHeight: headerRowLayout.implicitHeight
                    implicitWidth: headerRowLayout.implicitWidth

                    RowLayout {
                        id: headerRowLayout
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Loader {
                            active: !!root.headerIcon || root.headerSymbol !== ""
                            sourceComponent: root.headerIcon ? root.headerIcon : symbolComp
                        }

                        Component {
                            id: symbolComp
                            MaterialSymbol {
                                text: root.headerSymbol
                                iconSize: 22
                                color: Appearance.colors.colOnLayer0
                            }
                        }

                        StyledText {
                            text: root.headerText
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer0
                            font.weight: Font.DemiBold
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 200
                        }
                    }
                }

                // The header used to be ruled off from the rows with a 1px
                // border-coloured Rectangle. Law 11: sections separate by
                // whitespace on the 4dp grid, not by a line. headerRow already
                // carries menuMargin top and bottom, so removing the rule and
                // its own bottom margin leaves the gap doing the work.

                // Placeholder for content
                Loader {
                    id: contentLoader
                    Layout.fillWidth: true
                    sourceComponent: root.contentComponent
                }
            }
        }
    }

    property Component contentComponent: null
}
