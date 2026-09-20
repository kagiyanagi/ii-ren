import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: button

    required default property Item content

    // 32 is the pointer-shell minimum hit area (DESIGN.md 3.4); the glyph inside
    // stays its own size. It used to rest at 26, which is below it.
    implicitHeight: Math.max(content.implicitHeight, 32)
    implicitWidth: implicitHeight
    contentItem: content
}
