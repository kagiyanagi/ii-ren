// Rotated square growing from a random point. A 200x200 diamond reaches
// 100 * sqrt(2) from its centre, so Manhattan distance is the right metric.
import qs.modules.common.widgets.transitions

RevealWipe {
    id: effect
    maskRotation: 45
    targetScale: (cx, cy) => effect.manhattanMax(cx, cy) / (100 * Math.SQRT2)
}
