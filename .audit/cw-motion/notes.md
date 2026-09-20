# cw-motion — notes

## The inherited bug: fixed here, one line of follow-up elsewhere

`animations/PlaceholderOpeningAnimation.qml`'s icon swing (`rotationAnim`) used to be a
`PropertyAnimation` with `target: targetPlaceholder.iconWidget; property: "rotation"`.
That property is not free real estate: `PagePlaceholder.qml` already owns a binding on
it (`rotation: { root.iconSpec = shown ? enter : exit; return shown ? 0 : -70 }`, its
own §2.9 fix from `cw-scaffolding`). A `PropertyAnimation` driven by `target`/`property`
from *outside* the object that owns the binding is a plain value write on every frame,
and any such write clears whatever binding was on the property first — same class of
bug as `Behavior on scale` over a `scale:` binding (DESIGN.md 2.9, 10.4), just reached
via `animation.restart()` instead of a `Behavior`. First trigger: the swing plays once,
correctly, and permanently overwrites `rotation` with a plain `0`. Every `shown` toggle
after that does nothing — `iconSpec`'s side effect stops firing too, so even a future
fix to `rotation` alone would leave the enter/exit spec frozen on whichever it was last.

**Fixed inside this family**: the swing no longer targets `iconWidget.rotation` at all.
It now animates a new property on `PlaceholderOpeningAnimation` itself,
`iconRotationOffset` (always settles back to 0 at the end of every run, so there is
nothing to reset-on-hide). `PagePlaceholder`'s binding is therefore never written to
from outside again — the destructive write is gone, permanently, regardless of how many
times the trigger fires. That is the actual bug ("after one trigger, shown no longer
rotates the icon") fully closed from this side.

**What is left, and why it is not an edit made here**: the swing is currently invisible
end-to-end, because nothing reads `iconRotationOffset` yet. Making it visible again
means composing it into `PagePlaceholder`'s own `rotation` expression — the textbook
"animate a helper property and compose" DESIGN.md 2.9 prescribes, mirroring
`DockButton`'s `scale: hoverScale * pressScale`. That binding is owned by
`cw-scaffolding`, already landed, out of this family's file list.

### Needs a change outside this family

`dots/.config/quickshell/ii/modules/common/widgets/PagePlaceholder.qml`, inside the
`MaterialShapeWrappedMaterialSymbol { rotation: { ... } }` block (currently lines 73-76):

```qml
            rotation: {
                root.iconSpec = root.shown ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit
                return (root.shown ? 0 : -70) + openingAnimation.iconRotationOffset
            }
```

Only the `return` line changes (`+ openingAnimation.iconRotationOffset` appended).
`openingAnimation` is already the id of the `PlaceholderOpeningAnimation` instance in
that same file (line 38-41), so this is the only line that needs to move. Once applied,
the opening flourish is visible again, correctly landing on whichever `shown` value is
current instead of hard-resetting to 0, in all four callers
(`sidebarPolicies/Anime.qml`, `sidebarDashboard/notifications/NotificationList.qml`,
`sidebarPolicies/AiChat.qml`, `sidebarPolicies/Hermes.qml`).

### What was tried and rejected for a same-file fix

- **Mirror the binding with `Qt.binding()`** (`iconWidget.rotation = Qt.binding(() =>
  shown ? 0 : -70)` restored at the end of the swing). Works for the *value*, but
  `iconSpec`'s side effect lives in the same closure — mirroring the value without the
  side effect leaves `iconSpec` frozen after the first restore, i.e. every future
  `shown` transition plays on a single fixed spec instead of switching enter/exit. Fully
  mirroring both means duplicating PagePlaceholder's `-70`/spec-switch logic in a second
  file, which is the exact cross-file coupling this family is supposed to be removing,
  not adding.
- **`Binding { restoreMode: Binding.RestoreBinding }`**, toggled on/off around the swing,
  driving `rotation` from a helper property. This is the actual Qt feature built for
  "temporarily own a property, then hand the original binding back," and it would
  restore `iconSpec`'s side effect for free (same `QQmlBinding` object, not a copy). Not
  shipped: it depends on how `MaterialShapeWrappedMaterialSymbol`'s own
  `Behavior on rotation` reacts to a `Binding` element's writes vs. a raw
  `PropertyAnimation`'s (Qt suppresses a `Behavior` for the latter; the former is
  untested here), and confirming that needs a running shell, which this session doesn't
  have. Worth a look if the PagePlaceholder one-liner above is ever not wanted.

## Carousel.qml

