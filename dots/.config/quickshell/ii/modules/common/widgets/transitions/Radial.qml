// Circle growing from a random point until it covers the far corner.
import qs.modules.common.widgets.transitions

RevealWipe {
    id: effect
    maskRadius: 100
    targetScale: (cx, cy) => Math.ceil(effect.euclideanMax(cx, cy)) * 2 / effect.maskWidth
}
