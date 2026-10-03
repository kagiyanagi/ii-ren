pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ComboBox {
    id: root

    property string buttonIcon: ""
    // 4.1: through the token, or sharp mode leaves this one pill-shaped.
    property real buttonRadius: Appearance.rounding.full
    property color colBackground: Appearance.colors.colSecondaryContainer
    property color colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    property color colBackgroundActive: Appearance.colors.colSecondaryContainerActive
    property string searchText: ""

    property int visibleCount: {
        if (!root.searchText || root.searchText.length === 0) 
            return root.model?.length ?? 0
        return (root.model ?? []).filter(item => {
            const display = typeof item === "object" ? (item[root.textRole] ?? "") : String(item)
            return display.toLowerCase().includes(root.searchText.toLowerCase())
        }).length
    }

    implicitHeight: 40
    Layout.fillWidth: true

    opacity: root.enabled ? 1 : 0.4 // 3.1: disabled is the whole control
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    background: Rectangle {
        radius: root.buttonRadius
        color: (root.down && !root.popup.visible) ? root.colBackgroundActive : root.hovered ? root.colBackgroundHover : root.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Hover and press are the colour above; focus is the one state the
        // container colours have no sibling for, so it composites on top (3.1).
        StateOverlay {
            anchors.fill: parent
            topLeftRadius: root.buttonRadius
            topRightRadius: root.buttonRadius
            bottomLeftRadius: root.buttonRadius
            bottomRightRadius: root.buttonRadius
            contentColor: Appearance.colors.colOnSecondaryContainer
            focused: root.visualFocus
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }

    indicator: MaterialSymbol {
        x: root.width - width - 16
        y: root.height / 2 - height / 2
        text: "keyboard_arrow_down"
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnSecondaryContainer

        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    contentItem: Item {
        implicitWidth: buttonLayout.implicitWidth
        implicitHeight: buttonLayout.implicitHeight

        RowLayout {
            id: buttonLayout
            anchors.fill: parent
            spacing: 8
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.buttonIcon.length > 0 || (root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon)
                visible: active
                sourceComponent: MaterialSymbol {
                    text: {
                        if (root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon) {
                            return root.model[root.currentIndex].icon;
                        }
                        return root.buttonIcon;
                    }
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnSecondaryContainer
                text: root.displayText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    delegate: ItemDelegate {
        id: itemDelegate
        width: ListView.view ? ListView.view.width : root.width
        implicitHeight: visible ? 40 : 0
        visible: {
            if (!root.searchText || root.searchText.length === 0) return true
            const display = typeof model === "object" ? (model[root.textRole] ?? "") : String(model)
            return display.toLowerCase().includes(root.searchText.toLowerCase())
        }

        required property var model
        required property int index
        // The search field's arrow keys move the view's current index and
        // nothing rendered it, so typing then arrowing picked a row you could
        // not see (3.1, 3.7).
        highlighted: itemDelegate.ListView.view?.currentIndex === itemDelegate.index

        property color color: {
            if (root.currentIndex === itemDelegate.index) {
                if (itemDelegate.down) return Appearance.colors.colSecondaryContainerActive;
                if (itemDelegate.hovered || itemDelegate.highlighted) return Appearance.colors.colSecondaryContainerHover;
                return Appearance.colors.colSecondaryContainer;
            } else {
                if (itemDelegate.down) return Appearance.colors.colLayer3Active;
                if (itemDelegate.hovered || itemDelegate.highlighted) return Appearance.colors.colLayer3Hover;
                return ColorUtils.transparentize(Appearance.colors.colLayer3);
            }
        }
        property color colText: (root.currentIndex === itemDelegate.index) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3

        background: Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: itemDelegate.color
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
            }
        }

        contentItem: RowLayout {
            spacing: 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            Loader {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: Appearance.font.pixelSize.larger
                active: typeof itemDelegate.model === 'object' && itemDelegate.model?.icon?.length > 0
                visible: active
                sourceComponent: Item {
                    implicitWidth: icon.implicitWidth
                    implicitHeight: Appearance.font.pixelSize.larger
                    MaterialSymbol {
                        id: icon
                        anchors.centerIn: parent
                        text: itemDelegate.model?.icon ?? ""
                        iconSize: Appearance.font.pixelSize.larger
                        color: itemDelegate.colText
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.font.pixelSize.larger
                color: itemDelegate.colText
                text: itemDelegate.model[root.textRole]
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    popup: Popup {
        y: root.height + 10 // 5.3: a popup sits 10 from the thing it anchors to
        width: root.width
        clip: true
        height: Math.min(
            searchField.implicitHeight + 20 + (root.visibleCount * 42) + topPadding + bottomPadding,
            320
        )
        padding: 12 // 5.2, and it keeps the first row clear of a verylarge corner
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        // The list drops out of the field, so the field's edge is the origin (2.6).
        transformOrigin: Item.Top

        onVisibleChanged: {
            if (visible) {
                searchField.forceActiveFocus()
            } else {
                root.searchText = ""
                searchField.text = ""
            }
        }

        // The ArrowPopup recipe, from Appearance.animationCurves.arrowPopup*.
        // This was one fade, the same duration in both directions, which is
        // neither the popup motion 9 asks for nor an enter/exit pair (2.5).
        enter: Transition {
            ParallelAnimation {
                SequentialAnimation {
                    NumberAnimation {
                        property: "scale"
                        from: Appearance.animationCurves.arrowPopupScale
                        to: Appearance.animationCurves.arrowPopupOvershoot
                        duration: Appearance.animationCurves.arrowPopupScaleDuration
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                    NumberAnimation {
                        property: "scale"
                        to: 1
                        duration: Appearance.animationCurves.arrowPopupScaleDuration
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Appearance.animationCurves.arrowPopupSettle
                    }
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Appearance.animationCurves.arrowPopupFadeDuration
                }
            }
        }

        exit: Transition {
            ParallelAnimation {
                NumberAnimation {
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
                        property: "opacity"
                        to: 0
                        duration: Appearance.animationCurves.arrowPopupFadeDuration
                    }
                }
            }
        }

        background: Item {
            StyledRectangularShadow { target: popupBackground }
            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.verylarge // 9: popup radius
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: ColumnLayout {
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: searchField.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 6

                    MaterialSymbol {
                        Layout.leftMargin: 6
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Search")
                        // The colours a bare TextField neglects, the same ones
                        // StyledTextInput fills in -- the placeholder and the
                        // selection were coming from the Qt default palette.
                        color: Appearance.colors.colOnLayer1
                        placeholderTextColor: Appearance.m3colors.m3outline
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        background: null
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.hintingPreference: Font.PreferFullHinting
                        font.variableAxes: Appearance.font.variableAxes.main
                        HoverHandler { cursorShape: Qt.IBeamCursor } // 3.4
                        onTextChanged: root.searchText = text
                        Keys.onDownPressed: listView.incrementCurrentIndex()
                        Keys.onUpPressed: listView.decrementCurrentIndex()
                        // 3.7: the field has the focus, so Escape has to be let
                        // past it for the popup's CloseOnEscape to see it.
                        Keys.onEscapePressed: event => {
                            root.popup.close();
                            event.accepted = true;
                        }
                        Keys.onReturnPressed: {
                            if (listView.currentIndex >= 0) {
                                root.currentIndex = listView.currentIndex
                                root.popup.close()
                            }
                        }
                    }

                    MaterialSymbol {
                        visible: searchField.text.length > 0
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                        Layout.rightMargin: 6
                        MouseArea {
                            // 3.4: the glyph is 16, the target is 32. Expand the
                            // area, not the paint.
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = ""
                                searchField.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            StyledListView {
                id: listView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 320 - searchField.implicitHeight - 8 - 46)
                clip: true
                spacing: 2
                model: root.popup.visible ? root.delegateModel : null
                currentIndex: root.highlightedIndex
            }
        }
    }
}