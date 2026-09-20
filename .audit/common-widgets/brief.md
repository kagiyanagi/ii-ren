# common-widgets — brief

Written for the whole `shared-widgets` cluster at once, per `.github/AUDIT.md`: fifteen
families designed together so the library comes out as one system. Each family below is
one session and one queue row; this page is the brief for all of them.

The surface template (purpose / primary action / hierarchy) does not fit a component
library — a widget has no hierarchy of its own, it *supplies* one to 80 surfaces. So the
brief is inverted: a contract every widget must meet, then what each family specifically
owes against it.

---

## The contract

**Purpose.** `modules/common/widgets/` is the reason a surface never has to decide what a
button is. Every one of the ~80 audit sessions that follows will reach for these; whatever
is wrong here is wrong 80 times, and whatever is right here is free everywhere else.

**Primary action.** Make the design law unavoidable *by default*. A caller that writes
`RippleButton {}` and nothing else must already have four states, both animation
directions, tokenised motion and a 32px hit area. Correctness the caller has to opt into
is correctness that 80 sessions will forget.

**Reference.** AOSP's own component library — `StateTokens.kt`, `MotionTokens.kt`,
`ShapeTokens.kt` — where the component *is* the token's only consumer. The measure of
this library is that `.github/DESIGN.md` §9's recipes become descriptions of what the
widgets already do, not instructions for what a caller must add.

**Hierarchy of obligation**, when a family's work is too big for one session:

1. Defaults that are wrong for every caller (a missing state, an untokenised duration).
2. Knobs that let a caller be wrong (`animationDuration` as a property).
3. Per-widget polish.

**Out of scope.** `shapes/**` (git submodule). `shaders/check*.qml` (dev harness windows,
not shipped). `modules/settings/widgets/` — its own tranche, its own row, after this one.
Callers are not redesigned here: a family fixes the widget and every caller that *breaks*,
and leaves the rest to their own audit rows.

---

## Library-wide findings

Four defects that cut across families. Each is checked, not suspected.

**1. There is no focus state anywhere in the library.** One file mentions focus at all —
`StateOverlay.qml`, and only as its own `focused` property, which four callers in the
entire shell set. `RippleButton` never reads `Button.visualFocus`. DESIGN.md §3.1 requires
four states on every interactive element; the library ships three. Harmless on a layer
surface with `keyboardFocus: None`, not harmless in the settings app, which is keyboard-
navigable and where most of these widgets live. **Every family that owns an interactive
widget renders the 0.10 focus layer.** This is the single largest item in the tranche.

**2. Pressed and hover are the same colour.** `RippleButton.colBackgroundActive:
colBackgroundHover`, and `colBackgroundToggledActive: colBackgroundToggledHover`. The
tokens are 0.08 and 0.10 and they differ deliberately. Today the press reads only through
the ripple, so any caller with `rippleEnabled: false` — every dock-style icon — has no
press feedback at all.

**3. Motion nobody chose.** `check-design.py` finds 94 mechanical hits, 22 of them literal
durations. Three shapes, all present:

- a literal that the checker catches — `HighlightOverlay` blinks on `duration: 150` with
  no curve at all, so it runs linear;
- a literal the checker's regex misses — `StyledText` writes `duration: 300 / 2`, and
  hand-fits `Easing.InSine`/`OutSine` seven times, in the widget with **471 callers**;
- a literal exported as an API — `CircularProgress` exposes `animationDuration` and
  `easingType` as properties, so every caller invents its own. That is the worst of the
  three: it does not just violate the rule, it industrialises the violation. Knobs like
  this become defaults from `Appearance.animation.*`, and the knob goes.

`ContentSection` is the one to fix first on volume alone: `duration: 200;
easing.type: Easing.OutCubic` on the disclosure arrow, in a widget with 177 callers.

**4. `StateOverlay` is the preferred mechanism and is used four times.** DESIGN.md §3.1
ranks `colLayerNHover`/`colLayerNActive` first and `StateOverlay` second, and the library
mostly does neither — it ternaries a background colour, which is the one approach that
cannot composite over a photo and cannot keep hover → press → release continuous. Families
converge on the ranked mechanisms rather than each inventing a ternary.

---

## Interaction, applying to every family

