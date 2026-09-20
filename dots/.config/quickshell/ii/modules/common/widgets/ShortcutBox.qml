import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

Rectangle {
    id: root
    property string text: ""
    property string value: ""
    property string targetPageId: ""
    // Deprecated — use targetPageId
    property int targetPageIndex: -1
    property string targetSectionTitle: ""
    property string linkText: Translation.tr("Go there")
    property string materialIcon: "help"

    readonly property int itemIndex: {
        var p = parent;
        if (!p)
            return 0;
        var idx = 0;
        for (var i = 0; i < p.children.length; ++i) {
            if (p.children[i] === root)
                return idx;
            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                idx++;
        }
        return 0;
    }

    readonly property int totalItems: {
        var p = parent;
        if (!p)
            return 1;
        var count = 0;
        for (var i = 0; i < p.children.length; ++i) {
            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                count++;
        }
        return count;
    }

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1
    readonly property bool isPressed: mouseArea.pressed

    readonly property bool prevIsPressed: {
        var p = parent;
        if (!p)
            return false;
        for (var i = 0; i < p.children.length; ++i) {
            var child = p.children[i];
            if (child === root)
                return false;
            if (child.visible && typeof child.topLeftRadius !== "undefined") {
                var isImmediatePrev = true;
                for (var j = i + 1; j < p.children.length; ++j) {
                    var midChild = p.children[j];
                    if (midChild === root)
                        break;
                    if (midChild.visible && typeof midChild.topLeftRadius !== "undefined") {
                        isImmediatePrev = false;
                        break;
                    }
                }
                if (isImmediatePrev) {
                    return child.isPressed === true || (child.down !== undefined && child.down === true);
                }
            }
        }
        return false;
    }

    readonly property bool nextIsPressed: {
        var p = parent;
        if (!p)
            return false;
        var foundSelf = false;
        for (var i = 0; i < p.children.length; ++i) {
            var child = p.children[i];
            if (child === root) {
                foundSelf = true;
                continue;
            }
            if (foundSelf && child.visible && typeof child.topLeftRadius !== "undefined") {
                return child.isPressed === true || (child.down !== undefined && child.down === true);
            }
        }
        return false;
    }

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on topRightRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on bottomLeftRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on bottomRightRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    // The hover tint used to be swapped in here, on colSecondaryContainerHover --
    // which is the 0.10 mix, so a hover rendered at the pressed token's strength
    // and there was no pressed or focus state at all. A StateOverlay composites
    // all three at the right opacity and keeps hover -> press -> release
    // continuous (DESIGN.md 3.1).
    color: Appearance.colors.colSecondaryContainer
    implicitWidth: mainRowLayout.implicitWidth + 32
    implicitHeight: mainRowLayout.implicitHeight + 32

    function navigateToTarget() {
        var win = root.Window.window;
        if (!win || win.currentPage === undefined) {
            return;
        }
        // Prefer the stable page id; targetPageIndex is deprecated
        var idx = (root.targetPageId !== "" && win.pageIndexById !== undefined) ? win.pageIndexById(root.targetPageId) : root.targetPageIndex;
        if (idx >= 0) {
            win.pendingSectionHighlight = root.targetSectionTitle;
            win.currentPage = idx;
        }
    }

    // Declared before the content so the film sits behind it, and it takes the
    // box's four corner radii so it follows the press morph instead of squaring
    // off inside it.
    StateOverlay {
        anchors.fill: parent
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        contentColor: Appearance.colors.colOnSecondaryContainer
        hover: mouseArea.containsMouse
        focused: mouseArea.activeFocus
        press: mouseArea.pressed
    }

    RowLayout {
        id: mainRowLayout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        MaterialShapeWrappedMaterialSymbol {
            id: icon
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignVCenter
            text: root.materialIcon
            shape: MaterialShape.Shape.Cookie9Sided
            iconSize: 22
            padding: 8
            color: Appearance.colors.colSecondary
            colSymbol: Appearance.colors.colOnSecondary
        }

        StyledText {
            id: mainText
            Layout.fillWidth: true
            text: root.text !== "" ? root.text : Translation.tr("Looking for %1?").arg(root.value)
            color: Appearance.colors.colOnSecondaryContainer
            wrapMode: Text.WordWrap
        }

        StyledText {
            id: linkLabel
            Layout.alignment: Qt.AlignVCenter
            text: root.linkText
            font.pixelSize: Appearance.font.pixelSize.small
            // Weight goes through the wght axis, not font.bold (DESIGN.md 7).
            font.variableAxes: Appearance.font.variableAxes.title
            color: Appearance.colors.colPrimary
        }

        MaterialSymbol {
            id: arrowIcon
            Layout.alignment: Qt.AlignVCenter
            text: "arrow_forward"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colPrimary
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        // Everything reachable by mouse is reachable by keyboard (DESIGN.md 3.7),
        // and this lives in the settings app, which is navigated that way.
        activeFocusOnTab: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.navigateToTarget()
        Keys.onPressed: event => {
            if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return;
            root.navigateToTarget();
            event.accepted = true;
        }
    }
}
