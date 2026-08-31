pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQml.Models

import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    Layout.fillWidth: true
    readonly property bool wantsCard: true
    
    implicitHeight: Math.max(0, view.contentHeight) + componentSelectRow.implicitHeight + 28

    color: "transparent"
    radius: Appearance.rounding.large

    property int barSection // 0: left, 1: center, 2: right
    property var listModel
    property int selectedCompIndex

    property bool dragging: false

    // Compute available components from registry based on what's already used
    readonly property var usedIds: {
        let ids = []
        let allLists = [
            Config.options.bar.layouts.left,
            Config.options.bar.layouts.center,
            Config.options.bar.layouts.right
        ]
        for (let list of allLists) {
            for (let item of list) {
                ids.push(item.id)
            }
        }
        return ids
    }
    readonly property var availableComps: BarComponentRegistry.getAvailableComponents(usedIds)

    signal updated(var newList)

    Component.onCompleted: {
        initilizateLayout(listModel)
    }


    /*
     * We have to initilize the layout because we don't define the default values in Config.qml file
    */
    function initilizateLayout(list) {
        let initilizatedLayout = list.map(comp => initilizateComponent(comp))
        root.updated(initilizatedLayout)
    }

    function initilizateComponent(comp) {
        let base = {
            id: comp.id,
            centered: comp.centered !== undefined ? comp.centered : false,
            visible: comp.visible !== undefined ? comp.visible : true
        }
        if (comp.id === "sacebar" || comp.id === "spacebar") {
            base.style = comp.style !== undefined ? comp.style : "pipe"
            base.leftPadding = comp.leftPadding !== undefined ? comp.leftPadding : 4
            base.rightPadding = comp.rightPadding !== undefined ? comp.rightPadding : 4
        }
        return Object.assign({}, comp, base)
    }

    property var expandedMap: ({})

    function isEntryExpanded(idx) {
        return !!root.expandedMap[idx]
    }

    function toggleEntryExpanded(idx) {
        let map = Object.assign({}, root.expandedMap)
        if (map[idx]) {
            delete map[idx]
        } else {
            map[idx] = true
        }
        root.expandedMap = map
    }

    function moveExpanded(fromIndex, toIndex) {
        let map = {}
        for (let k in root.expandedMap) {
            let i = parseInt(k)
            if (i === fromIndex) {
                map[toIndex] = true
            } else if (fromIndex < toIndex && i > fromIndex && i <= toIndex) {
                map[i - 1] = true
            } else if (fromIndex > toIndex && i >= toIndex && i < fromIndex) {
                map[i + 1] = true
            } else {
                map[i] = true
            }
        }
        root.expandedMap = map
    }

    function removeExpanded(idx) {
        let map = {}
        for (let k in root.expandedMap) {
            let i = parseInt(k)
            if (i === idx) continue
            if (i > idx) {
                map[i - 1] = true
            } else {
                map[i] = true
            }
        }
        root.expandedMap = map
    }

    function toggleCenter(idx, currentList) {
        if (currentList[idx].centered) {
            currentList[idx].centered = false
            root.updated(currentList)
            return
        }
        for (let i = 0; i < currentList.length; i++) {
            currentList[i].centered = (i === idx);
        }

        root.updated(currentList)
    }

    DelegateModel {
        id: visualModel

        model: {
            values: root.listModel
        }
        delegate: ConfigListViewEntry {
            barSection: root.barSection
        }
    }

    StyledListView {
        id: view

        interactive: false
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: componentSelectRow.top
            margins: 10
            bottomMargin: 8
        }

        add: null

        model: visualModel

        spacing: 4
        cacheBuffer: 50
        
    }
    
    RowLayout {
        id: componentSelectRow
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 10
        }

        spacing: 4

        StyledComboBox {
            id: componentSelector
            
            topRightRadius: Appearance.rounding.verysmall
            bottomRightRadius: Appearance.rounding.verysmall

            buttonIcon: "box"
            textRole: "title"
            model: root.availableComps
            enabled: root.availableComps.length >= 1

            onActivated: index => {
                root.selectedCompIndex = index;
            }
        }

        RippleButton {
            id: addComponentButton
            implicitHeight: componentSelector.implicitHeight

            topLeftRadius: Appearance.rounding.verysmall
            bottomLeftRadius: Appearance.rounding.verysmall
            topRightRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full

            buttonText: Translation.tr("Add component")
            enabled: root.availableComps.length >= 1

            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            rippleColor: Appearance.colors.colSecondaryContainerActive
            
            onClicked: {
                let available = root.availableComps
                let idx = (componentSelector.currentIndex >= 0 && componentSelector.currentIndex < available.length)
                    ? componentSelector.currentIndex
                    : (root.selectedCompIndex >= 0 && root.selectedCompIndex < available.length ? root.selectedCompIndex : 0)
                if (available[idx] == null) return

                let newComp = initilizateComponent(available[idx]);
                listModel.push(newComp);

                root.updated(listModel);
            }
        }
    }
    
    
} 