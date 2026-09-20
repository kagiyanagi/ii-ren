# cw-misc — notes

## The real bug in this family: `AttachedFileIndicator.scale`

Not called out in the brief, found reading the file for the tokenisation pass. It
declared `property real scale: Math.min(root.maxHeight / imageHeight, root.width /
imageWidth)` as a private helper for sizing the image preview. `Rectangle`/`Item`
already has a `scale` property — the actual render transform — and QML lets you
redeclare a same-named, same-typed base property rather than rejecting it, so this
silently became the transform for the *whole card*, not just the preview.

Measured, not assumed: `imageWidth`/`imageHeight` default to `-1` and only leave it
for `image/*` mime types (see the `refresh()`/`fileTypeProc` flow). For every
non-image attachment — pdf, audio, video, text, exactly the cases the icon-picker
ternary two lines below plans for — `scale` evaluates to
`Math.min(200 / -1, width / -1)`, a large negative number, forever, and the whole
`Rectangle` (icon, filename, remove button, background) renders under that
transform. `qmllint` calls this out directly: `Property "scale" already exists in
base type "QQuickItem", use a different name. [property-override]`. Renamed to
`imageScale`; grepped all three callers (`AiChat.qml`, `Hermes.qml`,
`AiMessage.qml`) for `.scale` first per rule 9 — none read or set it, so the rename
is not observable from outside.

This is the kind of thing only a running shell (or `qmllint`) shows — a
non-image attachment would have rendered as a huge inverted card. Worth an actual
screenshot check once the orchestrator runs the shell; see "Still needs a running
shell" below.

## Finding 3, the rest of it

- `AndroidClock.qml`: `Behavior on color { ColorAnimation { duration: 400 } }` →
  `Appearance.animation.elementMoveFast.colorAnimation.createObject(this)`. This is
  DESIGN.md 2.3's own worked example (`Behavior on color` on `elementMoveFast`),
  verbatim.
- `CalendarView.qml`: `Behavior on weekDiff` called `Looks.transition.scroll` —
  `qs.modules.waffle.looks`, imported into a file under `modules/common/widgets`
  that ships to **both** panel families. This is worse than a bare literal: it's a
  common widget depending on one family's theme system. Swapped for
  `Appearance.animation.scroll` (`standardDecel` @200), which DESIGN.md 2.3 lists
  by name for "programmatic scrolling" — this is exactly what it's for. Duration
  changes 250ms → 200ms and the curve shape shifts slightly (Waffle's own
  `[0,0,0.25,1,1,1]` vs `standardDecel`'s `[0,0,0,1,1,1]`); both read as a
  decelerating scroll, nothing structural changes. The only live caller
  (`CalendarWidget.qml`, Waffle) inherits this.
- `CalendarView.qml` / `WeekRow.qml`: the fallback `delegate: Text { ... }` (bare,
  identical in both files, and — per the "Expose delegate" comment and confirmed by
  reading both real callers — never actually instantiated, since
  `CalendarWidget.qml` supplies `DayButton` and `WeekStartPicker.qml` supplies its
  own inline `Item`) → `StyledText`. Closes both of `check-design.py`'s bare-text
  hits in this family, not just WeekRow's.

## CalendarView hit targets — measured

DESIGN.md 3.4: 32px minimum, 40px where a mis-click is costly.

- `CalendarView.buttonSize` default: **40px** (unchanged — already compliant).
- The one real caller, `modules/waffle/notificationCenter/CalendarWidget.qml`:
  `buttonSize: 41`, and its `DayButton` delegate (`WButton`-rooted) is
  `implicitWidth/Height: calendarView.buttonSize`, `radius: height / 2` — paint and
  hit area are the same 41px circle. Both numbers already clear the bar; nothing
  to change.
- Neither `CalendarView` nor `WeekRow` render the actual clickable cell — the
  `delegate` is 100% caller-supplied, and `buttonSize`/`buttonSpacing` are an
  advisory contract (used only for `CalendarView`'s own `implicitHeight` math and
  read back by the caller for its own delegate and header row), not enforced onto
  the delegate. So "expand the `MouseArea`, don't inflate the paint" has no file in
  this family to apply it to — the one caller that makes a delegate clickable
  already does it right. Recorded here rather than acted on: turning
  `buttonSize`/`buttonSpacing` into an enforced contract (e.g. `CalendarView`
  sizing the delegate itself) would be a real API change to a 4-property surface
  with one caller, which is redesign, not what a lane 2 row owes.
- `CalendarView`'s own wheel-scroll `MouseArea` (`anchors.fill: parent`, `onWheel`
  only) is not a discrete click target — 3.4's minimum doesn't apply to it, and
  it's not "interactive" in finding 1's sense either (never takes focus, not in tab
  order). Pack.md's raw-primitives heuristic flags it as a possible
  `RippleButton`/`StateLayer` rebuild; that would be wrong here — a ripple firing
  on mouse wheel makes no sense. Left as a plain `MouseArea`, deliberately.

