import QtQuick
import qs.modules.common

Rectangle {
    // `full` is 9999 and Rectangle clamps it to half the shorter side, and it is
    // already 0 in sharp mode -- so this is the pill radius, without a second
    // copy of the sharpMode branch.
    radius: Appearance.rounding.full
}