**States.** Hover 0.08, focus 0.10, pressed 0.10, dragged 0.16, disabled `opacity: 0.4` on
the whole control. Via `colLayerNHover`/`colLayerNActive` on a solid background, else
`StateOverlay`. Never a hand-mixed tint.

**Motion.** Spatial for position/size/shape and may overshoot; effects for opacity/colour
and must not. Enter on default spatial or `emphasizedDecel`; exit on fast effects or
`emphasizedAccel` at about half the duration. **Both, always** — a widget that fades in
and vanishes is the most common bug in this repo. Specs come from `Appearance.animation.*`
by name; a widget that needs a bare animator spells out duration + `BezierSpline` +
`Appearance.animationCurves.*`, never a number.

**Transform origin** on anything that scales: press feedback `Item.Center`, a popup the
corner nearest what opened it, an edge-anchored panel that edge.

**Hit area** ≥ 32px, 40px where a mis-click costs something; expand the `MouseArea`, do not
inflate the paint. `Qt.PointingHandCursor` on anything clickable.

**Keyboard.** Reachable, Escape closes, and the focus layer renders — see finding 1.

**Edge states**, for any widget that can be empty, loading, errored or single: empty is
`PagePlaceholder`, never blank space; loading is determinate wherever the duration is
known; one-item must not look like a broken list. A family whose widgets have no such
state says so in its commit rather than leaving it ambiguous.

**Shape and spacing.** Radii from `Appearance.rounding.*`, child smaller than parent,
sharp mode still correct. The 4dp grid; §5.5 forbids decorative dividers and separator
lines — whitespace and layer cards instead.

**Rule 9 governs this whole tranche.** Every widget here is shared, so no default changes
without checking its callers. The count is in each family's section. A change to
`RippleButton` (295 callers) or `StyledText` (471) is verified against a representative
caller of each shape before it is committed — that is how a pressed-shape default once
squared 58 pills.

---

## The families

Ordered as the queue runs them: the widgets other widgets are built out of come first, so
each later family inherits a fixed base instead of re-fixing it.

### 1. `cw-buttons` — 21 files, 1,471 lines · lane 1

`RippleButton` and everything rooted in it, the state layers, and the button groups.
Highest-leverage row in the tranche: 295 direct callers, and fourteen more library widgets
are rooted in it — including four that other families own (`ConfigSwitch`, `ToolbarButton`,
`NavigationRailExpandButton`, `NotificationActionButton`) — so its defaults propagate
twice. This is why it runs first.

Owes: findings 1 and 2, at the root — the focus layer via `Button.visualFocus`, and
pressed separated from hover. `StateLayer`/`StateOverlay` are already correct and become
the mechanism the rest of the family uses instead of colour ternaries. Groups
(`ButtonGroup`, `VerticalButtonGroup`, `FlowButtonGroup`, `SelectionGroupButton`) get §5.6:
the card owns the row's geometry, hover fills it edge to edge and matches its corners.
`LightDarkPreferenceButton` carries 7 design-check hits, `MenuButton` 2.

Dies: nothing outright, but `colBackgroundActive: colBackgroundHover` and any per-caller
state colour that the tokens already cover.

### 2. `cw-primitives` — 18 files, 1,017 lines · lane 1

Text, symbols, images, shapes, and the three one-line rectangles. `StyledText` 471 callers,
`MaterialSymbol` 398 — the two most-instantiated types in the shell.

Owes: finding 3 in `StyledText` — `duration: 300 / 2` and seven hand-fitted sine curves
become `Appearance.animation.*`. Every label that can outgrow its cell elides (§10.17).
`MaterialShape` and its wrapper sit on the submodule and are only re-tokenised, not
reshaped. `CliphistImage` and `FileSearchImage` carry 2 hits each.

Dies: `Circle` and `Pill` if they turn out to be `StyledRectangle` with a radius — check
callers before deleting either.

### 3. `cw-scaffolding` — 14 files, 1,044 lines · lane 1

Page, section and scroll containers. `ContentSection` 177 callers, `ContentPage` 175,
`ContentSubsection` 63 — the skeleton of every settings page and most panels.

Owes: finding 3's highest-volume instance, `ContentSection`'s `200`/`OutCubic` disclosure
arrow, and the same in `ContentSubsection`. `StyledListView`/`StyledFlickable` keep the
Android overscroll stretch and get it verified, not assumed. `PagePlaceholder` (71 callers)
is the empty state the whole audit is told to use, so it is designed properly here once.
`ScrollEdgeFade` where content runs under a header.

