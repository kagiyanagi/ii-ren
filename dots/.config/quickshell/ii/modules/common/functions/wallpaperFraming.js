// Where a wallpaper lands on a screen: how it fits, how far it is zoomed and
// which part of it shows. The desktop (Background.qml) and the preview on the
// Background settings page both draw through this, so what is framed in the
// preview is what the desktop shows. wallpaperFraming.test.js checks it with
// `node`.
//
// One entry per wallpaper, in Persistent.states.wallpaperFraming, keyed by path:
//   mode     "fill" covers the screen, "fit" shows all of it, "stretch" ignores its shape
//   zoom     1..MAX_ZOOM, on top of the mode
//   x, y     0..1 along the slack: 0 lines the left/top edges up, 1 the right/bottom.
//            A picture narrower than the screen slides inside its bars the same way
//   subject  null, or a cutout of your own: { path, x, y, zoom }, its centre as a
//            fraction of the wallpaper and its box relative to the wallpaper's

var MAX_ZOOM = 4;
var MIN_SUBJECT_ZOOM = 0.1;
var DEFAULTS = { mode: "fill", zoom: 1, x: 0.5, y: 0.5, subject: null };
var SUBJECT_DEFAULTS = { x: 0.5, y: 0.5, zoom: 1 };

function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v));
}

// A hand-edited or half-written file must not put the wallpaper nowhere: a NaN
// survives clamp() untouched, so anything not a finite number falls back first.
function num(v, fallback) {
    return typeof v === "number" && isFinite(v) ? v : fallback;
}

function entry(map, path) {
    const e = (map && map[path]) || {};
    const s = e.subject;
    return {
        mode: e.mode === "fit" || e.mode === "stretch" ? e.mode : "fill",
        zoom: clamp(num(e.zoom, 1), 1, MAX_ZOOM),
        x: clamp(num(e.x, 0.5), 0, 1),
        y: clamp(num(e.y, 0.5), 0, 1),
        subject: s && typeof s.path === "string" && s.path.length > 0 ? {
            path: s.path,
            x: clamp(num(s.x, 0.5), 0, 1),
            y: clamp(num(s.y, 0.5), 0, 1),
            zoom: clamp(num(s.zoom, 1), MIN_SUBJECT_ZOOM, MAX_ZOOM)
        } : null
    };
}

// Nothing worth storing: the entry is dropped rather than kept at its defaults.
function isDefault(f) {
    return f.mode === "fill" && f.zoom === 1 && f.x === 0.5 && f.y === 0.5 && !f.subject;
}

// The zoom the desktop has always applied before any framing: an oversized
// wallpaper zooms to background.parallax.workspaceZoom so parallax has room to
// pan, capped at what it holds, and parallax gets that room even from one cut to
// the panel. A wallpaper no bigger than the screen used to be zoomed again by its
// shortfall on top of being scaled to cover, so it showed only its middle; the
// cover scale in rect() already makes it fit.
function baseZoom(iw, ih, vw, vh, preferred, parallax) {
    if (!(iw > 0 && ih > 0 && vw > 0 && vh > 0))
        return 1;
    const s = (iw <= vw || ih <= vh) ? 1 : Math.min(preferred, iw / vw, ih / vh);
    return (parallax && s <= 1) ? preferred : s;
}

// The wallpaper's rect in screen coordinates; it may run past the screen.
// `extraZoom` is baseZoom(), which only fill takes: fit promises the whole
// picture, and a stretched one has no spare to pan over.
function rect(f, iw, ih, vw, vh, extraZoom) {
    if (!(iw > 0 && ih > 0 && vw > 0 && vh > 0))
        return { x: 0, y: 0, width: vw, height: vh };
    let w = vw, h = vh;
    if (f.mode !== "stretch") {
        const s = (f.mode === "fit" ? Math.min : Math.max)(vw / iw, vh / ih);
        w = iw * s;
        h = ih * s;
    }
    const z = f.zoom * (f.mode === "fill" ? num(extraZoom, 1) : 1);
    w *= z;
    h *= z;
    return { x: (vw - w) * f.x, y: (vh - h) * f.y, width: w, height: h };
}

function covers(r, vw, vh) {
    // Half a pixel of slack: a cover scale computed in floating point can come
    // out a hair short of the screen, and that is not a gap anyone can see.
    return r.x <= 0.5 && r.y <= 0.5 && r.x + r.width >= vw - 0.5 && r.y + r.height >= vh - 0.5;
}

// One axis of a drag. The picture follows the pointer one to one until an edge
// meets the screen's, and no further; pulling back moves it again at once, with
// no dead zone to unwind first.
function along(p, delta, slack) {
    return Math.abs(slack) < 0.5 ? p : clamp(p + delta / slack, 0, 1);
}

// Moved by (dx, dy) screen px. `r` is rect() for `f`.
function pan(f, r, vw, vh, dx, dy) {
    return Object.assign({}, f, {
        x: along(f.x, dx, vw - r.width),
        y: along(f.y, dy, vh - r.height)
    });
}

// Zoomed to `zoom`, keeping the point at screen (cx, cy) under the pointer.
function zoomAt(f, iw, ih, vw, vh, extraZoom, zoom, cx, cy) {
    const before = rect(f, iw, ih, vw, vh, extraZoom);
    const next = Object.assign({}, f, { zoom: clamp(num(zoom, f.zoom), 1, MAX_ZOOM) });
    const after = rect(next, iw, ih, vw, vh, extraZoom);
    const axis = (p, c, x0, w0, w1, v) => {
        const slack = v - w1;
        return Math.abs(slack) < 0.5 ? p : clamp((c - (c - x0) * w1 / w0) / slack, 0, 1);
    };
    next.x = axis(f.x, cx, before.x, before.width, after.width, vw);
    next.y = axis(f.y, cy, before.y, before.height, after.height, vh);
    return next;
}

// The subject's box inside a wallpaper rect w x h, in that rect's coordinates.
function subjectRect(s, w, h) {
    return { x: (s.x - s.zoom / 2) * w, y: (s.y - s.zoom / 2) * h, width: s.zoom * w, height: s.zoom * h };
}

// Its centre stays on the wallpaper, wherever the box itself hangs out to.
function subjectPan(s, w, h, dx, dy) {
    return Object.assign({}, s, { x: clamp(s.x + dx / w, 0, 1), y: clamp(s.y + dy / h, 0, 1) });
}

// Zoomed to `zoom` about (fx, fy), a point given as a fraction of the wallpaper.
function subjectZoomAt(s, zoom, fx, fy) {
    const z = clamp(num(zoom, s.zoom), MIN_SUBJECT_ZOOM, MAX_ZOOM);
    const k = z / s.zoom;
    return Object.assign({}, s, {
        zoom: z,
        x: clamp(fx + (s.x - fx) * k, 0, 1),
        y: clamp(fy + (s.y - fy) * k, 0, 1)
    });
}

// Where parallax puts a wallpaper framed at x0. `d` runs -1..1 across the
// workspaces (a little past for the sidebars' nudge), positive moving it right.
// It swings out from wherever the framing left it, as far as the picture reaches
// on that side, so one panned to an edge never opens a gap; the default framing
// is the old symmetric swing exactly.
function travel(x0, w, v, d) {
    return x0 + d * Math.max(0, d > 0 ? -x0 : x0 + w - v);
}

if (typeof module !== "undefined")
    module.exports = { MAX_ZOOM, MIN_SUBJECT_ZOOM, DEFAULTS, SUBJECT_DEFAULTS, entry, isDefault, baseZoom, rect, covers, pan, zoomAt, subjectRect, subjectPan, subjectZoomAt, travel };
