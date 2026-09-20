# cw-gestures — notes

## The owner-coupling decision: loosened, not documented as list-only

**Confirmed with cw-notifications via the orchestrator, after landing this fix**: both of its
real `SwipeDismissible` owners have a genuine `ListView` ancestor (the outer
`NotificationListView`, and a `StyledListView` inside `NotificationGroup`), so `owner.parent.parent`
already resolved for both and neither needed anything from this session to keep working —
"document as list-only" was a fully available, zero-risk answer, not something the loosening was
covering for on short notice. Chose loosening anyway, because the brief's "either/or" was a
real decision to make once, not a decision to make only if someone was blocked on it today: the
guards are mutation-tested to be no-ops on the existing ListView-owned case (verified above and
in `tools/check-swipe-dismissible.py`), so there is no cost to the working callers, and the
payoff is that the next `ii-clipboardToast`-shaped caller does not have to hand-rewrite the
widget the way that one did. The crash sites the orchestrator's relay named
(`destroyWithAnimation`, `onDraggingChanged`, `onDragDiffXChanged`) are exactly the three this
session already found and gated on `hasSharedDragState` — matches independently confirmed.

Chose loosening. `SwipeDismissible.qmlParent` was `readonly property var: owner?.parent?.parent`,
then called `.resetDrag()` and wrote `.dragIndex`/`.dragDistance` on whatever that resolved to,
unconditionally. Inside a `StyledListView` delegate that guess lands on the `ListView` itself
two hops up, which is where `dragIndex`/`dragDistance`/`resetDrag()` actually live — the
contract is real, just structural rather than declared. Anywhere else the guess still resolves
to a real `Item` (a grandparent always exists), just one with none of those three members, so
the first drag called a method that does not exist on it. `ii-clipboardToast` hit exactly this
and hand-rolled its own dismiss instead (`.audit/ii-clipboardToast/notes.md`).

Two independent problems, both fixed:

1. **The crash.** `qmlParent` is no longer `readonly`, so a caller whose shared state lives
   somewhere else can hand it in directly. Every place that calls or writes through it is now
   gated on `hasSharedDragState` (`typeof root.qmlParent?.resetDrag === "function"`), checking
   the *shape*, not just truthiness — a `qmlParent` that resolves to a real but unrelated Item
   is exactly the case a plain `?? `/optional-chain read cannot catch, because reading an
   undeclared property quietly returns `undefined`, but calling or assigning through the same
   reference does not fail as quietly. With the gate, a `qmlParent` that isn't list-shaped is a
   no-op, not a crash.
2. **The silent no-op underneath it.** Even without the crash, a standalone owner would never
   have moved: the row-itself branch of `xOffset` read `parentDragDistance`
   (`qmlParent?.dragDistance ?? 0`), which is only ever nonzero because *this same row* writes
   it up to the parent as a broadcast for its neighbours. With no parent, that round trip
   returns 0 forever, so `dragDiffX` (DragManager's own live diff, already tracking the mouse
   correctly) never reached the screen. Fixed by reading `root.dragDiffX` directly for that
   branch. **The *condition* (`dragIndexDiff == 0`) is unchanged on purpose** — only the value
   moved. `dragIndexDiff == 0` is true with no parent at all too (`parentDragIndex` and
   `itemIndex` both default to -1), and, importantly, it stays true through the
   release-to-`resetDrag()` window the same way with a real parent, which a `root.dragging`-based
   condition (tried first, see below) does not.

Neighbour-follow (the 0.3/0.1 fractions) only ever fires with a real shared parent — a lone
item has no neighbours to move, so nothing further was needed there.

### Rejected: gating the self-case on `root.dragging` instead of `dragIndexDiff == 0`

