pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Column {
    id: root
    required property string categoryName
    // The binds this block shows, already filtered and already cut to a length
    // that fits a column -- CheatsheetKeybinds owns the packing, because only it
    // knows how tall the viewport is.
    required property var binds
    // True when this is the second or later block of a category too long for one
    // column, so the heading says it is picking up where the last one left off.
    property bool continued: false
    readonly property bool isCategorized: categoryName?.length > 0
    // Reported up so every block of every category lands on one key-column width.
    property int measuredBindWidth: 0
    property int sharedBindWidth: 0
    property real columnSpacing: 40
    property real titleSpacing: 8
    property real rowSpacing: 4

    // Excellent symbol explaination and source :
    // http://xahlee.info/comp/unicode_computing_symbols.html
    // https://www.nerdfonts.com/cheat-sheet
    property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
      })
    property var functionSymbolMap: ({
        "F1":  "󱊫",
        "F2":  "󱊬",
        "F3":  "󱊭",
        "F4":  "󱊮",
        "F5":  "󱊯",
        "F6":  "󱊰",
        "F7":  "󱊱",
        "F8":  "󱊲",
        "F9":  "󱊳",
        "F10": "󱊴",
        "F11": "󱊵",
        "F12": "󱊶",
    })

    property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
        "Scroll ↑/↓": "󱕒",
        "Page_↑/↓": "⇞/⇟",
    })

    property var keyBlacklist: ["SUPER_L", "SUPER_R"]
    property var keySubstitutions: Object.assign({
        "Super": "",
        "Mouse_up": "Scroll ↓",    // ikr, weird
        "Mouse_down": "Scroll ↑",  // trust me bro
        "Mouse:272": "LMB",
        "Mouse:273": "RMB",
        "Mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter",
        // "Shift": "",
      },
      !!Config.options.cheatsheet.superKey ? {
          "Super": Config.options.cheatsheet.superKey,
      }: {},
      Config.options.cheatsheet.useMacSymbol ? macSymbolMap : {},
      Config.options.cheatsheet.useFnSymbol ? functionSymbolMap : {},
      Config.options.cheatsheet.useMouseSymbol ? mouseSymbolMap : {},
    )

    spacing: titleSpacing

    StyledText {
        readonly property string categoryTitle: root.isCategorized ? root.categoryName : Translation.tr("Uncategorized")
        text: root.continued ? Translation.tr("%1 (cont.)").arg(categoryTitle) : categoryTitle
        font.pixelSize: Appearance.font.pixelSize.title
    }

    Column {
        spacing: root.rowSpacing
        Repeater {
            model: root.binds
            delegate: BindLine {
                required property var modelData
                keyData: modelData
                categoryName: root.categoryName
            }
        }
    }

    component BindLine: Row {
        id: bindLine
        required property var keyData
        property string categoryName: ""
        // Only a bind this shell wrote into custom/keybinds.lua can be removed
        // from here. Everything else belongs to the shipped config, and offering
        // a delete that silently does nothing is worse than not offering it.
        readonly property int userIndex: UserKeybinds.indexOfBind(keyData.modmask, keyData.key)

        HoverHandler {
            id: rowHover
        }

        Row {
            spacing: 16
            Row {
                id: modRow
                // Re-measured, not latched at completion: the key size and the
                // split-buttons switch are live config, and a one-shot max kept
                // the old column width after either changed.
                onImplicitWidthChanged: root.measuredBindWidth = Math.max(root.measuredBindWidth, implicitWidth)
                width: Math.max(root.sharedBindWidth, root.measuredBindWidth)
                spacing: 4
                Repeater {
                    model: {
                        const modList = UserKeybinds.modNames(bindLine.keyData.modmask).map(mod => root.keySubstitutions[mod] || mod)
                        if (modList.length == 0) return []
                        if (Config.options.cheatsheet.splitButtons) return modList;
                        return [modList.join(" ")]
                    }
                    delegate: KeyboardKey {
                        required property var modelData
                        key: modelData
                        pixelSize: Config.options.cheatsheet.fontSize.key
                    }
                }
                StyledText {
                    id: keybindPlus
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.keyBlacklist.includes(bindLine.keyData.key) && bindLine.keyData.modmask > 0
                    text: "+"
                }
                KeyboardKey {
                    id: keybindKey
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.keyBlacklist.includes(bindLine.keyData.key)
                    key: {
                        const k = StringUtils.toTitleCase(bindLine.keyData.key)
                        return root.keySubstitutions[k] || k
                    }
                    pixelSize: Config.options.cheatsheet.fontSize.key
                    color: Appearance.colors.colOnLayer0
                }
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: commentText.implicitWidth + root.columnSpacing
                implicitHeight: commentText.implicitHeight
                RippleButton {
                    id: removeButton
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    implicitWidth: 24
                    implicitHeight: 24
                    visible: bindLine.userIndex !== -1
                    // Present but invisible until the row is under the pointer:
                    // a delete on every custom row at rest would be the loudest
                    // thing in a list whose whole job is to be read.
                    opacity: rowHover.hovered ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    buttonRadius: Appearance.rounding.full
                    onClicked: UserKeybinds.remove(bindLine.userIndex)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer0
                        text: "delete"
                    }

                    StyledToolTip {
                        // `removeButton`, not `parent`: a tooltip's parent is
                        // typed as a bare Item, so the lookup only resolved by
                        // luck.
                        extraVisibleCondition: removeButton.hovered
                        text: Translation.tr("Remove this custom keybind")
                    }
                }

                StyledText {
                    id: commentText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                    text: {
                        const regex = new RegExp("\\s*" + bindLine.categoryName + "\\s*:\\s*");
                        return bindLine.keyData.description.replace(regex, "");
                    }
                }
            }
        }
    }
}