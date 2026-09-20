// Radial, run backwards: an inverted circle mask closing in on a random point.
import qs.modules.common
import qs.modules.common.widgets.transitions

RevealWipe {
    id: effect
    maskRadius: Appearance.rounding.full // clamps to maskWidth/2 either way; self-adjusts if that ever changes
    reverse: true
    invert: true
    targetScale: (cx, cy) => Math.ceil(effect.euclideanMax(cx, cy)) * 2 / effect.maskWidth
}