More "obviously correct" at first — `dragging` is this instance's own authoritative state,
independent of any index bookkeeping, and it even fixes a latent bug where two rows sharing one
`itemIndex` would move in lockstep. **Regresses the exit animation.** `dragging` is already
`false` by the time `onDragReleased` (and so `destroyWithAnimation`) runs — `DragManager.onReleased`
sets it before emitting. `destroyWithAnimation`'s second line
(`target.anchors.leftMargin = target.anchors.leftMargin`, "break binding") reads `xOffset` at
that exact moment to freeze it before the exit `NumberAnimation` takes over. With the condition
on `dragging`, that read had already fallen through to the neighbour branches — `0` for a row
past the dismiss threshold — so the frozen start position snapped to 0 a frame before the
exit animation ran, i.e. the card would visibly snap back to place and then fly out, instead of
continuing its slide. `dragIndexDiff == 0` does not have this problem: `resetDrag()` (called one
line earlier, guarded) changes `parentDragIndex` to -1, which for any real `itemIndex >= 0`
already fails `dragIndexDiff == 0` on its own — the condition falls through to the same `: 0`
catch-all in both the old code and mine, so nothing about the release-time behaviour changed
for the real `StyledListView` case. Verified by tracing both call orders by hand; not run in
the shell (rule 5) since it doesn't need one — the sequencing is fully determined by source.

## §3.6 — "lifts, does not fade, takes the 0.16 layer"

**`SwipeDismissible`/`DragManager` already satisfy "does not fade"** — neither file touches
`opacity` anywhere, checked by reading, not by omission. Nothing to change.

**The lift is a caller decision, and it stays one.** Neither of my six files paints an item that
could visibly lift:
- `SwipeDismissible` only ever writes `target.anchors.leftMargin`. The row's own background,
  shadow and colour are `NotificationItem.qml`/`NotificationGroup.qml` — `cw-notifications`'
  files, mid-edit in this same run. `dragging` was already public (inherited from
  `DragManager`) before this session; a caller wanting the 0.16 tint or an elevation lift while
  dragging already had what it needs to key off. Documented explicitly in the file's own
  docstring now so the next reader doesn't have to trace it.
- `ResizeHandler` emits `resized`/`resizedXY` and paints only its own corner grip (the
  hover/press arc, already state-layered on `elementMoveFast`, unchanged) — the widget being
  resized is entirely the caller's (`MediaWidget.qml`'s) business.
- `AbstractWidget`'s own `drag.target: draggable ? root : undefined` is the one place in this
  family where a *widget itself* — not a proxy row — could lift on its own drag. Deliberately
  not touched; see below.

### Rejected: adding a generic drag-lift to `AbstractWidget`

`AbstractWidget.drag.target` looked like the obvious place for a shared 0.16/lift default,
matching the tranche's "correctness the caller doesn't have to opt into" goal. Checked both real
callers first (rule 9) — `grep -rn "AbstractWidget\b"` outside its own file finds exactly two:
`AbstractBackgroundWidget.qml` and `StyledOverlayWidget.qml` (via `AbstractOverlayWidget`).
**Both override `drag.target: undefined`** and drive their own `x`/`y` from a `DragHandler` or
hand-rolled pointer math instead. `AbstractWidget`'s built-in drag path is dead code for 100% of
today's callers, so a lift keyed off it would never fire — pure speculation, the thing this
library already has too much of.

Worse than merely unused: `AbstractBackgroundWidget` already implements its own lift —
`property real dragLift: isDragging ? 1.03 : 1.0` — multiplied straight into `root.scale`
alongside its lock/lifecycle scale factors (`AbstractBackgroundWidget.qml:830-837`). Adding a
second, base-class-driven write to the same `scale` property would be two bindings competing for
one property, which is exactly the shape of regression this family was warned about, not a
fix. `StyledOverlayWidget` has no lift at all (only `z: dragHandler.active ? 2 : 1`, a
raise-to-front, which is a different thing) — a real gap, but one that belongs in that file,
which is a caller, not mine to add to.

### Found, not touched: a duration literal doubling as an implicit flag

`AbstractWidget`'s two `NumberAnimation`s pick `Easing.OutCubic` with no bezier curve — bypassing
`Appearance.animationCurves` entirely — whenever `animDuration == Math.round(450 *
Appearance.animMultiplier) || animDuration > 500`. `StyledOverlayWidget` is the only caller that
ever sets `animDuration` to that exact `450 * multiplier` value (a resize-settle animation), so
this is a hand-fitted curve selected by *matching a specific caller's chosen number* rather than
an explicit flag. Fragile (change either constant and the special case silently stops
matching) and a real "hand-fitted easing" of the kind other families were asked to tokenise, but
fixing it properly wants an explicit property on `StyledOverlayWidget` (a caller I cannot edit)
and a visible motion change I cannot measure at 60fps without running the shell (rule 5) for a
path outside this family's brief. Recorded rather than bodged.