Three `duration:`-plus-broken-curve spots, all the same shape: `easing.type:
Easing.BezierSpline` with no `easing.bezierCurve` at all (undefined control points —
this is not "linear", it is unspecified, the same shape as the brief's own
`HighlightOverlay` example). Read as one problem wearing two counts ("3 and 3
hand-fitted easings"): fixing the token also completes the curve.

- Badge opacity fade -> `elementMoveFast` (opacity is effects, never overshoot).
- `snapAnim` (`contentX`) -> `Appearance.animation.scroll`, named for exactly this in
  DESIGN.md 2.3 ("programmatic scrolling").
- `expandAnimation` (`height`) -> `elementMove`. **This one has no caller anywhere in
  the file or the repo** (`grep -rn expandAnimation` outside Carousel.qml finds nothing;
  nothing calls `.start()`/`.restart()` on it inside the file either — `expanded` is
  declared and never read). Tokenised anyway rather than deleted: a duration is still a
  guess or a token regardless of whether the code path is exercised, and deleting an
  animation object is a bigger call than this family's brief asked for. Flagging here in
  case a future session wants to either wire it up or remove it.

Left alone: `_animProgress`'s `Behavior` (`elementMove.duration * 1.7`) — already
tokenised, not a hit, and the `* 1.7` is a one-time "play once at creation" scale-up for
the initial `showOpenningAnimation` reveal, not a repeated-toggle case, so the
`Component.onCompleted` imperative set that follows it doesn't have the same
binding-destruction problem as PlaceholderOpeningAnimation — nothing ever needs that
binding to fire again after construction.

**Observation, not fixed (belongs to `cw-effects`, not owed by this family's brief):**
the carousel's delegate (`Repeater { delegate: Item { ... layer.enabled: true;
layer.effect: OpacityMask { ... } ... } }`) is a per-corner-radius mask applied inside a
repeated delegate — exactly the §8/§10.11 shape ("never an effect inside a delegate that
can appear more than ~20 times"). `favouritesCarouselModel` is usually small, but nothing
caps it. Pre-existing, not introduced here, not in cw-motion's owed list (cw-effects's
section is explicitly where "the widgets a delegate would nest" gets audited) — noted so
it isn't lost.

## ErrorShakeAnimation.qml

Five-leg decaying shake (50/50/40/40/30ms). Every `Appearance.animation.*` spec is a
two-point tween; none of them is a 5-leg decay, and forcing one onto each leg (e.g. all
five at `elementMoveSmall`'s 350ms) would turn a ~210ms "no!" shake into a 1750ms flail —
a real behaviour change, not a token rename. Marked `design-ok` per-line instead
(matching `LightDarkPreferenceButton`'s precedent for a justified, non-AOSP exception),
with the reasoning in one comment above the block. This is a one-shot acknowledgement
(2.7) that is *meant* to overshoot past `distance` — that decay is the whole effect.

## The wipes / TransitionImage

`Crossfade`, `RevealWipe`, `Wipe`'s `duration` stays a caller-set property — confirmed
by reading `TransitionImage.qml`: it always binds `item.duration = Qt.binding(() =>
root.animationDuration)` onto whichever effect it loads. Gave each a real default
(`Appearance.animationCurves.expressiveSlowSpatialDuration`, 650) since "an
unparameterised caller is already correct" is this family's own charter, even though
the one real caller always overrides it.

Both `RevealWipe` and `Wipe` shared one hand-fit inline bezier, byte-for-byte identical
in both files (`[0.227, 0.877, 0.959, 0.310, 1.0, 1.0]`) — a single curve someone picked
once and copied. Replaced with `Appearance.animationCurves.emphasizedDecel`, which
DESIGN.md 2.4 names for exactly this ("entering, appearing, expanding") and which does
not overshoot past 1 (a mask that overshot its target scale and eased back would visibly
pulse). `Crossfade`'s plain opacity fade got `expressiveEffects` instead (the effects
family curve, opacity-appropriate) rather than the spatial `emphasizedDecel` used for the
other two, since it animates opacity, not a mask's scale/width.

`Outer.qml`/`Radial.qml`'s `maskRadius: 100` -> `Appearance.rounding.full`. Both wrap a
200x200 mask (RevealWipe's own default), so radius 100 = a full circle; `rounding.full`
(9999) clamps to the same circle via Qt's own radius-vs-half-dimension clamping, and
self-adjusts if `maskWidth`/`maskHeight` ever change, which a hardcoded 100 would not.
Left `Diamond.qml`/`Slash.qml`'s `100`/`50`/`200` alone — those are load-bearing
Manhattan-distance geometry tied to the mask's own size (commented in the files
themselves), not a rounding value; not a design token at all.

`TransitionImage.animationDuration` (1100 radial / 1000 other) is a real, deliberate,
full-screen wallpaper-crossing duration with no `Appearance` spec anywhere near that
scale (max named is 650). Left the numbers, added a `design-ok` citation rather than
inventing a new "XLong" spec for a single caller. The async-`Connections` hit
(`target: effectLoader.item`) was a checker false positive in practice — `effectLoader`
has no `asynchronous: true` of its own (the string match came from an unrelated `Image`
property default elsewhere in the file) — but `?? null` is free and matches the
documented convention (DESIGN.md 2.9), so added it anyway.

## animations/BounceAnimation.qml, DelayedPropertyAnimation.qml, TriggerAnimation.qml

`TriggerAnimation` needed nothing: it has no duration of its own (the caller supplies
the whole `Animation` object), so "the default comes from Appearance" is vacuously true.

`DelayedPropertyAnimation`'s `duration`/`easing` are aliases onto its own bare
`PropertyAnimation` — no explicit default existed, so an unparameterised caller silently
got Qt's built-in 250ms/Linear. Gave the inner `anim` a real default
(`Appearance.animation.elementMove`, "the default for position and size"); every current
caller of this and `BounceAnimation` already overrides what it cares about, so nothing
visible changes.

`BounceAnimation` was **not** in the brief's sanctioned-knobs list (only
`TriggerAnimation`, `DelayedPropertyAnimation`, "the wipes" are named) — read that as a
signal to tighten it rather than just tokenise its default. It has exactly one caller in
the whole repo (`PlaceholderOpeningAnimation`, same family), so rule 9 is trivially
satisfiable: defaulted `totalDuration` to `Appearance.animation.clickBounce.duration`
("press feedback springing back" is precisely what this widget is a generic version of),
cited `peak: 1.1` to `FastBitmapDrawable.HOVERED_SCALE` (already exactly that value, just
uncited before), and dropped the caller's `peak: 1.1; totalDuration: 400` overrides since
they now match the new default exactly. Net effect: the icon swing (now 350ms via
`elementMoveSmall`) and the scale bounce (now 350ms via `clickBounce`, was 400ms) finish
together instead of the bounce trailing the rotation by 150ms — tighter, not looser.

## The check this left behind

`tools/check-motion-defaults.py` — asserts the five files where a caller-supplied
duration is legitimate (`DelayedPropertyAnimation`, `BounceAnimation`, `Crossfade`,
`RevealWipe`, `Wipe`) still default to `Appearance.*`, and that none of their
`easing.bezierCurve`s regressed to an inline array. Mutation-tested against isolated
scratch copies (never the real files) three ways — a literal duration, an inline bezier
array, a deleted default — all caught at the right line. `TriggerAnimation` is
deliberately not in the checker's file list: it has no duration property to regress.

## Gates run

- `check-design.py --diff` filtered to this family: 0 findings (grep on the filtered
  command produces no output — clean).
- `check-design.py -v` (full repo) filtered to this family: also 0 findings — no
  pre-existing debt left in any file this family touched.
- `qmllint` via a private shadow tree: 96 warnings across the 15 files, all pre-existing
  (verified two ways: (a) every finding sits on a line outside this session's diff
  hunks, mostly `Carousel.qml`'s repeater delegate and the two `Layout.*`-by-string
  animation files' unused `QtQuick.Layouts` imports; (b) the 58 `missing-property` hits
  on `Appearance.animation.X`/`Appearance.rounding.X` reproduce identically against
  `PagePlaceholder.qml` and `RippleButton.qml`, neither touched this session nor flagged
  by `cw-scaffolding`/`cw-buttons`'s own notes — `Appearance.animation`/`.rounding` are
  typed as bare `QtObject`, so qmllint cannot resolve members on them anywhere in the
  shell). Zero new warnings introduced.
- `check-m3-tokens.py`: passes (springs, state layers, opacities all still match AOSP —
  nothing in this family touches a token's own value).
- Full existing checker suite (`check-button-states.py`, `check-scaffold-containers.py`,
  etc., including siblings' new ones already in the tree): all pass.

## Needs a running shell to verify

Every timing change here is a like-for-like token swap or a documented, small,
deliberate retiming (BounceAnimation 400ms -> 350ms; the wipes' curve from a hand-fit
bezier to `emphasizedDecel`, same duration). None of it was measured at 60fps
(DESIGN.md's own rule 4 and the checklist's last line) because this session cannot run
`qs -c ii` under the parallel rules. Worth a real capture once the shell is free:
- The wallpaper transition curve swap (`RevealWipe`/`Wipe`: hand-fit bezier ->
  `emphasizedDecel`) — same duration, different shape; should still read as a clean
  expanding reveal with no overshoot-then-settle wobble on the mask.
- `PlaceholderOpeningAnimation`'s icon swing once the `PagePlaceholder.qml` one-liner
  above is applied — confirm the composed rotation lands correctly on repeated
  show/hide/trigger cycles, not just the first one.