Dies: any section that paints its own separator — §5.5, whitespace on the 4dp ladder and a
`colLayer1`/`colLayer2` card instead.

### 4. `cw-config-rows` — 12 files, 1,517 lines · lane 1

The `Config*` row family plus the monitor picker. `ConfigSwitch` 129 callers,
`ConfigSelectionArray` 70, `ConfigSpinBox` 56, `ConfigSlider` 47. Almost all of
`modules/settings` is these six types in a column.

Owes: §5.7 — in a settings row the label sits *above* a full-width track, never beside it.
§5.6 — the card owns the row geometry; a row must not paint a background at a different
radius or width from the card behind it (§10.13). The focus state matters most here of
anywhere, because this family is the keyboard-navigable part of the shell.
`ConfigListViewEntry` is the largest file in the family at 392 lines.

Dies: any row-level divider; per-row backgrounds that fight their container.

### 5. `cw-inputs` — 16 files, 1,648 lines · lane 1

Sliders, combo boxes, switches, radio buttons, text fields, the address bar.

Owes: §9's switch/slider recipe — thumb on fast spatial, track colour on default effects,
M3 Expressive thumb squeeze on press, value text tabular (`font.family.numbers`).
`StyledComboBox`/`StyledComboBoxSearch` are popups and take §9's popup motion: open
0.5 → 1.02 → 1 with the origin on the field, close on `emphasizedAccel`, Escape dismisses.
`StyledSwitch` has 3 hand-fitted easings, the combo boxes 2 each. Text fields need the
focus state to be visible, not an `activeFocus` boolean nothing renders (§3.7).

Dies: hand-rolled popup motion in the combo boxes if `ArrowPopup`'s transcription covers
it.

### 6. `cw-navigation` — 13 files, 830 lines · lane 1

Tab bars, tab buttons, the navigation rail, the toolbar row.

Owes: §9's tab recipe — indicator on `elementMoveSmall`, label crossfade on
`elementMoveFast`. `SecondaryTabButton` has 2 hand-fitted easings and 1 design hit;
`SecondaryTabBar`, `ToolbarTabBar`, `NavigationRail`, `NavigationRailButton` and
`NavigationRailTabArray` one hit each — this family is where the untokenised motion is
densest per line. Rail expand/collapse is spatial with both directions specified.

Dies: nothing; this family is tokenisation and states.

### 7. `cw-dialogs` — 14 files, 929 lines · lane 1

`WindowDialog` and its parts, the tooltips, `NoticeBox`, `ShortcutBox`.

Owes: §9's dialog recipe — scrim, elevation 5, radius `verylarge`, enter `emphasizedDecel`,
exit `emphasizedAccel` at half. Tooltips: `colTooltip`, ~500ms delay, fade only, no scale.
Confirming action right, destructive in `colError`. `NoticeBox` has 38 callers and is the
shell's error surface, so its edge states are the ones worth getting right.

Dies: **`WindowDialogSeparator`**. §5.5 forbids it and it has **zero callers** — it exists
only to be deleted, and DESIGN.md §9 still lists it as a dialog part, so that line goes
too. `WindowDialogSectionHeader` and `WindowDialogParagraph` take the whitespace-and-card
treatment in its place.

### 8. `cw-progress` — 13 files, 1,060 lines · lane 1

Progress bars, circular progress, the loading indicator, the cookies and visualizers.

Owes: finding 3's worst case — `CircularProgress` and `ClippedFilledCircularProgress`
export `animationDuration` and `easingType`, which become defaults from
`Appearance.animation.*` and stop being knobs. `MaterialLoadingIndicator` (the morphing M3
Expressive one) has 3 hits and 3 hand-fitted easings. §9: indeterminate only where the
duration is genuinely unknown — anywhere it is known, this family should offer the
determinate form so callers stop reaching for the spinner.

Dies: the duration/easing knobs. Any visualizer that runs an effect per frame gets checked
against §8's budget.

### 9. `cw-notifications` — 6 files, 612 lines · lane 1

`NotificationItem`, `NotificationGroup` and their parts.

