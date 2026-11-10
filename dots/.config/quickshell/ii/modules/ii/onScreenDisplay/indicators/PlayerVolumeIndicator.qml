import QtQuick
import Quickshell.Services.Mpris
import qs.modules.ii.onScreenDisplay
import qs.modules.common.widgets
import qs.modules.common

OsdMaterialValueIndicator {
    id: root

    // Set by OnScreenDisplay: the player whose volume changed, not the active one.
    property MprisPlayer player

    value: root.player?.volume ?? 0
    icon: root.value > 0 ? "music_note" : "music_off"
    shape: MaterialShape.Shape.Cookie7Sided
    // Red means past the sink's protection limit, which a player's own volume is not
    // subject to: a player at 100%, or one that allows more, is not a warning.
    maxLimit: Infinity
}
