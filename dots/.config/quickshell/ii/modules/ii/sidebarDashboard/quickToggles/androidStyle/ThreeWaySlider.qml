pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    required property string toggleType
    required property var toggleModel

    readonly property real margin: 4
    readonly property real knobSize: root.height - (margin * 2)

    readonly property real posLeft: margin
    readonly property real posCenter: (root.width - knobSize) / 2
    readonly property real posRight: root.width - knobSize - margin

    readonly property real thresholdLeftCenter: (posLeft + posCenter) / 2
    readonly property real thresholdCenterRight: (posCenter + posRight) / 2

    readonly property int currentStateIndex: {
        if (toggleType === "soundcoreAnc") {
            let mode = SoundcoreService.isConnected ? SoundcoreService.currentMode : (BudsService.isConnected ? BudsService.currentMode : "Normal");
            if (mode === "NoiseCanceling") return 0;
            if (mode === "Normal") return 1;
            if (mode === "Transparency") return 2;
            return 1;
        } else if (toggleType === "powerProfile") {
            let prof = PowerProfiles.profile;
            if (prof === PowerProfile.PowerSaver) return 0;
            if (prof === PowerProfile.Balanced) return 1;
            if (prof === PowerProfile.Performance) return 2;
            return 1;
        } else if (toggleType === "keyboardBacklight") {
            let val = KeyboardBacklight.currentValue;
            let max = KeyboardBacklight.maxValue;
            if (val === 0) return 0;
            if (val >= max) return 2;
            return 1;
        }
        return 1;
    }

    // Holds the position the user picked until the service catches up,
    // so the knob does not snap back mid-gesture.
    property int localOverrideIndex: -1
    readonly property int activeVisualIndex: localOverrideIndex !== -1 ? localOverrideIndex : currentStateIndex

    onCurrentStateIndexChanged: {
        localOverrideIndex = -1;
    }

    Timer {
        id: overrideResetTimer
        interval: 800
        repeat: false
        onTriggered: localOverrideIndex = -1
    }

    property bool isDraggingKnob: false
    property real knobDragX: posCenter

    readonly property int hoverIndex: {
        let xVal = isDraggingKnob ? knobDragX : targetX;
        if (xVal < thresholdLeftCenter) return 0;
        if (xVal > thresholdCenterRight) return 2;
        return 1;
    }

    readonly property real targetX: {
        if (activeVisualIndex === 0) return posLeft;
        if (activeVisualIndex === 1) return posCenter;
        return posRight;
    }

    readonly property bool isToggled: {
        if (toggleType === "soundcoreAnc") return hoverIndex !== 1;
        if (toggleType === "powerProfile") return hoverIndex !== 1;
        if (toggleType === "keyboardBacklight") return hoverIndex !== 0;
        return false;
    }

    function applyStateIndex(idx) {
        if (toggleType === "soundcoreAnc") {
            let targetMode = "Normal";
            if (idx === 0) targetMode = "NoiseCanceling";
            else if (idx === 1) targetMode = "Normal";
            else if (idx === 2) targetMode = "Transparency";
            
            let activeService = SoundcoreService.isConnected ? SoundcoreService : (BudsService.isConnected ? BudsService : null);
            if (activeService) activeService.setMode(targetMode);
        } else if (toggleType === "powerProfile") {
            if (idx === 0) PowerProfiles.profile = PowerProfile.PowerSaver;
            else if (idx === 1) PowerProfiles.profile = PowerProfile.Balanced;
            else if (idx === 2) PowerProfiles.profile = PowerProfile.Performance;
        } else if (toggleType === "keyboardBacklight") {
            let max = KeyboardBacklight.maxValue;
            if (idx === 0) KeyboardBacklight.setValue(0);
            else if (idx === 1) KeyboardBacklight.setValue(Math.max(1, Math.round(max / 2)));
            else if (idx === 2) KeyboardBacklight.setValue(max);
        }
    }

    function getIconForIndex(idx) {
        if (toggleType === "soundcoreAnc") {
            if (idx === 0) return "noise_control_off";
            if (idx === 1) return "hearing";
            if (idx === 2) return "visibility";
        } else if (toggleType === "powerProfile") {
            if (idx === 0) return "energy_savings_leaf";
            if (idx === 1) return "airwave";
            if (idx === 2) return "local_fire_department";
        } else if (toggleType === "keyboardBacklight") {
            if (idx === 0) return "backlight_high_off";
            if (idx === 1) return "backlight_high";
            if (idx === 2) return "brightness_6";
        }
        return toggleModel?.icon ?? "close";
    }

    Rectangle {
        id: bgPill
        anchors.fill: parent
        radius: height / 2
        color: Appearance.colors.colLayer2
        border.width: 0

        Rectangle {
            id: dotLeft
            width: 6
            height: 6
            radius: 3
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.left
            anchors.horizontalCenterOffset: root.posLeft + (root.knobSize / 2)
            opacity: root.hoverIndex === 0 ? 0.0 : 1.0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Rectangle {
            id: dotCenter
            width: 6
            height: 6
            radius: 3
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.hoverIndex === 1 ? 0.0 : 1.0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Rectangle {
            id: dotRight
            width: 6
            height: 6
            radius: 3
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.right
            anchors.horizontalCenterOffset: -(root.posLeft + (root.knobSize / 2))
            opacity: root.hoverIndex === 2 ? 0.0 : 1.0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    Rectangle {
        id: knob
        width: root.knobSize
        height: root.knobSize
        radius: width / 2
        y: root.margin
        x: root.isDraggingKnob ? root.knobDragX : root.targetX

        color: dragArea.pressed ? Appearance.colors.colPrimaryActive
            : dragArea.containsMouse ? Appearance.colors.colPrimaryHover
            : Appearance.colors.colPrimary

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on x {
            enabled: !root.isDraggingKnob
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }

        MaterialSymbol {
            id: knobIcon
            anchors.centerIn: parent
            iconSize: 22
            color: Appearance.colors.colOnPrimary
            text: root.getIconForIndex(root.hoverIndex)
        }
    }

    // preventStealing is what keeps the pager and the panel's scroll off this
    // drag. It used to also walk every ancestor and assign `interactive` false
    // and then true, which destroyed their bindings for the rest of the session:
    // after one tap the panel rubber-banded under any drag, and the pager turned
    // in edit mode.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        preventStealing: true
        hoverEnabled: true
        cursorShape: root.isDraggingKnob ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        onPressed: (mouse) => {
            root.isDraggingKnob = true;
            root.knobDragX = Math.max(root.posLeft, Math.min(root.posRight, mouse.x - root.knobSize / 2));
        }

        onPositionChanged: (mouse) => {
            if (root.isDraggingKnob) {
                root.knobDragX = Math.max(root.posLeft, Math.min(root.posRight, mouse.x - root.knobSize / 2));
            }
        }

        onReleased: (mouse) => {
            root.localOverrideIndex = root.hoverIndex;
            overrideResetTimer.restart();
            root.isDraggingKnob = false;
            root.applyStateIndex(root.hoverIndex);
        }

        onCanceled: {
            root.isDraggingKnob = false;
        }
    }
}
