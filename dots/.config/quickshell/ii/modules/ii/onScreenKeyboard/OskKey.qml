import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    property var keyData
    property string key: keyData.label
    property string type: keyData.keytype
    property var keycode: keyData.keycode
    property string shape: keyData.shape
    property bool isShift: Ydotool.shiftKeys.includes(keycode)
    property bool isBackspace: (key.toLowerCase() == "backspace")
    property bool isEnter: (key.toLowerCase() == "enter" || key.toLowerCase() == "return")
    // 48 is AOSP's minimum touch target and the key unit every width ratio below is
    // a multiple of; the fn row is one grid step shorter.
    property real baseWidth: 48
    property real baseHeight: 48
    property var widthMultiplier: ({
        "normal": 1,
        "fn": 1,
        "tab": 1.6,
        "caps": 1.9,
        "shift": 2.5,
        "control": 1.3
    })
    property var heightMultiplier: ({
        "normal": 1,
        "fn": 0.75,
        "tab": 1,
        "caps": 1,
        "shift": 1,
        "control": 1
    })
    toggled: isShift ? Ydotool.shiftMode : false

    // `keytype` says what a slot is, `shape` only says how wide. A spacer holds the
    // row's stagger -- the Caps slot every layout leaves open, because double-tapping
    // Shift locks caps -- so it has to be sizeable, which keying this on the shape made
    // impossible: two 1u holes stood in for one 1.9u key and pushed the home row 23px
    // right of where a physical board puts it.
    readonly property bool isSpacer: root.type === "spacer"
    enabled: !root.isSpacer
    colBackground: root.isSpacer ? ColorUtils.transparentize(Appearance.colors.colLayer1) : Appearance.colors.colLayer1
    buttonRadius: Appearance.rounding.small
    // Rounded, because a RowLayout hands a fractional width straight to the glyph
    // rasteriser. `?? 1` rather than `|| baseWidth`: the multiplier is missing for
    // space/expand/empty, and the old form only worked because NaN is falsy.
    implicitWidth: Math.round(baseWidth * (widthMultiplier[shape] ?? 1))
    implicitHeight: Math.round(baseHeight * (heightMultiplier[shape] ?? 1))
    Layout.fillWidth: shape == "space" || shape == "expand"

    Connections {
        target: Ydotool
        enabled: isShift
        function onShiftModeChanged() {
            if (Ydotool.shiftMode == 0) {
                capsLockTimer.hasStarted = false;
            }
        }
    }

    Timer {
        id: capsLockTimer
        property bool hasStarted: false
        property bool canCaps: false
        interval: 300
        function startWaiting() {
            hasStarted = true;
            canCaps = true;
            start();
        }
        onTriggered: {
            canCaps = false;
        }
    }

    downAction: () => {
        Ydotool.press(root.keycode);
        if (isShift && Ydotool.shiftMode == 0) Ydotool.shiftMode = 1;
    }
    releaseAction: () => {
        if (root.type == "normal") {
            Ydotool.release(root.keycode);
            if (Ydotool.shiftMode == 1) {
                Ydotool.releaseShiftKeys()
            }
        } else if (isShift) {
            if (Ydotool.shiftMode == 1) {
                if (!capsLockTimer.hasStarted) {
                    capsLockTimer.startWaiting();
                } else {
                    if (capsLockTimer.canCaps) {
                        Ydotool.shiftMode = 2; // Caps lock mode
                    } else {
                        Ydotool.releaseShiftKeys()
                    }
                }
            } else if (Ydotool.shiftMode == 2) {
                Ydotool.releaseShiftKeys();
            }
        } else if (root.type == "modkey") {
            root.toggled = !root.toggled;
            if (!root.toggled) {
                if (isShift) {
                    Ydotool.releaseShiftKeys();
                } else { 
                    Ydotool.release(root.keycode);
                }
            }
        }

    }

    contentItem: StyledText {
        id: keyText
        anchors.fill: parent
        font.family: (isBackspace || isEnter) ? Appearance.font.family.iconMaterial : Appearance.font.family.main
        // A word label steps down: at `large`, "Menu" elided to "Me..." on a key
        // wide enough to hold it, and letters reading larger than modifier names is
        // what a physical keyboard does anyway.
        font.pixelSize: (isBackspace || isEnter) ? Appearance.font.pixelSize.huge :
            (root.shape == "fn" || keyText.text.length > 1) ? Appearance.font.pixelSize.small :
            Appearance.font.pixelSize.large
        horizontalAlignment: Text.AlignHCenter
        color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        text: root.isBackspace ? "backspace" : root.isEnter ? "subdirectory_arrow_left" :
            Ydotool.shiftMode == 2 ? (root.keyData.labelCaps || root.keyData.labelShift || root.keyData.label) :
            Ydotool.shiftMode == 1 ? (root.keyData.labelShift || root.keyData.label) : 
            root.keyData.label
    }
}
