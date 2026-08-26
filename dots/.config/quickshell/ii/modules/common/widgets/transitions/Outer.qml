// Radial, run backwards: an inverted circle mask closing in on a random point.
import qs.modules.common.widgets.transitions

RevealWipe {
    id: effect
    maskRadius: 100
    reverse: true
    invert: true
    targetScale: (cx, cy) => Math.ceil(effect.euclideanMax(cx, cy)) * 2 / effect.maskWidth
}
