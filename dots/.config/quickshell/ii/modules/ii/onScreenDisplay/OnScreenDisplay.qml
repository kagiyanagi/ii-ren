import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "components"
import "popups"

Scope {
    id: root
    property string protectionMessage: ""
    property var focusedScreen: Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")) || Quickshell.screens[0] || null

    // Reactive count of Pipewire program playback nodes (output apps with audio)
    // Updated explicitly via Connections to guarantee reactivity for width bindings
    property int programPlaybackCount: Audio.outputAppNodes.length

    Connections {
        target: Audio
        ignoreUnknownSignals: true
        function onOutputAppNodesChanged() {
            root.programPlaybackCount = Audio.outputAppNodes.length;
        }
    }

    property bool isStartup: true
    Timer {
        running: true
        interval: 500
        onTriggered: root.isStartup = false
    }

    property string currentIndicator: "volume"
    readonly property bool isDisplayIndicator: currentIndicator === "brightness" || currentIndicator === "gamma"
    property bool isClosing: false

    readonly property real currentValue: {
        if (currentIndicator === "volume") {
            if (Audio.sink && Audio.sink.audio)
                return Audio.sink.audio.muted ? 0 : Audio.sink.audio.volume;
            return 0;
        } else if (currentIndicator === "brightness") {
            let brightnessMonitor = Brightness.getTargetMonitor();
            return brightnessMonitor ? brightnessMonitor.brightness : 0.5;
        } else if (currentIndicator === "playerVolume") {
            return MprisController.activePlayer ? MprisController.activePlayer.volume : 0;
        } else if (currentIndicator === "gamma") {
            let from = Hyprsunset.gammaLowerLimit / 100;
            return (Hyprsunset.gamma / 100 - from) / (1.0 - from);
        } else if (currentIndicator === "keyboardBrightness") {
            return KeyboardBacklight.percentage / 100;
        }
        return 0.5;
    }

    readonly property string currentIcon: {
        if (currentIndicator === "volume") {
            const muted = (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false;
            const vol = root.currentValue;
            if (muted)
                return "volume_off";
            if (vol <= 0.0)
                return "volume_mute";
            if (vol <= 0.33)
                return "volume_mute";
            if (vol <= 0.66)
                return "volume_down";
            return "volume_up";
        } else if (currentIndicator === "brightness") {
            if (Hyprsunset.temperatureActive)
                return "routine";
            const val = root.currentValue;
            if (val <= 0.33)
                return "brightness_low";
            if (val <= 0.66)
                return "brightness_medium";
            return "brightness_high";
        } else if (currentIndicator === "playerVolume") {
            return "music_note";
        } else if (currentIndicator === "gamma") {
            return "wb_twilight";
        } else if (currentIndicator === "keyboardBrightness") {
            return "keyboard";
        }
        return "volume_up";
    }

    function updateIndicatorValue(newValue) {
        if (currentIndicator === "volume") {
            Audio.setVolume(newValue);
        } else if (currentIndicator === "brightness") {
            let brightnessMonitor = Brightness.getTargetMonitor();
            if (brightnessMonitor) {
                brightnessMonitor.setBrightness(newValue);
            }
        } else if (currentIndicator === "playerVolume") {
            if (MprisController.activePlayer) {
                MprisController.activePlayer.volume = newValue;
            }
        } else if (currentIndicator === "gamma") {
            let from = Hyprsunset.gammaLowerLimit / 100;
            let actualValue = newValue * (1.0 - from) + from;
            Hyprsunset.setGamma(Math.round(actualValue * 100));
        } else if (currentIndicator === "keyboardBrightness") {
            if (KeyboardBacklight.available && KeyboardBacklight.ready) {
                const step = Math.round(newValue * KeyboardBacklight.maxValue);
                KeyboardBacklight.setValue(step);
            }
        }
    }

    function triggerOsd() {
        if (!root.currentIndicator)
            root.currentIndicator = "volume";
        if (!Config.osdIndicatorEnabled(root.currentIndicator))
            return;
        if (Config.ready && Config.options.osd && Config.options.osd.hideWhenFullscreen && Notifications.focusedWindowFullscreen)
            return;
        root.isClosing = false;
        if (osdLoader.item) {
            osdLoader.item.openedProgress = 1.0;
            if (!GlobalStates.osdVolumeOpen) {
                osdLoader.item.isExpanded = false;
                osdLoader.item.expandedProgress = 0.0;
            }
        }
        GlobalStates.osdVolumeOpen = true;
        osdTimeout.restart();
    }

    Timer {
        id: osdTimeout
        interval: Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            if (osdLoader.item && (osdLoader.item._mouseInside || (osdLoader.item.deviceOutputPopup && osdLoader.item.deviceOutputPopup.opened)))
                return;
            GlobalStates.osdVolumeOpen = false;
            root.protectionMessage = "";
        }
    }

    Connections {
        target: GlobalStates
        ignoreUnknownSignals: true
        function onOsdInteraction() {
            root.triggerOsd();
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            if (GlobalStates.dashboardPanelOpen)
                return;
            root.protectionMessage = "";
            root.currentIndicator = "brightness";
            root.triggerOsd();
        }
    }

    Connections {
        target: Hyprsunset
        function onGammaChangeAttempt() {
            if (GlobalStates.dashboardPanelOpen)
                return;
            root.protectionMessage = "";
            root.currentIndicator = "gamma";
            root.triggerOsd();
        }
    }

    Connections {
        target: KeyboardBacklight
        function onCurrentValueChanged() {
            if (root.isStartup || GlobalStates.dashboardPanelOpen || KeyboardBacklight.suppressOsd)
                return;
            if (!KeyboardBacklight.initialValueLoaded) {
                KeyboardBacklight.initialValueLoaded = true;
                return;
            }
            root.protectionMessage = "";
            root.currentIndicator = "keyboardBrightness";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to volume changes
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready || root.isStartup || GlobalStates.blockVolumeOsdForBluetooth || GlobalStates.dashboardPanelOpen)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onMutedChanged() {
            if (!Audio.ready || root.isStartup || GlobalStates.blockVolumeOsdForBluetooth || GlobalStates.dashboardPanelOpen)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        target: Audio
        function onSinkProtectionTriggered(reason) {
            root.protectionMessage = reason;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        target: MprisController.activePlayer ?? null
        function onVolumeChanged() {
            if (MprisController.canChangeVolume) {
                root.currentIndicator = "playerVolume";
                root.triggerOsd();
            }
        }
    }

    Connections {
        target: Config.ready ? Config.options.osd : null
        ignoreUnknownSignals: true
        function onEnableChanged() {
            if (!Config.options.osd.enable) {
                GlobalStates.osdVolumeOpen = false;
                root.isClosing = false;
            }
        }
    }

    Loader {
        id: osdLoader
        active: (GlobalStates.osdVolumeOpen || root.isClosing) && !GlobalStates.osdConnectActive

        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"
            implicitWidth: 800

            property alias deviceOutputPopup: deviceOutputPopup

            // === SIZING TOKENS ===
            readonly property real osdBaseHeight: (Config.ready && Config.options.osd && Config.options.osd.height) ? Config.options.osd.height : 500
            // AOSP volume dialog, frameworks/base SystemUI res/values/dimens.xml (android16-qpr1):
            // background_margin 6, components_spacing 4, floating_sliders_spacing 8,
            // button_size 48, track_width 40 -> volume_dialog_width 60 = 2 * 6 + 48.
            readonly property real osdMargin: 6
            readonly property real osdItemSpacing: 4
            readonly property real osdRowSpacing: 8
            readonly property real osdGroupSpacing: 28
            readonly property real osdButtonHeight: 48
            readonly property real osdCollapseButtonHeight: osdButtonHeight
            readonly property real osdSquaredButtonSize: 40
            readonly property real osdSliderTrackWidth: 40

            readonly property real osdContractedWidth: 2 * osdMargin + osdButtonHeight
            readonly property real extrasExpandedWidth: {
                if (root.currentIndicator === "volume") {
                    var count = root.programPlaybackCount;
                    var slidersW = (2 + count) * osdButtonHeight;
                    if (count > 0) {
                        return slidersW + 2 * osdGroupSpacing + count * osdRowSpacing;
                    } else {
                        return slidersW + osdGroupSpacing + osdRowSpacing;
                    }
                } else if (root.isDisplayIndicator) {
                    var kbd = KeyboardBacklight.available ? 1 : 0;
                    var n = 2 + kbd; // 2 complementary display sliders + optional KeyboardBacklight
                    return n * osdButtonHeight + 2 * osdGroupSpacing + (n - 1) * osdRowSpacing;
                }
                return 0;
            }
            readonly property real osdExpandedWidth: osdContractedWidth + extrasExpandedWidth
            readonly property real osdExtrasMaxWidth: extrasExpandedWidth

            // One member of an M3 Expressive connected button group: an icon, a tooltip,
            // and radii that read its neighbours. AOSP's volume dialog has no labels in
            // it, and the labelled version of this button could not fit one -- the card
            // is `osdContractedWidth + extrasExpandedWidth` wide and the label cells
            // asked for more than that, so every one of them elided to two characters.
            component OsdMorphToggle: RippleButton {
                id: morphToggle

                property string symbol
                property string tooltipText
                // The button that stays on screen when the OSD is collapsed is a group
                // of one: it is the dialog's whole face, so it is a pill on both ends.
                property bool standalone: false

                // Neighbours come from the row's own child list, so a button added or
                // removed does not need three other buttons edited to agree with it.
                readonly property var group: morphToggle.parent
                readonly property int indexInGroup: group?.children.indexOf(morphToggle) ?? -1
                readonly property var prevSibling: (indexInGroup > 0) ? group.children[indexInGroup - 1] : null
                readonly property var nextSibling: (indexInGroup >= 0 && group && indexInGroup < group.children.length - 1) ? group.children[indexInGroup + 1] : null
                readonly property bool isFirstInGroup: standalone || indexInGroup === 0
                readonly property bool isLastInGroup: standalone || (group ? indexInGroup === group.children.length - 1 : true)

                // Press feedback is the group's, not this button's: the pressed member
                // grows and its neighbours yield, so the run keeps its total width.
                readonly property bool prevIsPressed: prevSibling?.down ?? false
                readonly property bool nextIsPressed: nextSibling?.down ?? false
                Layout.preferredWidth: {
                    if (morphToggle.down)
                        return osdRoot.osdButtonHeight + osdRoot.osdItemSpacing * 2;
                    if (morphToggle.prevIsPressed || morphToggle.nextIsPressed)
                        return osdRoot.osdButtonHeight - osdRoot.osdItemSpacing;
                    return osdRoot.osdButtonHeight;
                }
                Layout.preferredHeight: osdRoot.osdButtonHeight
                Layout.fillWidth: false

                Behavior on Layout.preferredWidth {
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                }

                // A group end, and any member that is on, is a pill; the seams between
                // two off members are `rounding.small` (DESIGN.md 4.3 -- selection is a
                // legitimate shape morph, and this is the button-group signature).
                readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : height / 2
                readonly property real rSmall: Appearance.rounding.small
                readonly property bool prevIsChecked: prevSibling?.toggled ?? false
                readonly property bool nextIsChecked: nextSibling?.toggled ?? false

                // `prev` is physically left only in a LeftToRight row; the OSD flips the
                // row direction with the screen edge it is anchored to.
                readonly property real leadingRadius: (isFirstInGroup || toggled || prevIsChecked) ? rFull : rSmall
                readonly property real trailingRadius: (isLastInGroup || toggled || nextIsChecked) ? rFull : rSmall
                readonly property real leftRadiusCalc: osdRoot.isLeftPosition ? leadingRadius : trailingRadius
                readonly property real rightRadiusCalc: osdRoot.isLeftPosition ? trailingRadius : leadingRadius

                topLeftRadius: leftRadiusCalc
                bottomLeftRadius: leftRadiusCalc
                topRightRadius: rightRadiusCalc
                bottomRightRadius: rightRadiusCalc

                Behavior on topLeftRadius { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                Behavior on bottomLeftRadius { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                Behavior on topRightRadius { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                Behavior on bottomRightRadius { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }

                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                colRippleToggled: Appearance.colors.colPrimaryActive

                contentItem: MaterialSymbol {
                    text: morphToggle.symbol
                    iconSize: Appearance.font.pixelSize.larger
                    color: morphToggle.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    // Selection reads on the icon's fill axis, not on colour alone.
                    fill: morphToggle.toggled ? 1 : 0
                }

                StyledToolTip {
                    text: morphToggle.tooltipText
                    extraVisibleCondition: morphToggle.hovered
                }
            }

            // The container the extras pack into, sized to what the card actually grows
            // by. Every row used to guess this separately and the top rows guessed wrong.
            component OsdExtrasRow: Item {
                default property alias content: extrasLayout.data

                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.preferredWidth: osdRoot.osdExtrasMaxWidth * osdRoot.expandedProgress
                visible: osdRoot.expandedProgress > 0.001
                clip: true

                // Anchored to the inner edge and sized by its content, the way the
                // slider row's extras are. Filling the parent instead hands the run
                // whatever the card has spare and spreads the buttons across it.
                RowLayout {
                    id: extrasLayout
                    anchors.left: osdRoot.isLeftPosition ? parent.left : undefined
                    anchors.right: osdRoot.isLeftPosition ? undefined : parent.right
                    height: parent.height
                    spacing: osdRoot.osdItemSpacing
                    layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft
                }
            }

            Connections {
                target: root
                function onFocusedScreenChanged() {
                    osdRoot.screen = root.focusedScreen;
                }
            }

            readonly property bool isLeftPosition: (Config.ready && Config.options.osd && Config.options.osd.position === "left")

            WlrLayershell.namespace: "quickshell:onScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: true
                bottom: true
                right: !osdRoot.isLeftPosition
                left: osdRoot.isLeftPosition
            }
            mask: Region {
                item: osdGroupWrapper
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            readonly property real maxLimit: (root.currentIndicator === "volume") ? ((Config.options.audio && Config.options.audio.protection && Config.options.audio.protection.enable) ? Config.options.audio.protection.maxAllowed / 100 : 1.5) : 1.0

            property bool isExpanded: false
            property real openedProgress: 0.0
            property real expandedProgress: 0.0

            // Enter on the fast spatial spec (may overshoot), exit accelerating on the
            // effects spec at ~half the duration (DESIGN.md, enter/exit asymmetry).
            Behavior on openedProgress {
                NumberAnimation {
                    id: openAnim
                    duration: Math.round((openAnim.to > 0 ? Appearance.animation.elementMoveSmall.duration : Appearance.animation.elementMoveFast.duration) * Appearance.animMultiplier)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: openAnim.to > 0 ? Appearance.animationCurves.expressiveFastSpatial : Appearance.animationCurves.emphasizedAccel
                }
            }

            NumberAnimation {
                id: expandAnim
                target: osdRoot
                property: "expandedProgress"
                to: 1.0
                duration: Math.round(Appearance.animation.elementMoveSmall.duration * Appearance.animMultiplier)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }

            NumberAnimation {
                id: collapseAnim
                target: osdRoot
                property: "expandedProgress"
                to: 0.0
                duration: Math.round(Appearance.animation.elementMoveFast.duration * Appearance.animMultiplier)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }

            onIsExpandedChanged: {
                if (osdRoot.isExpanded) {
                    collapseAnim.stop();
                    expandAnim.start();
                } else {
                    expandAnim.stop();
                    collapseAnim.start();
                }
                if (isExpanded)
                    root.triggerOsd();
            }

            Component.onCompleted: {
                root.isClosing = false;
            }

            Component.onDestruction: {
                root.isClosing = false;
            }

            Connections {
                target: GlobalStates
                function onOsdVolumeOpenChanged() {
                    if (GlobalStates.osdVolumeOpen) {
                        osdRoot.openedProgress = 1.0;
                        root.isClosing = false;
                        // Ensure collapsed state at the start of every open session.
                        // The Loader may reuse the same PanelWindow across rapid
                        // brightness-scroll re-triggers, so we zero out expansion
                        // here before the user sees the OSD.
                        osdRoot.isExpanded = false;
                        osdRoot.expandedProgress = 0.0;
                    } else {
                        root.isClosing = true;
                        osdRoot.openedProgress = 0.0;
                    }
                }
            }

            onOpenedProgressChanged: {
                if (openedProgress === 0.0) {
                    root.isClosing = false;
                }
            }

            onVisibleChanged: {
                if (!visible) {
                    osdRoot.isExpanded = false;
                } else if (GlobalStates.osdVolumeOpen) {
                    // Start the slide-in only once the surface is mapped; from
                    // Component.onCompleted most of it plays before the first frame.
                    osdRoot.openedProgress = 1.0;
                }
            }

            property bool isDragging: slidersRow.isDragging
            property real displayValue: root.currentValue

            Behavior on displayValue {
                id: displayValueBehavior
                enabled: !osdRoot.isDragging
                SmoothedAnimation {
                    velocity: 4.0
                }
            }

            property bool _mouseInside: false
            property bool _mouseEverInside: false

            function _updateOsdHover(hovered) {
                if (osdRoot._mouseInside === hovered)
                    return;
                osdRoot._mouseInside = hovered;
                if (hovered) {
                    osdRoot._mouseEverInside = true;
                    osdTimeout.stop();
                    osdHoverGraceTimer.stop();
                    if (!GlobalStates.osdVolumeOpen) {
                        GlobalStates.osdVolumeOpen = true;
                    }
                } else {
                    osdHoverGraceTimer.restart();
                }
            }

            Timer {
                id: osdHoverGraceTimer
                interval: 150
                repeat: false
                onTriggered: {
                    if (!osdRoot._mouseInside && !deviceOutputPopup.opened) {
                        root.triggerOsd();
                    }
                }
            }

            Connections {
                target: deviceOutputPopup
                function onOpenedChanged() {
                    if (!deviceOutputPopup.opened && !osdRoot._mouseInside) {
                        osdTimeout.restart();
                    }
                }
            }

            Item {
                id: windowWrapper
                anchors.fill: parent

                Item {
                    id: protectionMessageWrapper
                    anchors.left: osdRoot.isLeftPosition ? osdGroupWrapper.right : undefined
                    anchors.right: !osdRoot.isLeftPosition ? osdGroupWrapper.left : undefined
                    // A floating surface sits 10 from the thing it hangs off, on either
                    // side (DESIGN.md 5.3). The right-hand case used to be -12, which
                    // put the card *under* the dialog it was warning about.
                    anchors.leftMargin: osdRoot.isLeftPosition ? 10 : undefined
                    anchors.rightMargin: !osdRoot.isLeftPosition ? 10 : undefined
                    anchors.verticalCenter: osdGroupWrapper.verticalCenter
                    implicitHeight: protectionMessageBackground.implicitHeight
                    implicitWidth: protectionMessageBackground.implicitWidth

                    // Enter on default effects, leave accelerating at half that. The
                    // spec is assigned from inside the binding that drives the
                    // animation, because a Behavior cannot read its own direction
                    // (DESIGN.md 2.9).
                    property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
                    opacity: {
                        const shown = root.protectionMessage !== "";
                        protectionMessageWrapper.fadeSpec = shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                        return shown ? 1 : 0;
                    }
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: protectionMessageWrapper.fadeSpec.duration
                            easing.type: protectionMessageWrapper.fadeSpec.type
                            easing.bezierCurve: protectionMessageWrapper.fadeSpec.bezierCurve
                        }
                    }

                    HoverHandler {
                        id: protectionHoverHandler
                        enabled: protectionMessageWrapper.visible
                        onHoveredChanged: osdRoot._updateOsdHover(hovered)
                    }

                    Rectangle {
                        id: protectionMessageBackground
                        anchors.centerIn: parent
                        color: Appearance.m3colors.m3error
                        property real padding: 10
                        implicitHeight: protectionMessageRowLayout.implicitHeight + padding * 2
                        implicitWidth: protectionMessageRowLayout.implicitWidth + padding * 2
                        radius: Appearance.rounding.normal
                        border.width: 0

                        RowLayout {
                            id: protectionMessageRowLayout
                            anchors.centerIn: parent
                            MaterialSymbol {
                                id: protectionMessageIcon
                                text: "dangerous"
                                iconSize: Appearance.font.pixelSize.hugeass
                                color: Appearance.m3colors.m3onError
                            }
                            StyledText {
                                id: protectionMessageTextWidget
                                horizontalAlignment: Text.AlignHCenter
                                color: Appearance.m3colors.m3onError
                                wrapMode: Text.Wrap
                                text: root.protectionMessage
                            }
                        }
                    }
                }

                Item {
                    id: osdGroupWrapper
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: osdRoot.isLeftPosition ? parent.left : undefined
                    anchors.right: !osdRoot.isLeftPosition ? parent.right : undefined
                    anchors.leftMargin: osdRoot.isLeftPosition ? (-width + width * osdRoot.openedProgress) : undefined
                    anchors.rightMargin: !osdRoot.isLeftPosition ? (-width + width * osdRoot.openedProgress) : undefined
                    width: osdContainer.width + 2 * osdMargin
                    height: osdBaseHeight + 2 * osdMargin
                    // Spatial progress may overshoot; opacity must not.
                    opacity: Math.min(1, osdRoot.openedProgress)

                    readonly property bool hasExpandableIndicator: root.currentIndicator === "volume" || root.currentIndicator === "playerVolume" || root.currentIndicator === "brightness" || root.currentIndicator === "gamma"
                    readonly property bool hasTopButton: hasExpandableIndicator || root.currentIndicator === "keyboardBrightness"

                    HoverHandler {
                        id: osdHoverHandler
                        onHoveredChanged: osdRoot._updateOsdHover(hovered)
                    }

                    // Elevation 3 -- a popup (DESIGN.md 6.2). The container is a plain
                    // rounded rectangle, which is the cached rectangular shadow's case;
                    // the drop shadow it used to carry rendered the whole 418px surface
                    // offscreen every frame for the same picture.
                    StyledRectangularShadow {
                        id: osdShadow
                        target: osdContainer
                    }

                    Rectangle {
                        id: osdContainer
                        anchors.top: parent.top
                        anchors.topMargin: osdMargin
                        anchors.left: osdRoot.isLeftPosition ? parent.left : undefined
                        anchors.leftMargin: osdRoot.isLeftPosition ? osdMargin : undefined
                        anchors.right: !osdRoot.isLeftPosition ? parent.right : undefined
                        anchors.rightMargin: !osdRoot.isLeftPosition ? osdMargin : undefined

                        width: osdContractedWidth + (osdExpandedWidth - osdContractedWidth) * osdRoot.expandedProgress
                        height: osdBaseHeight

                        // Radius interpolated directly from expandedProgress — synchronised with the
                        // master animation. No separate Behavior (it would lag the width growth).
                        // Contracted (expandedProgress=0) -> width/2 (pill shape).
                        // Expanded   (expandedProgress=1) -> windowRounding.
                        radius: (Appearance.rounding.windowRounding - osdContractedWidth / 2) * osdRoot.expandedProgress + osdContractedWidth / 2

                        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
                        border.width: 0

                        ColumnLayout {
                            id: osdLayout
                            anchors.fill: parent
                            anchors.margins: osdMargin
                            spacing: osdItemSpacing

                            // (1) Top row: the indicator's primary toggle, pinned to the
                            // screen edge so it is the face of the collapsed dialog, plus
                            // the extras that grow out from behind it.
                            RowLayout {
                                id: volumeTopRow
                                visible: root.currentIndicator === "volume"
                                spacing: osdRowSpacing * osdRoot.expandedProgress
                                Layout.fillWidth: true
                                Layout.preferredHeight: osdButtonHeight
                                Layout.fillHeight: false
                                layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                OsdMorphToggle {
                                    standalone: true
                                    toggled: (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false
                                    symbol: toggled ? "notifications_off" : "notifications_active"
                                    tooltipText: toggled ? Translation.tr("Unmute sound") : Translation.tr("Mute sound")
                                    onClicked: {
                                        if (Audio.sink && Audio.sink.audio)
                                            Audio.sink.audio.muted = !Audio.sink.audio.muted;
                                        root.triggerOsd();
                                    }
                                }

                                OsdExtrasRow {
                                    OsdMorphToggle {
                                        toggled: !Config.options.sounds.enable
                                        symbol: Config.options.sounds.enable ? "volume_up" : "volume_off"
                                        tooltipText: Config.options.sounds.enable ? Translation.tr("Disable system sounds") : Translation.tr("Enable system sounds")
                                        onClicked: {
                                            Config.options.sounds.enable = !Config.options.sounds.enable;
                                            root.triggerOsd();
                                        }
                                    }

                                    OsdMorphToggle {
                                        id: outputDevicesBtn
                                        toggled: deviceOutputPopup.opened
                                        symbol: "headphones"
                                        tooltipText: Translation.tr("Output devices")
                                        onClicked: {
                                            deviceOutputPopup._clickActive = !deviceOutputPopup._clickActive;
                                            root.triggerOsd();
                                        }

                                        OsdDeviceOutputPopup {
                                            id: deviceOutputPopup
                                            hoverTarget: outputDevicesBtn
                                            keyboardFocus: WlrKeyboardFocus.Click
                                            forceClick: true
                                            customPosition: true
                                            anchorRight: true
                                            anchorTop: true
                                            // A popup sits 10 from the thing it anchors to (DESIGN.md 5.3).
                                            customMarginRight: osdContainer.width + 10
                                            customMarginTop: (osdRoot && osdContainer) ? (osdRoot.height - osdContainer.height) / 2 - 10 : 0
                                            contentHeight: osdContainer.height - 20
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                id: brightnessTopRow
                                visible: root.isDisplayIndicator
                                spacing: osdRowSpacing * osdRoot.expandedProgress
                                Layout.fillWidth: true
                                Layout.preferredHeight: osdButtonHeight
                                Layout.fillHeight: false
                                layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                OsdMorphToggle {
                                    standalone: true
                                    toggled: Appearance.m3colors.darkmode
                                    symbol: toggled ? "dark_mode" : "light_mode"
                                    tooltipText: toggled ? Translation.tr("Dark mode") : Translation.tr("Light mode")
                                    onClicked: {
                                        if (Appearance.m3colors.darkmode)
                                            DarkModeService.disableDarkMode();
                                        else
                                            DarkModeService.enableDarkMode();
                                        root.triggerOsd();
                                    }
                                }

                                OsdExtrasRow {
                                    OsdMorphToggle {
                                        toggled: Hyprsunset.temperatureActive
                                        symbol: "wb_twilight"
                                        tooltipText: toggled ? Translation.tr("Disable nightlight") : Translation.tr("Enable nightlight")
                                        onClicked: {
                                            Hyprsunset.toggleTemperature();
                                            root.triggerOsd();
                                        }
                                    }

                                    OsdMorphToggle {
                                        toggled: Config.options.light.night.automatic
                                        symbol: "schedule"
                                        tooltipText: toggled ? Translation.tr("Auto nightlight on") : Translation.tr("Auto nightlight off")
                                        onClicked: {
                                            Config.options.light.night.automatic = !Config.options.light.night.automatic;
                                            root.triggerOsd();
                                        }
                                    }
                                }
                            }

                            // The indicators with no extras of their own keep the single
                            // labelled button they have always had.
                            OsdTopButton {
                                id: topButton
                                visible: root.currentIndicator !== "volume" && !root.isDisplayIndicator
                                currentIndicator: root.currentIndicator
                                expandedProgress: osdRoot.expandedProgress
                                buttonHeight: osdButtonHeight

                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                Layout.preferredHeight: buttonHeight
                                Layout.preferredWidth: osdButtonHeight + (parent.width - osdButtonHeight) * osdRoot.expandedProgress
                                onClicked: root.triggerOsd()
                            }

                            // (2) Sliders -- the reason the dialog is on screen.
                            OsdSlidersRow {
                                id: slidersRow
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                currentIndicator: root.currentIndicator
                                expandedProgress: osdRoot.expandedProgress
                                sliderTrackWidth: osdSliderTrackWidth
                                displayValue: osdRoot.displayValue
                                maxLimit: osdRoot.maxLimit
                                currentIcon: root.currentIcon
                                rootOsd: root
                                osdRoot: osdRoot
                                osdRowSpacing: osdRowSpacing
                                osdGroupSpacing: osdGroupSpacing
                            }

                            // (3) AOSP's squared button slot under the track. Music
                            // recognition, and only that -- its other branch drew a
                            // second nightlight toggle directly under the one in the
                            // top row whenever the gamma indicator was showing.
                            RippleButton {
                                id: musicCircle
                                visible: root.currentIndicator === "volume"
                                // Centred under the main slider, which is the column
                                // this button belongs to. Centring it in the *card*
                                // left it drifting into the middle as the card grew.
                                Layout.alignment: osdRoot.isLeftPosition ? Qt.AlignLeft : Qt.AlignRight
                                Layout.leftMargin: osdRoot.isLeftPosition ? (osdButtonHeight - osdSquaredButtonSize) / 2 : 0
                                Layout.rightMargin: osdRoot.isLeftPosition ? 0 : (osdButtonHeight - osdSquaredButtonSize) / 2
                                Layout.topMargin: osdItemSpacing
                                Layout.preferredWidth: osdSquaredButtonSize
                                Layout.preferredHeight: visible ? osdSquaredButtonSize : 0
                                buttonRadius: Appearance.rounding.small
                                rippleEnabled: true

                                toggled: SongRec.running
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                colBackgroundToggled: Appearance.colors.colPrimary
                                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                                colRipple: Appearance.colors.colSecondaryContainerActive
                                colRippleToggled: Appearance.colors.colPrimaryActive

                                contentItem: MaterialSymbol {
                                    text: "music_note"
                                    color: musicCircle.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                    iconSize: Appearance.font.pixelSize.huge
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    fill: musicCircle.toggled ? 1 : 0
                                }

                                onClicked: {
                                    SongRec.toggleRunning();
                                    root.triggerOsd();
                                }

                                StyledToolTip {
                                    text: SongRec.running ? Translation.tr("Stop music recognition") : Translation.tr("Start music recognition")
                                    extraVisibleCondition: musicCircle.hovered
                                }
                            }

                            // (4) Bottom row: the expand/collapse control in AOSP's
                            // settings slot, and this indicator's remaining toggles.
                            RowLayout {
                                id: volumeBottomRow
                                visible: root.currentIndicator === "volume"
                                spacing: osdRowSpacing * osdRoot.expandedProgress
                                Layout.fillWidth: true
                                Layout.preferredHeight: osdButtonHeight
                                Layout.fillHeight: false
                                layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                OsdCollapseButton {
                                    isExpanded: osdRoot.isExpanded
                                    hasExpandableIndicator: osdGroupWrapper.hasExpandableIndicator
                                    buttonHeight: osdButtonHeight
                                    expandedProgress: osdRoot.expandedProgress
                                    buttonRadius: osdButtonHeight / 2
                                    showText: false

                                    Layout.fillWidth: false
                                    Layout.alignment: Qt.AlignRight
                                    Layout.preferredHeight: osdButtonHeight
                                    Layout.preferredWidth: osdButtonHeight
                                    onClicked: {
                                        osdRoot.isExpanded = !osdRoot.isExpanded;
                                        root.triggerOsd();
                                    }
                                }

                                OsdExtrasRow {
                                    OsdMorphToggle {
                                        toggled: EasyEffects.active
                                        symbol: "graphic_eq"
                                        tooltipText: toggled ? Translation.tr("EasyEffects On") : Translation.tr("EasyEffects Off")
                                        onClicked: {
                                            EasyEffects.toggle();
                                            root.triggerOsd();
                                        }
                                    }

                                    OsdMorphToggle {
                                        toggled: (Audio.source && Audio.source.audio) ? Audio.source.audio.muted : false
                                        symbol: toggled ? "mic_off" : "mic"
                                        tooltipText: toggled ? Translation.tr("Unmute Mic") : Translation.tr("Mute Mic")
                                        onClicked: {
                                            Audio.toggleMicMute();
                                            root.triggerOsd();
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                id: brightnessBottomRow
                                visible: root.isDisplayIndicator
                                spacing: osdRowSpacing * osdRoot.expandedProgress
                                Layout.fillWidth: true
                                Layout.preferredHeight: osdButtonHeight
                                Layout.fillHeight: false
                                layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                OsdCollapseButton {
                                    isExpanded: osdRoot.isExpanded
                                    hasExpandableIndicator: osdGroupWrapper.hasExpandableIndicator
                                    buttonHeight: osdButtonHeight
                                    expandedProgress: osdRoot.expandedProgress
                                    buttonRadius: osdButtonHeight / 2
                                    showText: false

                                    Layout.fillWidth: false
                                    Layout.alignment: Qt.AlignRight
                                    Layout.preferredHeight: osdButtonHeight
                                    Layout.preferredWidth: osdButtonHeight
                                    onClicked: {
                                        osdRoot.isExpanded = !osdRoot.isExpanded;
                                        root.triggerOsd();
                                    }
                                }

                                OsdExtrasRow {
                                    OsdMorphToggle {
                                        visible: KeyboardBacklight.available
                                        toggled: KeyboardBacklight.currentValue > 0
                                        symbol: "keyboard"
                                        tooltipText: toggled ? Translation.tr("Kbd Backlight On") : Translation.tr("Kbd Backlight Off")
                                        onClicked: {
                                            if (KeyboardBacklight.available && KeyboardBacklight.ready)
                                                KeyboardBacklight.setValue(KeyboardBacklight.currentValue > 0 ? 0 : KeyboardBacklight.maxValue);
                                            root.triggerOsd();
                                        }
                                    }

                                    OsdMorphToggle {
                                        toggled: Hyprsunset.gamma !== 100
                                        symbol: "wb_sunny"
                                        tooltipText: toggled ? Translation.tr("Low Gamma") : Translation.tr("Normal Gamma")
                                        onClicked: {
                                            Hyprsunset.setGamma(Hyprsunset.gamma === 100 ? Hyprsunset.gammaLowerLimit : 100);
                                            root.triggerOsd();
                                        }
                                    }
                                }
                            }

                            OsdCollapseButton {
                                id: collapseButton
                                isExpanded: osdRoot.isExpanded
                                hasExpandableIndicator: osdGroupWrapper.hasExpandableIndicator
                                buttonHeight: osdCollapseButtonHeight
                                expandedProgress: osdRoot.expandedProgress
                                buttonRadius: osdCollapseButtonHeight / 2

                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                Layout.preferredHeight: osdCollapseButtonHeight
                                Layout.preferredWidth: osdCollapseButtonHeight + (parent.width - osdCollapseButtonHeight) * osdRoot.expandedProgress
                                visible: root.currentIndicator !== "volume" && !root.isDisplayIndicator
                                onClicked: {
                                    osdRoot.isExpanded = !osdRoot.isExpanded;
                                    root.triggerOsd();
                                }
                            }
                        }
                    }

                }
            }
        }
    }

    IpcHandler {
        target: "osdVolume"

        function trigger() {
            root.triggerOsd();
        }

        function hide() {
            GlobalStates.osdVolumeOpen = false;
        }

        function toggle() {
            GlobalStates.osdVolumeOpen = !GlobalStates.osdVolumeOpen;
        }

        // Open first, then expand: the Loader has no item while the OSD is closed, and
        // `triggerOsd` zeroes the expansion on the way in, so setting the flag before
        // the call made `expand` a no-op from the state it is most often called in.
        function expand() {
            root.triggerOsd();
            if (osdLoader.item)
                osdLoader.item.isExpanded = true;
        }

        function collapse() {
            root.triggerOsd();
            if (osdLoader.item)
                osdLoader.item.isExpanded = false;
        }
    }
    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed: {
            root.triggerOsd();
        }
    }
    GlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed: {
            GlobalStates.osdVolumeOpen = false;
        }
    }

    onCurrentIndicatorChanged: GlobalStates.osdCurrentIndicator = currentIndicator
    onProtectionMessageChanged: GlobalStates.osdProtectionMessage = protectionMessage

    Component.onCompleted: {
        GlobalStates.osdCurrentIndicator = currentIndicator;
        GlobalStates.osdProtectionMessage = protectionMessage;
    }
}