## Finding 1 (focus layer) — nothing to add

The only interactive element this family owns is `AttachedFileIndicator`'s remove
button, and it's `RippleButton`-rooted, so it already renders the 0.10 focus film
from the landed `cw-buttons` work (`Button.visualFocus` via `StateOverlay`) — per
that family's notes, not re-added here. Everything else in these four files is
either decorative (`AndroidClock`, the fallback `Text`/`StyledText` delegates) or a
layout/scaffolding widget with no control of its own (`CalendarView`, `WeekRow`);
the actual interactive delegates belong to callers, out of scope per the contract
("Callers are not redesigned here").

## Rejected / considered and left alone

- **Converting `CalendarView`'s wheel-scroll `MouseArea` to `RippleButton` or
  `StateLayer`.** It has no click action; a ripple or state layer would visually
  fire on scroll input, which is not what either mechanism is for.
- **`AttachedFileIndicator`'s `OpacityMask`+`layer.enabled` on the image preview.**
  It's used as a `Repeater`/`ListView` delegate in `Hermes.qml`, so technically an
  "effect in a repeated delegate" per §8/anti-pattern 11 — but per-message
  attachment counts are small (not the ~20+ the rule targets), the same pattern is
  standard throughout the primitives family for thumbnails, and it isn't part of
  this family's "Owes". Left alone; flagging here in case `cw-effects` or a later
  pass wants the wider picture.
- **A new `tools/check-*.py`.** Nothing in this family's diff is a branch, loop,
  parser, or money/security path. The one real bug (the `scale` collision) is
  already guarded by `qmllint`'s own `property-override` rule, which is already
  part of this family's (and presumably every family's) gate — a bespoke script
  would duplicate a check that already exists and already runs.
- **Deleting `AndroidClock.qml` as dead code.** It has zero callers anywhere in the
  repo (`grep -rl AndroidClock` outside its own file: nothing). The brief says
  "Dies: nothing" for this family, so it stays; noting the orphan status for
  whoever next looks at it, not acting on it.
- **Fixing the pre-existing `missing-property`/`unqualified-access` qmllint noise**
  (28 + 7 hits across the family, all pre-existing). This is the same
  `Appearance`-singleton pattern qmllint flags identically throughout the whole
  shipped library — confirmed against `RippleButton.qml` (already landed by
  `cw-buttons`), which carries the same two classes of warning untouched. Not part
  of any family's "Owes" anywhere in the brief; leaving it as baseline, consistent
  with precedent.

## Needs a change outside this family

None. Nothing here required touching `Appearance.qml`, `Config.qml`, or a caller —
every token this family needed (`elementMoveFast`, `scroll`) already existed.

## Still needs a running shell to verify

- `AttachedFileIndicator`'s `imageScale` fix, on an actual non-image attachment
  (pdf/audio/text) in `AiChat`/`Hermes`/`AiMessage` — the bug (whole-card transform)
  and the fix are both easiest to *see*, harder to prove from source alone.
- `CalendarView`'s week-scroll feel at 200ms/`standardDecel` vs the old
  250ms/custom curve, in the live Waffle calendar widget — should still read as a
  smooth decelerating scroll, per DESIGN.md 2.4's "measure motion, don't eyeball
  it," but this session had no shell to record it at 60fps against.
- `AndroidClock`'s background `ColorAnimation` retiming (400ms linear → 200ms
  tokenised) has no live caller to watch it on at all (see orphan note above).

## Gates run

- `python3 tools/check-design.py --diff 2>&1 | grep -E 'widgets/(AndroidClock|AttachedFileIndicator|CalendarView|WeekRow)\.qml'` —
  no output (clean). Full run's only current diff-scope finding belongs to
  `WindowDialogSectionHeader.qml` (`cw-dialogs`, a sibling).
- `qmllint` via `mkshadow.sh` into this session's own scratch shadow dir — clean
  for all four files: the `property-override` hit is fixed, all five confirmed-
  unused imports are gone, no new warnings of any kind introduced. Remaining
  28 `missing-property` + 7 `unqualified-access` lines are pre-existing baseline
  noise (see "Rejected" above).
- `python3 tools/check-m3-tokens.py` — passes (unaffected; no token definitions
  touched, only usages of existing ones).
- `python3 tools/check-text-primitives.py` — passes (unaffected; `StyledText`
  itself wasn't touched, only two new callers of it).
