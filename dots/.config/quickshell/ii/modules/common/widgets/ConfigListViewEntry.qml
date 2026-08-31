import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: wrapper
    
    required property var modelData
    readonly property var compInfo: BarComponentRegistry.getComponent(modelData.id)

    property bool alternateColor: visualIndex % 2 == 0
    property color colBackground: alternateColor ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2
    property color colHover: alternateColor ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer2Hover
    property color colActive: alternateColor ? Appearance.colors.colLayer3Active : Appearance.colors.colLayer2Active

    property color colTitle: Appearance.colors.colOnLayer0

    property int barSection
    readonly property bool expanded: root.isEntryExpanded(visualIndex)
    readonly property bool isSpacer: Boolean(modelData && (modelData.id === "sacebar" || modelData.id === "spacebar"))

    anchors {
        right: parent?.right
        left: parent?.left
    }
    height: content.height
    property int visualIndex: DelegateModel.itemsIndex


    Behavior on y {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    function getOrderedList() {
        var ordered = []

        for (var i = 0; i < visualModel.items.count; i++) {
            var item = visualModel.items.get(i).model
            ordered.push(item.modelData)
        }

        return ordered
    }

    function updateSpacebarConfig(newStyle, newLeft, newRight) {
        let arr = wrapper.getOrderedList()
        let item = Object.assign({}, arr[wrapper.visualIndex])
        if (newStyle !== undefined) {
            item.style = newStyle
            modelData.style = newStyle
        }
        if (newLeft !== undefined) {
            item.leftPadding = newLeft
            modelData.leftPadding = newLeft
        }
        if (newRight !== undefined) {
            item.rightPadding = newRight
            modelData.rightPadding = newRight
        }
        arr[wrapper.visualIndex] = item
        root.updated(arr)
    }

    property real bottomRadius: {
        if (listModel.length == 1 || visualIndex == listModel.length - 1) return Appearance.rounding.full
        return Appearance.rounding.verysmall
    }

    property real topRadius: {
        if (listModel.length == 1 || visualIndex == 0) return Appearance.rounding.full
        return Appearance.rounding.verysmall
    }

    Rectangle {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }

        scale: dragArea.held ? 1.02 : 1
        opacity: dragArea.held ? 0.8 : 1

        Behavior on scale {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        
        topLeftRadius: topRadius
        topRightRadius: topRadius
        bottomLeftRadius: bottomRadius
        bottomRightRadius: bottomRadius
        
        height: mainColumn.implicitHeight + 8

        color: dragArea.held ? colActive : colBackground
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Drag.active: dragArea.held
        Drag.source: dragArea
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        states: State {
            when: dragArea.held

            ParentChange {
                target: content
                parent: root
            }
            AnchorChanges {
                target: content
                anchors {
                    left: undefined
                    right: undefined
                    verticalCenter: undefined
                }
            }
        }

        ColumnLayout {
            id: mainColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 20
                topMargin: 4
                bottomMargin: 4
            }
            spacing: 8

            RowLayout {
                id: contentRow
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    id: dragIndicatorIcon
                    text: "drag_indicator"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOutline
                }
                
                MaterialSymbol {
                    id: icon
                    Layout.leftMargin: 10
                    text: wrapper.compInfo?.icon ?? ""
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: Appearance.colors.colPrimary
                    fill: 1
                }

                StyledText {
                    id: title
                    text: {
                        let base = wrapper.compInfo?.title ?? modelData.id
                        if (wrapper.isSpacer && modelData.style) {
                            return base + " (" + modelData.style + ")"
                        }
                        return base
                    }
                    color: wrapper.colTitle

                    Layout.leftMargin: 10
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.normal
                    }
                }
                
                Item {
                    height: 40
                    Layout.fillWidth: true
                }

                Loader {
                    active: (modelData.id in page.componentMap) || wrapper.isSpacer
                    sourceComponent: EntryButton {
                        iconText: "settings"
                        iconFill: wrapper.expanded
                        tooltip: Translation.tr("Settings")

                        onClicked: {
                            if (wrapper.isSpacer) {
                                root.toggleEntryExpanded(wrapper.visualIndex)
                            } else {
                                page.scrollTo(modelData.id)
                            }
                        }
                    }
                }
                
                Loader {
                    active: barSection == 1 // only showing it on center layout
                    sourceComponent: EntryButton {
                        iconText: "adjust"
                        iconFill: modelData.centered
                        tooltip: Translation.tr("Center")

                        onClicked: {
                            root.toggleCenter(wrapper.visualIndex, wrapper.getOrderedList())
                        }
                    }
                }
                
                EntryButton {
                    id: removeButton
                    iconText: "close"
                    tooltip: Translation.tr("Remove")

                    onClicked: {
                        root.removeExpanded(visualIndex)
                        let arr = wrapper.getOrderedList()
                        arr.splice(visualIndex, 1)
                        root.updated(arr)
                    }
                }
            }

            // Inline settings drawer for sacebar/spacebar
            ColumnLayout {
                id: spacebarDrawer
                visible: wrapper.isSpacer && wrapper.expanded
                Layout.fillWidth: true
                Layout.leftMargin: 36
                Layout.rightMargin: 4
                Layout.bottomMargin: 8
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    StyledText {
                        text: Translation.tr("Style")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        Layout.preferredWidth: 60
                    }

                    StyledComboBox {
                        Layout.fillWidth: true
                        textRole: "text"
                        model: [
                            { text: Translation.tr("Pipe"), value: "pipe", icon: "power_input" },
                            { text: Translation.tr("Dot"), value: "dot", icon: "circle" },
                            { text: Translation.tr("Dash"), value: "dash", icon: "remove" },
                            { text: Translation.tr("Empty"), value: "empty", icon: "space_bar" }
                        ]
                        currentIndex: {
                            const s = (modelData.style ?? "pipe").toLowerCase()
                            if (s === "dot") return 1
                            if (s === "dash") return 2
                            if (s === "empty") return 3
                            return 0
                        }
                        onActivated: index => {
                            const val = model[index].value
                            wrapper.updateSpacebarConfig(val, undefined, undefined)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            text: Translation.tr("Left pad")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledSpinBox {
                            from: 0
                            to: 100
                            stepSize: 2
                            value: modelData.leftPadding !== undefined ? modelData.leftPadding : 4
                            onValueModified: {
                                wrapper.updateSpacebarConfig(undefined, value, undefined)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            text: Translation.tr("Right pad")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledSpinBox {
                            from: 0
                            to: 100
                            stepSize: 2
                            value: modelData.rightPadding !== undefined ? modelData.rightPadding : 4
                            onValueModified: {
                                wrapper.updateSpacebarConfig(undefined, undefined, value)
                            }
                        }
                    }
                }
            }
        }
    }
    
    DropArea {
        id: dropArea
        anchors {
            fill: parent
            margins: 20
        }

        onEntered: (drag) => {
            let fromIndex = drag.source.parent.visualIndex
            let toIndex = wrapper.visualIndex
            
            root.moveExpanded(fromIndex, toIndex)
            visualModel.items.move(fromIndex, toIndex)
        }
    }

    MouseArea {
        id: dragArea

        property bool held: false
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            margins: -6
        }
        width: 50

        pressAndHoldInterval: 200

        drag.target: held ? content : undefined
        drag.axis: Drag.YAxis
        drag.minimumY: 0
        drag.maximumY: root.listModel.length * 40 + (root.listModel.length - 1) * 4

        onPressAndHold: {
            root.dragging = true
            held = true
        }
        onReleased: {
            root.updated(wrapper.getOrderedList())
            held = false
            root.dragging = false
        }
    }

    component EntryButton: RippleButton {
        id: button
        implicitWidth: implicitHeight

        property string iconText: ""
        property bool iconFill: false
        property string tooltip: ""

        MaterialSymbol {
            text: button.iconText
            anchors.centerIn: parent
            color: Appearance.colors.colPrimary
            iconSize: Appearance.font.pixelSize.huge
            fill: button.iconFill ? 1 : 0
        }

        StyledToolTip {
            text: button.tooltip
        }
    }
}
    