Owes: §9's notification recipe — `SwipeDismissible` for dismissal (70px threshold,
neighbours at 0.3 and 0.1), group expansion on default spatial with both directions.
`NotificationGroup` is rooted in a bare `MouseArea`, which is the §3.2 shape the pack flags
as a rebuilt `RippleButton`; decide deliberately whether the whole group is clickable or
only its rows, and do not nest a second ripple inside a rippled parent. One-item and
empty are the edge states that matter.

Dies: nothing structural; the group header may lose chrome to §5.5.

### 10. `cw-effects` — 8 files, 234 lines · lane 1

Shadows, blur, colorize, mask, the two wallpaper shaders. Small but load-bearing:
`StyledRectangularShadow` 71 callers, `StyledDropShadow` 51.

Owes: §8's effect budget — one layer/effect per widget, never inside a repeated delegate
(§10.11). This family is where that rule is either enforced or lost, since these are the
widgets a delegate would nest. `StyledDropShadow` carries a design hit.

Dies: whichever of the two shadow wrappers the other can express — 122 combined callers
means check both before merging, and merging is optional.

### 11. `cw-media` — 8 files, 1,007 lines · lane 2

Player controls and the lyric stack.

Owes: `PlayerControlsLyrics` has 7 design hits and `PlayerControls` 4 — the densest pair in
the tranche. `MaterialMusicControls` is the M3 Expressive reference for the transport row.
`LyricScroller`/`Lyrics` animate without touching `Appearance.animation`. Edge states are
real here: no player, no lyrics, one line.

Dies: `LyricsStatic` if `Lyrics` with scrolling disabled covers it.

### 12. `cw-motion` — 15 files, 858 lines · lane 2

`transitions/`, `animations/`, `TransitionImage`, `Carousel`, `ErrorShakeAnimation`.

Owes: this family *is* the enter/exit rule, so it is the one place a caller-supplied
duration is legitimate — `TriggerAnimation`, `DelayedPropertyAnimation` and the wipes are
parameterised on purpose. The work is that their **defaults** come from
`Appearance.animation.*` so an unparameterised caller is already correct.
`ErrorShakeAnimation` has 5 design hits and `PlaceholderOpeningAnimation` 2; `Carousel` has
3 and 3 hand-fitted easings. §2.7: reset on hide, and stagger capped at ~6, never inside a
scrolling delegate.

Dies: any transition whose curve is a hand fit of one already in `animationCurves`.

### 13. `cw-gestures` — 6 files, 446 lines · lane 2

`DragManager`, `SwipeDismissible`, `ResizeHandler`, the widget canvas.

Owes: §3.6 — the dragged item lifts (elevation), it does not fade, and it takes the 0.16
drag layer. `SwipeDismissible` reads `owner.parent.parent` for `dragIndex`/`dragDistance`/
`resetDrag`, which is why `ii-clipboardToast` could not use it for a lone card; either that
coupling is loosened so a non-`ListView` owner works, or it is documented as
list-only — see `.audit/ii-clipboardToast/notes.md`.

Dies: nothing; this family is behaviour, and its risk is regression, not sloppiness.

### 14. `cw-misc` — 4 files, 463 lines · lane 2

`CalendarView`, `WeekRow`, `AttachedFileIndicator`, `AndroidClock`. Grouped because they
are leaves with few callers, not because they are alike.

Owes: tokenisation — all four animate without touching `Appearance.animation`. `WeekRow`
carries a design hit. `CalendarView` is a grid of hit targets, so §3.4's 32px minimum is
the thing to measure.

Dies: nothing.

### 15. `cw-battery` — 1 file, 1,040 lines · lane 2

`CustomBatteryMeter`, the largest file in the library and the most design-check hits of
any (10): literal durations, hex literals, off-grid margins, 4 hand-fitted easings.

Owes: tokenisation, end to end. It is one file with one job, which is why it is last and
lane 2 — the brief leaves almost no choices, and the diff is mechanical. Charging,
low-battery and unknown-percentage are its edge states.

Dies: the hex literals; the hand-fitted curves.

---

## What this tranche does not do

It does not redesign callers. It does not touch `modules/settings/widgets/` — the next
tranche. It does not add widgets: if a family finds a gap, it records it in `notes.md` for
the surface that needs it, because a widget with no caller is the thing this library has
too much of already.
