// Circle growing from a random point until it covers the far corner.
import qs.modules.common
import qs.modules.common.widgets.transitions

RevealWipe {
    id: effect
    maskRadius: Appearance.rounding.full // clamps to maskWidth/2 either way; self-adjusts if that ever changes
    targetScale: (cx, cy) => Math.ceil(effect.euclideanMax(cx, cy)) * 2 / effect.maskWidth
}
