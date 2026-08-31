import QtQuick
import Quickshell
import qs.services

AndroidSliderWidgetBase {
    id: root

    tooltipText: Translation.tr("Microphone")
    materialSymbol: {
        const muted = (Audio.source && Audio.source.audio) ? Audio.source.audio.muted : false;
        const vol = root.sliderValue;
        if (muted || vol <= 0.0) return "mic_off";
        return "mic";
    }
    sliderValue: (Audio.source && Audio.source.audio) ? Audio.source.audio.volume : 0
    onMoved: function(value) {
        if (Audio.source && Audio.source.audio) {
            Audio.source.audio.volume = value;
            if (Audio.source.audio.muted && value > 0) {
                Audio.source.audio.muted = false;
            }
        }
    }
}