### Also noticed: `ResizeHandler`'s `opacity: … ? 0.85 : 0`

Not a state-layer tint (nothing it dims sits over content at a fixed colour — it's the whole
grip's visibility), not one of DESIGN.md's four state opacities, not caught by
`check-design.py`, and not called out in the brief. Left alone; flagging in case a later pass
wants a token for "affordance visible on hover" generally.

## Needs a change outside this family

**The overscroll drag-overhang item turned out not to need anything from `DragManager`/
`SwipeDismissible` at all** — worth stating plainly since the brief assumed it would. Read
`StyledFlickable.qml`, `StyledListView.qml`, `WheelScrollHandler.qml` (all `cw-scaffolding`'s,
not edited). `StyledListView`/`StyledFlickable`'s own vertical drag-to-scroll is `Flickable`'s
**built-in** touch/mouse drag — it does not go through any `MouseArea` of mine at all;
`WheelScrollHandler` is itself a `MouseArea` with `acceptedButtons: Qt.NoButton`, so it only ever
sees wheel events, never the drag. There is no "drag tracking" for a Flickable's own drag gesture
to add to `DragManager`/`SwipeDismissible` — Qt's `Flickable` already tracks it, natively:

- `Flickable.verticalOvershoot` (confirmed present in this system's Qt6 —
  `/usr/lib/qt6/qml/QtQuick/plugins.qmltypes:5323`) reports exactly "the drag overhang" live,
  once `boundsBehavior` includes `Flickable.StopAtBounds` (also confirmed in the same
  `.qmltypes`) — which is precisely the flag cw-scaffolding's notes.md already named as half the
  fix. No new tracking code, anywhere, is needed to produce this number.
- `Flickable.dragging` (also confirmed present) is the native "is a drag live right now" bool —
  the same role `SwipeDismissible.dragging` plays for the swipe-to-dismiss case, already built
  in for this one.

Concretely, in `StyledFlickable.qml`:

```qml
boundsBehavior: Flickable.StopAtBounds   // was DragOverBounds

onVerticalOvershootChanged: wheelHandler.overscroll = root.verticalOvershoot
```

placed next to the existing `onContentYChanged: wheelHandler.syncTarget()`. The existing
`contentItem.transform: Scale { … }` block (already reading `wheelHandler.overscroll`) needs no
change at all — one `overscroll` now has two producers (wheel deltas, drag overhang) instead of
one. Same two lines in `StyledListView.qml` (its `boundsBehavior` is at line 92, its
`onContentYChanged` at line 129).

One thing I could not verify without running the shell and did not want to guess at as a second
change bundled into the same recommendation: `WheelScrollHandler.overscroll` carries its own
500ms `Behavior` (`elementMove`), which is fine for discrete wheel ticks but would fight a
continuously-updating drag source, chasing a moving target the whole time the finger is past the
bound. This codebase already has the idiom for exactly this
(`NotificationItem.qml`'s `Behavior on anchors.leftMargin { enabled: !dragManager.dragging }`) —
the likely correct shape is `Behavior on overscroll { enabled: !handler.flickable.dragging; … }`
in `WheelScrollHandler.qml` so the live drag tracks 1:1 and only the release/settle animates. Not
included as a flat instruction because cw-scaffolding's own notes.md is explicit that this family
measures motion with a harness before committing to a specific Behavior shape rather than
asserting one — same discipline should apply here, and it's their file to measure it in.

Horizontal case not addressed — both files are vertical lists/panels; a horizontal
`StyledFlickable` caller, if one exists, would want `horizontalOvershoot` mirrored the same way.

## Also fixed here, found while reading

- `DragManager.qml` imported `qs.modules.common` and `qs.services` and used neither — confirmed
  by reading and by qmllint's `unused-imports`. Both deleted (`SwipeDismissible`, which extends
  it and does use `qs.modules.common`, imports it itself; a derived file's imports are its own).
- `AbstractOverlayWidget.qml` imported `Quickshell` and `qs.modules.common`, used neither (it is
  14 lines of two boolean properties). Both deleted.
- `AbstractWidget.qml` imported `Quickshell`, used nothing from it (`qs.modules.common` stays —
  `Appearance.animation`/`animMultiplier` are real uses). Deleted.
- `DragManager.onCanceled: (mouse) => { …; released(mouse); }` — qmllint's
  `signal-handler-parameters`: `MouseArea.canceled` carries no `MouseEvent`, so `mouse` was
  always `undefined` here, silently. `onReleased`'s own body never reads any field of `mouse`, so
  re-emitting `released()` with no argument is behaviourally identical — this is a genuine no-op
  fix, not a guess, and it removes a latent trap for whoever adds a `mouse.button` check to
  `onReleased` later and gets `undefined` from this path only.

## The check this left behind

`tools/check-swipe-dismissible.py` — one file, two things, because they're both "the dismiss
contract" and both invisible to `check-design.py`:

1. DESIGN.md 3.6's two numbers: `dragConfirmThreshold: 70`, and the `0.3`/`0.1` neighbour
   fractions (matched as `* 0.3`/`* 0.1` specifically — both digits already appear in this file's
   own docstring prose, which must not satisfy the check; caught this exact false-pass while
   mutation-testing and tightened the regex).
2. The owner-coupling fix stays fixed: all three reaches into `qmlParent` (`resetDrag()`,
   `.dragIndex =`, `.dragDistance =`) stay gated on `hasSharedDragState`, `qmlParent` stays
   non-`readonly`, `xOffset`'s own-row branch keeps reading `root.dragDiffX`, and
   `DragManager` keeps exposing `dragDiffX` (a rename there would silently break the fix without
   either file's own diff looking wrong).

Mutation-tested against all seven assertions (threshold, both fractions independently, each of
the three guards independently, `readonly` reappearing, the own-row source reverting, and
`DragManager` losing `dragDiffX`) by editing a scratch-backed copy of the real file, confirming
`FAIL` with the right message each time, then restoring byte-for-byte
(`diff` against a pre-edit backup) before moving on.

## Gates

- `check-design.py --diff`, filtered to this family's six paths: clean, no output.
- `qmllint` (own shadow tree, `tools/p3-widget-port/mkshadow.sh`): exit 0 on all six files.
  Remaining warnings are all `[missing-property]` on `Appearance.*`/`QObject` — the same
  singleton-resolution noise on every line in every file that touches `Appearance`, present on
  lines I never edited too, not specific to this family — plus one pre-existing `[unqualified]`
  in `WidgetCanvas.qml`'s nested `Canvas` (see below). No errors.
- `tools/check-swipe-dismissible.py`: passes, mutation-tested (above).
- `tools/check-m3-tokens.py`, `tools/check-button-states.py`: pass, unaffected (sanity-checked;
  neither targets anything in this family).

## Noticed, not touched, needs a shell to verify safely

`WidgetCanvas.qml:48`, inside `dotGrid`'s inline `sourceComponent: Canvas { onPaint: { …
root.alignmentGridStep … } }`, qmllint flags `[unqualified]` and suggests
`pragma ComponentBehavior: Bound` (already used elsewhere in the tree, e.g.
`StyledOverlayWidget.qml`). Did not add it: this exact `FadeLoader`/nested-`Canvas` structure
carries its own extensive comments about a previously-fixed performance regression (~20k dots
repainted per frame during the lock animation), and DESIGN.md 2.9 separately warns that an async
`Loader` combined with implicit cross-boundary access in this general shape is where this
codebase's one segfault class lives. `pragma ComponentBehavior: Bound` is normally the safe,
correct fix for exactly this warning, but this file has already been performance-debugged once
and I have no way to confirm at 60fps (rule 5: no `qs -c ii`) that it stays that way. Left for a
session that can run the shell.

## Driving this family, for the next session

- `/usr/bin/qmllint` is the Qt5 stub other families' notes already warn about — prints nothing,
  exits 255. `/usr/lib/qt6/bin/qmllint` is the real one; confirmed here too.
- `tools/p3-widget-port/mkshadow.sh` (not `tools/audit/`) is the shadow-tree builder; it `rm -rf`s
  its output dir, so a private one per session is not optional.
- `Appearance.*` reads as `[missing-property] on QObject` for every line in every file that
  touches it, everywhere in this tree, including lines untouched by this session — it's the
  singleton's own dynamic (`FileView`/`JsonAdapter`-backed) shape defeating qmllint's static
  resolution, not a per-file problem. Don't chase it; it isn't yours to fix and isn't evidence of
  anything broken.
