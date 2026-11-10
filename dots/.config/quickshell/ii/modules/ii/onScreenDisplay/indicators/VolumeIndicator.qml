import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay
import qs.modules.common.widgets
import qs.modules.common

OsdMaterialValueIndicator {
    id: root

    value: Audio.sink?.audio.volume ?? 0
    icon: {
        const muted = (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false;
        const vol = root.value;
        if (muted) return "volume_off";
        if (vol <= 0.33) return "volume_mute";
        if (vol <= 0.66) return "volume_down";
        return "volume_up";
    }
    shape: MaterialShape.Shape.Cookie7Sided
    // Red past the protection limit (inclusive, as Audio clamps to it), or past 100%
    // with protection off. The half percent turns it red exactly when the number shown
    // does: PipeWire's cubic volume reads 1.0000001 at 100%.
    maxLimit: ((Config.options.audio?.protection?.enable ? Config.options.audio.protection.maxAllowed : 100) + 0.5) / 100
}
