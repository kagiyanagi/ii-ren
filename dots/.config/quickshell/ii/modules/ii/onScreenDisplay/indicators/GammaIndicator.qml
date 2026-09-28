import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay
import qs.modules.common.widgets
import qs.modules.common

OsdMaterialValueIndicator {
    value: Hyprsunset.gamma / 100 ?? 0.5
    from: Hyprsunset.gammaLowerLimit / 100
    minimalFrom: Hyprsunset.gammaLowerLimit / 100
    icon: "wb_twilight"
    shape: MaterialShape.Shape.Gem

    onMoved: function(v) {
        const gamma = Math.max(Hyprsunset.gammaLowerLimit, Math.min(100, v * 100));
        Hyprsunset.setGamma(gamma);
    }
}
