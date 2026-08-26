// Diagonal bar widening from the centre. A 100px wide slash reaches
// 50 * sqrt(2) from its centre line.
import qs.modules.common.widgets.transitions

RevealWipe {
    id: effect
    randomCenter: false
    maskWidth: 100
    maskHeight: Math.ceil(Math.hypot(effect.width, effect.height)) * 2
    maskRotation: 45
    targetScale: (cx, cy) => effect.manhattanMax(cx, cy) / (50 * Math.SQRT2)
}
