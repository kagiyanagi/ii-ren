import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

Item {
    id: root
    property bool vertical: false
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)

    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap 
    readonly property int monitorIndex: barLoader.monitorIndex
    property int workspaceOffset: useWorkspaceMap ? workspaceMap[monitorIndex] : 0

    readonly property int workspacesShown: dynamicWorkspaces
    ? ((workspaceMap[monitorIndex + 1] ?? workspaceMap[monitorIndex] + Config.options.bar.workspaces.shown) - workspaceMap[monitorIndex])
    : Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((monitor?.activeWorkspace?.id - root.workspaceOffset - 1) / root.workspacesShown)
    property list<bool> workspaceOccupied: []
    property int workspaceIndexInGroup: (monitor?.activeWorkspace?.id - root.workspaceOffset - 1) % root.workspacesShown    
    property var monitorWindows
    readonly property int effectiveActiveWorkspaceId: monitor?.activeWorkspace?.id ?? 1

    property int individualIconBoxHeight: 22
    property int iconBoxWrapperSize: 26
    property int workspaceDotSize: 4
    property real iconRatio: 0.8
    property bool showIcons: Config.options.bar.workspaces.showAppIcons

    readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    property int maxWindowCount: isScrollingLayout ? Config.options.bar.workspaces.maxWindowCount : 1

    readonly property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamicWorkspaces

    function isWorkspaceVisible(wsIndex) {
        const wsId = workspaceGroup * workspacesShown + wsIndex + 1 + workspaceOffset
        const isActive = wsId === effectiveActiveWorkspaceId
        const isOccupied = workspaceOccupied[wsIndex]
        return !dynamicWorkspaces || isActive || isOccupied
    }

    readonly property int visibleActiveIndex: {
        if (!dynamicWorkspaces) return workspaceIndexInGroup
        let count = 0
        for (let i = 0; i < workspacesShown; i++) {
            if (i === workspaceIndexInGroup) return count
            if (isWorkspaceVisible(i)) count++
        }
        return count
    }

    /*
     * The strip's real geometry, in *visible* slots.
     *
     * A workspace is not always iconBoxWrapperSize wide: it grows with the app
     * icons in it, and with dynamicWorkspaces an empty one takes no room at
     * all. Both indicators used to mix the two coordinate systems -- their
     * position counted slots of a fixed size while the offset that corrected
     * for the real widths came from a loop over *raw* child indices, hidden
     * children included. With dynamic workspaces on and icons showing, the
     * indicator therefore landed beside the workspace it was pointing at.
     *
     * Everything below walks the live child widths instead, so one function
     * answers where a slot edge is and the indicators only have to say which
     * edge they want.
     */
    readonly property var slotSizes: {
        const sizes = [];
        for (let i = 0; i < root.workspacesShown; i++) {
            const item = contentLayout.children[i];
            if (!item?.visible)
                continue;
            const size = root.vertical ? item.height : item.width;
            // `> 0` and not Math.max: NaN fails every comparison but survives
            // Math.max, and one NaN here is a blank bar (ii-background-root).
            sizes.push(size > 0 ? size : root.iconBoxWrapperSize);
        }
        return sizes;
    }

    // Size of visible slot k, clamped at both ends so the indicator's overshoot
    // past the first or last workspace extrapolates instead of collapsing.
    function slotSize(k: int): real {
        const sizes = root.slotSizes;
        if (sizes.length === 0)
            return root.iconBoxWrapperSize;
        return sizes[Math.max(0, Math.min(sizes.length - 1, k))];
    }

    // Leading edge of fractional visible-slot position v, along the bar's axis.
    function slotEdge(v: real): real {
        const sizes = root.slotSizes;
        const n = sizes.length;
        if (n === 0 || !isFinite(v))
            return 0;
        const whole = Math.floor(v);
        let edge = 0;
        if (whole <= 0) {
            edge = whole * sizes[0];
        } else {
            for (let i = 0; i < Math.min(whole, n); i++)
                edge += sizes[i];
            if (whole > n)
                edge += (whole - n) * sizes[n - 1];
        }
        return edge + (v - whole) * root.slotSize(whole);
    }

    // How many visible slots sit before raw workspace index `index`.
    function slotsBefore(index: int): int {
        let n = 0;
        for (let i = 0; i < index; i++)
            if (contentLayout.children[i]?.visible)
                n++;
        return n;
    }

    property bool showNumbersByMs: false
    Timer {
        id: showNumbersTimer
        interval: (Config.options.bar.workspaces.showNumberDelay ?? 100)
        repeat: false
        onTriggered: {
            root.showNumbersByMs = true
        }
    }
    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
            if (GlobalStates.superDown) showNumbersTimer.restart();
            else {
                showNumbersTimer.stop();
                root.showNumbersByMs = false;
            }
        }
        function onSuperReleaseMightTriggerChanged() { 
            showNumbersTimer.stop()
        }
    }

    function updateWorkspaceOccupied() {
        workspaceOccupied = Array.from({ length: root.workspacesShown }, (_, i) => {
            const wsId = workspaceGroup * root.workspacesShown + i + 1 + root.workspaceOffset;
            return Hyprland.workspaces.values.some(ws => ws.id === wsId);
        })
    }

    function getWindowCountForWorkspace(workspaceId) {
        return HyprlandData.windowList.filter(w => w.workspace.id === workspaceId && !w.floating).length;
    }

    // Window list updates
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            const windowsOnMonitor = HyprlandData.windowList.filter(win => win.monitor === root.monitorIndex && !win.floating)
            windowsOnMonitor.sort((a, b) => a.at[0] - b.at[0])
            root.monitorWindows = windowsOnMonitor.map(win => ({
                icon: Quickshell.iconPath(AppSearch.guessIcon(win?.class), "image-missing"),
                workspace: win.workspace?.id
            }))
        }
    }

    // Occupied workspace updates
    Component.onCompleted: {
        updateWorkspaceOccupied()
    }
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateWorkspaceOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateWorkspaceOccupied();
        }
    }
    onWorkspaceGroupChanged: {
        updateWorkspaceOccupied();
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : contentLayout.implicitWidth
    implicitHeight: root.vertical ? contentLayout.implicitHeight : Appearance.sizes.barHeight

    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // Active workspace indicator
    Rectangle {
        id: activeIndicator
        z: 2
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        color: Appearance.colors.colPrimary
        opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
        radius: Appearance.rounding.full
        
        // The tab-indicator stretch: the leading edge runs on fast spatial and
        // the trailing one on default spatial, so the pill elongates out of the
        // workspace it is leaving and gathers back into the one it lands on.
        AnimatedTabIndexPair {
            id: idxPair
            index: root.visibleActiveIndex
        }

        function getWindowCount(workspaceId) {
            return HyprlandData.windowList.filter( w => w.workspace.id === workspaceId && !w.floating ).length;
        }

        property int index: root.workspaceIndexInGroup
        property int windowCount: getWindowCount(index + root.workspaceOffset + root.workspaceGroup * root.workspacesShown + 1)

        property bool isEmptyWorkspace: windowCount === 0
        property bool isOneWindow: windowCount === 1

        property real indicatorInsetEmpty: root.iconBoxWrapperSize * 0.07
        property real indicatorInsetOneWindow: root.iconBoxWrapperSize * 0.14
        property real indicatorInset: root.iconBoxWrapperSize * 0.1

        property real visualInset: {
            if (!root.showIcons)
                return indicatorInsetEmpty - 0.5
            if (isEmptyWorkspace)
                return indicatorInsetEmpty
            if (isOneWindow)
                return indicatorInsetOneWindow
            return indicatorInset
        }

        // The inset is the one term of the geometry that is not already moving:
        // it steps when the window count crosses 0 or 1. It feeds the position
        // and the length, so animating it here -- once, on the spec the motion
        // table gives position and size -- keeps the two ends of the pill on
        // one timing. Two Behaviors, one per end, is how they drift apart.
        Behavior on visualInset {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        readonly property real leadSlot: Math.min(idxPair.idx1, idxPair.idx2)
        readonly property real trailSlot: Math.max(idxPair.idx1, idxPair.idx2)

        readonly property real indicatorPosition: root.slotEdge(leadSlot) + visualInset
        readonly property real indicatorLength: Math.max(0, root.slotEdge(trailSlot + 1) - root.slotEdge(leadSlot) - visualInset * 2)

        y: root.vertical ? indicatorPosition : 0
        x: root.vertical ? 0 : indicatorPosition
        implicitHeight: root.vertical ? indicatorLength : individualIconBoxHeight
        implicitWidth: root.vertical ? individualIconBoxHeight : indicatorLength
    }
    
    Rectangle {
        id: hoverIndicator
        z: 2
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter

        radius: Appearance.rounding.full

        /*
         * The bar's own state film, not a tint of its own: hover and pressed are
         * the layer-0 siblings of the surface the strip sits on (3.1, 6.1), so
         * they stay right when transparency is on. This used to be a primary
         * fill at a hand-written 0.1, with no pressed state at all.
         *
         * `visible` used to be bound to containsMouse, which meant the opacity
         * Behavior below never ran -- the pill vanished in one frame, as the
         * NOTE this block used to carry said. It is now driven by the fade, so
         * the exit exists and the first-contact snap still has a visible edge to
         * trigger on.
         */
        color: {
            const pressed = interactionMouseArea.pressed;
            // Over the active pill an opaque layer-0 fill painted the pill out. There
            // it is the pill's own state layer instead -- its content colour at the
            // hover/pressed film token, so the pill shows through, as in Android.
            if (onActive)
                return ColorUtils.transparentize(Appearance.colors.colOnPrimary, pressed ? 0.90 : 0.92);
            return pressed ? Appearance.colors.colLayer0Active : Appearance.colors.colLayer0Hover;
        }
        opacity: interactionMouseArea.containsMouse ? 1 : 0
        visible: opacity > 0

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(hoverIndicator)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(hoverIndicator)
        }

        property int hoverIdx: interactionMouseArea.hoverIndex
        readonly property bool onActive: hoverIdx === root.workspaceIndexInGroup
        property bool wasVisible: false

        onVisibleChanged: { // we disable the animations on first contact, then enable it
            if (visible && !wasVisible) {
                positionBehavior.enabled = false
                lengthBehavior.enabled = false

                Qt.callLater(function() {
                    positionBehavior.enabled = true
                    lengthBehavior.enabled = true
                })
            }
            wasVisible = visible
        }

        // On the active workspace the film takes the pill's own inset, so no rim of
        // it shows round the pill's edge.
        readonly property real hoverInset: onActive ? activeIndicator.visualInset : root.iconBoxWrapperSize * 0.05
        readonly property int hoverSlot: root.slotsBefore(hoverIdx)

        property real indicatorPosition: root.slotEdge(hoverSlot) + hoverInset
        property real indicatorLength: Math.max(0, root.slotSize(hoverSlot) - hoverInset * 2)

        y: root.vertical ? indicatorPosition : 0
        x: root.vertical ? 0 : indicatorPosition
        implicitHeight: root.vertical ? indicatorLength : individualIconBoxHeight
        implicitWidth: root.vertical ? individualIconBoxHeight : indicatorLength

        Behavior on indicatorPosition {
            id: positionBehavior
            animation: Appearance.animation.elementMove.numberAnimation.createObject(hoverIndicator)
        }
        Behavior on indicatorLength {
            id: lengthBehavior
            animation: Appearance.animation.elementMove.numberAnimation.createObject(hoverIndicator)
        }
    }


    MouseArea {
        id: interactionMouseArea
        z: 4 
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.RightButton | Qt.LeftButton | Qt.BackButton
        
        // Raw workspace index under the pointer. Hidden workspaces take no room
        // in the strip, so they must take none here either -- counting them made
        // every click past a hidden workspace land on the wrong one.
        property int hoverIndex: {
            const position = root.vertical ? mouseY : mouseX;
            let accumulated = 0;
            let last = 0;

            for (let i = 0; i < root.workspacesShown; i++) {
                const item = contentLayout.children[i];
                if (!item?.visible) continue;

                const itemSize = root.vertical ? item.height : item.width;
                last = i;

                if (position < accumulated + itemSize) {
                    return i;
                }

                accumulated += itemSize;
            }

            return last;
        }

        onPressed: (event) => {
            if (event.button === Qt.RightButton) {
                GlobalStates.overviewOpen = !GlobalStates.overviewOpen
            } 
            if (event.button === Qt.BackButton) {
                Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
            }
            if (event.button === Qt.LeftButton) {
                const wsId = workspaceOffset + workspaceGroup * workspacesShown + hoverIndex + 1;
                Hyprland.dispatch(`hl.dsp.focus({ workspace = ${wsId} })`);
            }
        }
        
        onWheel: (event) => {
            // console.log(event.angleDelta.y)
            if (event.angleDelta.y < 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r+1"})`);
            else if (event.angleDelta.y > 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r-1"})`);
        }
    }

    StyledRectangle {
        id: occupiedIndicatorsBg
        anchors.fill: occupiedIndicatorsLayout
        contentLayer: StyledRectangle.ContentLayer.Group
        color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.4)
        visible: false
    }

    GridLayout {
        id: occupiedIndicatorsLayout
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
        z: 1

        columns: root.vertical ? 1 : 99
        rows: root.vertical ? 99 : 1

        layer.enabled: true
        visible: false

        Repeater {
            model: root.workspacesShown
            delegate: Item {
                id: wsBg
                Layout.alignment: Qt.AlignCenter

                property int wsId: workspaceGroup * workspacesShown + index + 1 + workspaceOffset
                property bool currentOccupied: workspaceOccupied[index] && wsId != effectiveActiveWorkspaceId
                property bool previousOccupied: index > 0 && workspaceOccupied[index - 1] && (wsId - 1) != effectiveActiveWorkspaceId
                property bool nextOccupied: index < workspacesShown - 1 && workspaceOccupied[index + 1] && (wsId + 1) != effectiveActiveWorkspaceId
                
                property int windowCount: root.getWindowCountForWorkspace(wsId)
                
                property real itemSize: {
                    const item = contentLayout.children[index]
                    return root.vertical ? (item?.height ?? root.iconBoxWrapperSize) : (item?.width ?? root.iconBoxWrapperSize)
                }

                implicitWidth: root.vertical ? root.iconBoxWrapperSize : (wsBg.wsVisible ? itemSize : 0)
                implicitHeight: root.vertical ? (wsBg.wsVisible ? itemSize : 0) : root.iconBoxWrapperSize
                property bool wsVisible: root.isWorkspaceVisible(index)


                Pill {
                    property real stretchAmount: 12 // not using multiplier because it mulitplies multi-windowed workspaces A LOT
                    
                    property real undirectionalWidth: root.iconBoxWrapperSize * wsBg.currentOccupied
                    
                    property real undirectionalLength: {
                        if (!wsBg.currentOccupied) return 0
                        
                        let baseLength = wsBg.itemSize
                        
                        if (wsBg.previousOccupied && index > 0) {
                            baseLength += stretchAmount
                        }
                    
                        if (wsBg.nextOccupied && index < workspacesShown - 1) {
                            baseLength += stretchAmount
                        }
                        
                        return baseLength
                    }
                    
                    property real undirectionalOffset: {
                        if (!wsBg.currentOccupied) return 0.5 * root.iconBoxWrapperSize
                        
                        if (!wsBg.previousOccupied || index === 0) return 0
                        
                        return -stretchAmount
                    }

                    anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                    x: root.vertical ? 0 : undirectionalOffset
                    y: root.vertical ? undirectionalOffset : 0
                    implicitWidth: root.vertical ? undirectionalWidth : undirectionalLength
                    implicitHeight: root.vertical ? undirectionalLength : undirectionalWidth

                    Behavior on undirectionalWidth {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on undirectionalLength {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on undirectionalOffset {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }

    MultiEffect {
        id: occupiedIndicatorsMultiEffect
        z: 1
        anchors.centerIn: parent
        implicitWidth: occupiedIndicatorsLayout.implicitWidth
        implicitHeight: occupiedIndicatorsLayout.implicitHeight
        source: occupiedIndicatorsBg
        maskEnabled: true
        maskSource: occupiedIndicatorsLayout
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    GridLayout {
        id: contentLayout
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
        z: 3

        columns: root.vertical ? 1 : 99
        rows: root.vertical ? 99 : 1

        Repeater {
            id: workspaceRepeater
            model: root.workspacesShown

            delegate: Item {
                id: background
                Layout.alignment: Qt.AlignCenter

                visible: wsVisible
                property bool wsVisible: root.isWorkspaceVisible(index)
                implicitWidth: root.vertical 
                    ? root.iconBoxWrapperSize 
                    : (Math.max(layout.implicitWidth + 8, root.iconBoxWrapperSize))
                implicitHeight: root.vertical 
                    ? (Math.max(layout.implicitHeight + 8, root.iconBoxWrapperSize))
                    : root.iconBoxWrapperSize
                
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }


                WorkspaceBackgroundIndicator {
                    workspaceValue: workspaceOffset + workspaceGroup * workspacesShown + index + 1
                    activeWorkspace: monitor?.activeWorkspace?.id === workspaceValue
                }
                
                GridLayout {
                    id: layout
                    anchors.centerIn: parent
                    columnSpacing: 0
                    rowSpacing: 0
                    columns: root.vertical ? 1 : 99
                    rows: root.vertical ? 99 : 1

                    /*
                     * Monochrome icons used to cost a Desaturate *and* a
                     * ColorOverlay per icon, inside a repeated delegate (law 8,
                     * 8) -- and the option is on by default, so every app icon
                     * in the bar paid for two framebuffers. One MultiEffect on
                     * the row does the same desaturate-then-tint for every icon
                     * in the workspace at once. It sits here and not on the
                     * delegate above because this layout holds nothing but the
                     * icons; the number and the dot are its siblings.
                     */
                    layer.enabled: Config.options.bar.workspaces.monochromeIcons && layout.width > 0
                    layer.effect: MultiEffect {
                        saturation: -0.8
                        colorization: 0.1
                        colorizationColor: Appearance.colors.colOnLayer1
                    }

                    Repeater {
                        property int workspaceIndex: workspaceOffset + workspaceGroup * workspacesShown + index + 1
                        // root.maxWindowCount, not the config key it is derived
                        // from: the scrolling-layout cap was computed above and
                        // then bypassed here, so it never applied.
                        model: root.showIcons ? root.monitorWindows?.filter(win => win.workspace === workspaceIndex).splice(0, root.maxWindowCount) : []
                        delegate: Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: root.individualIconBoxHeight
                            height: root.individualIconBoxHeight
                            IconImage {
                                id: mainAppIcon
                                Layout.alignment: Qt.AlignHCenter
                                anchors {
                                    left: parent.left
                                    top: parent.top
                                    leftMargin: root.showNumbersByMs ? 15 : 2
                                    topMargin: root.showNumbersByMs ? 15 : 2
                                }
                                source: modelData.icon
                                implicitSize: (root.individualIconBoxHeight * root.iconRatio) * (root.showNumbersByMs ? 1 / 1.5 : 1)

                                Behavior on anchors.leftMargin {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Behavior on anchors.topMargin {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Behavior on implicitSize {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component WorkspaceBackgroundIndicator: Rectangle {
        property bool showNumbers: Config.options.bar.workspaces.alwaysShowNumbers || root.showNumbersByMs
        property int workspaceValue
        property bool activeWorkspace
        property color indColor: (activeWorkspace) ? Appearance.colors.colOnPrimary : (root.workspaceOccupied[index] ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1Inactive)

        anchors.centerIn: parent
        width: root.workspaceDotSize
        height: width
        radius: width / 2
        visible: layout.implicitHeight + 8 < root.iconBoxWrapperSize || root.showNumbersByMs
        color: !showNumbers ?  indColor : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        StyledText {
            opacity: showNumbers ? 1 : 0
            anchors.centerIn: parent
            text: Config.options?.bar.workspaces.numberMap[workspaceValue - 1] || workspaceValue
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: indColor
            // Opacity is an effect: it clips, so it takes the critically damped
            // spec, not the spatial one that overshoots past 1 (2.1, 10.6).
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}