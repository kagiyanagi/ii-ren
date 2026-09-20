# cw-navigation — notes

## What the brief's headline number turned out to be

"The densest untokenised motion per line in the library" reads as a tokenisation
row, and the mechanical part of it was four `check-design.py` hits in 830 lines. The
real debt was two things a regex structurally cannot reach:

- **`idx1Duration: 50` / `idx2Duration: 200`.** Both tab bars drive their indicator
  through `modules/common/models/AnimatedTabIndexPair`, whose durations arrive under
  property names ending in `Duration`. `check-design.py`'s rule is `\bduration:`, and
  `idx1Duration:` does not match it — case-sensitively the `D` is wrong and the word
  boundary is missing. That is the **exported-knob** shape the tranche notes flagged
  as blind spot 2, and it is the third instance (`CircularProgress`, `StyledText`,
  this), so the tightening they described is now warranted.
- **A missing state has no line.** Neither `TabButton`-rooted widget nor
  `ToolbarTextField` rendered focus, and `SecondaryTabButton` had no press state at
  all outside its ripple. `check-button-states.py` walks QQC2 **`Button`** roots, so
  all three sit outside its net by construction.

## Measured, not assumed

Four things were settled with the plain `qml` runtime (`/usr/lib/qt6/bin/qml
-platform offscreen`, answer encoded in the exit code) rather than reasoned about.
None of them needs Quickshell, so none of them needed the shell:

| question | answer |
|---|---|
| `TabButton`'s default `focusPolicy` | already `Qt.StrongFocus` — the explicit line I first wrote was dead, and is gone |
| `visualFocus` after `forceActiveFocus(Qt.TabFocusReason)` on a `TabButton` | **true**, with or without that line, so the film is reachable and not inert |
| `TabButton.activeFocusOnTab` | **true** by default — the rail and the secondary tabs are in the keyboard tab chain already |
| `Transition { to: "expanded" }` vs `to: ""` | each fires exactly once, in the right direction, on a state driven by a `when:` |
| `Rectangle.topLeftRadius` with only `radius` set | follows `radius` (17 → 17), so `StateOverlay { radius: parent.radius }` reaches `StateLayer`'s corners without spelling four out |

**Inline components DO see the enclosing file's root id** in Qt 6.11, contrary to the
Qt docs' inline-component scope note — measured, `component Probe: QtObject {
property int viaUnqualified: outerNum }` resolves. That matters beyond this row:
`RippleButton`'s `component RippleAnim: NumberAnimation { duration: rippleDuration }`
depends on it and so does `SecondaryTabButton`'s copy. `RailEnter`/`RailExit` still
take their `enabled:` at the instantiation site rather than inside the component —
not because it fails, but because that is where `root._isInitialized` belongs anyway.

## The one place 2.5 could not be honoured, and why

`NavigationRailTabArray`'s pill is the **selection indicator**, so DESIGN.md 9 puts
it on `elementMoveSmall`. Its size also changes when the rail expands, where 2.5
wants an asymmetric pair. One `Behavior` cannot tell which cause moved it, and the
rail's own container (`settings.qml`, 200ms on `elementMoveFast`) sets the pace
everything else has to keep up with. Tearing the pill's height away from its own
travel is the worse of the two errors, so all three legs are symmetric on
`elementMoveSmall` and the asymmetry lives in the two widgets that only ever move
because of expand: `NavigationRailButton` (500 out / 130 back) and
`NavigationRailExpandButton`'s chevron (same pair).

`implicitHeight` had **no** animation at all before this and simply jumped 32 → 56.

## `PropertyChanges` that was never going to animate

`NavigationRailButton`'s expanded state carried `PropertyChanges { target:
itemBackground; implicitWidth: root.visualWidth }` — the same binding the base state
already has. The width actually changes because `visualWidth` re-evaluates off
`root.expanded`, which is a race with the state machine capturing the pre-change
value, so the `PropertyAnimation` beside it was dead more often than not. qmllint
said so twice (`Quick.property-changes-parsed`) and both warnings are gone with it.

The width now rides a plain `Behavior` whose spec comes from inside `visualWidth`'s
own binding — 2.9's shape, `Revealer` is the worked example, and
`check-navigation-widgets.py` fails if anyone puts the ternary back in the Behavior.

## Also fixed here, found while reading

- **`ToolbarPairedFab` anchored its own root** (`anchors.verticalCenter:
  parent.verticalCenter`). Two of its four callers (`NotesWidget`, `TodoWidget`) put
  it in a `RowLayout` with `Layout.alignment: Qt.AlignVCenter`, which Qt calls
  undefined behaviour — the same class `check-scaffold-containers.py` guards for its
  own family. `RegionSelection` sets the anchor itself inside a plain `Row`, so
  nothing regresses; the `RowLayout` callers now get the alignment they asked for.
- **`ToolbarPairedFab`'s shadow anchored across a Loader boundary.** `target:
  fabWidget` is a sibling of the Loader, therefore neither parent nor sibling of the
  item the Loader builds, so Qt refused the anchor out loud. `anchors.fill: undefined`
  and let the Loader size it, exactly as `Toolbar` already does.
- **`ToolbarPairedFab.clicked(event)` always forwarded `undefined`.**
  `AbstractButton.clicked` takes no arguments; qmllint flagged the handler. No caller
  read it, so the parameter is gone rather than made to work.
- **The selected label was the wrong colour in two places.**
  `NavigationRailButton`'s icon went to `m3onSecondaryContainer` when toggled while
  its label stayed `colOnLayer1` on top of the pill; `ToolbarTabButton` gave neither
  its icon nor its label a selected colour at all, so the only selection cue was the
  indicator behind them. Both now take `colOnSecondaryContainer` through one
  `colContent`, crossfading on `elementMoveFast` — which is what DESIGN.md 9's
  "label crossfades" means here, and it is also the film colour.
- **`colStateLayer` was the wrong hue on three widgets.** `RippleButton` defaults it
  to `colOnPrimary`/`colOnLayer1`; `IconToolbarButton` fills with
  `colSecondaryContainer`, `ToolbarPairedFab` with `colTertiaryContainer` and
  `ToolbarTabButton` sits on the bar's secondary-container pill. A focus film in the
  wrong hue is the fourth state rendered wrong, which is not much better than absent.
- **`ToolbarTabButton.buttonRadius: height / 2`** ignored sharp mode, where every
  sibling collapses. `Appearance.rounding.full` clamps to the same pill and zeroes
  with the rest (4.1).
- **`Toolbar` painted `m3colors.m3surfaceContainer`** — the generated palette, not
  the semantic layer, so it did not follow content transparency. `colSurfaceContainer`
  is `solveOverlayColor`'d and is byte-identical with transparency off (verified:
  `overlayOpacity = 1` makes `invA = 0` and the function returns the target).
- **`Toolbar`'s width animated on `elementMoveFast`**, an effects spec on a size.
  `elementResize` is the spec table's answer for implicit size changes.
- **`SecondaryTabButton.down` was never true.** Its `MouseArea` swallows the press,
  so `AbstractButton` never sets its own `down` -- which is why the press film needs
  `root.down = true/false` driven by hand, the way `RippleButton` already does it.
  Caught by writing the film first and then asking what set the flag; measured that
  `down` is writable on a `TabButton` and starts false under a swallowing MouseArea.
  `NavigationRailButton` is fine here: `PointingHandInteraction` rejects the press
  (`mouse.accepted = false`) so the Control still sees it.
- **`SecondaryTabButton` stacked a `PointingHandInteraction` under its own
  `MouseArea`**, which already sets the same cursor and sits on top of it. Deleted.
- **`SecondaryTabBar.baseWidth` divided by `root.count`** with no guard — an empty
  tab bar produced `Infinity` and an indicator at `NaN`.
- **`tabContentWidth` was dead** and is now what makes the tab label elide. It
  computed the right number and nothing read it, so a long translated tab name drew
  straight out past the pill (10.17). The row is capped to it and the label fills.

## What was deliberately *not* done

- **`SecondaryTabButton` is not rebuilt on `RippleButton`.** It duplicates ~60 lines
  of the ripple, and the brief for this family says "Dies: nothing". `TabBar` drives
  `checked` through its own `ButtonGroup` over `AbstractButton`, so a rebuild would
  work — but it is five call sites of behaviour change for a code-shape win, with no
  design defect left once the states are right. If anyone takes it on, the ripple is
  a straight copy and the only real work is `checked` → `toggled`.
- **`ToolbarTabButton` and `IconToolbarButton` keep their hand-mixed hover tints.**
  Both set `colBackgroundHover: transparentize(colOnSurface, 0.95)` — a 0.05 film
  where the token is 0.08 — and the fix belongs at `RippleButton`, which renders
  hover as a background colour and only focus/press as a film. See below.
- **Tab height 42 and `horizontalPadding: 10` are untouched.** M3's secondary tab is
  48dp and its text buttons pad 16, but both are visible layout changes across five
  and three surfaces with no measurement available here. Same reasoning
  `cw-buttons` used for `GroupButton.clickedWidth`.
- **`SecondaryTabBar`'s 1px bottom border stays.** 5.5 forbids separators "between
  section headers and controls or around content groups"; this is the track the
  active indicator rides, part of M3's own tab anatomy, and `colOutlineVariant` is
  the token 6.1 names for it. It is not a section divider.
- **`showLabel` still pops.** `ToolbarTabBar` hides non-current labels when there are
  more tabs than `maxTextTabs`. Crossfading it means either the tab width snapping at
  the *end* of the fade instead of the start, or animating a `Row` child's width —
  and 9's "label crossfades" is the selected/unselected colour change, which is now
  there. Left as a pop.
- **`?? 56` / `?? 130` fallbacks in `NavigationRailTabArray`** are wrong (the
  highlight fallback should be 32, not 56) but only reachable before `children[0]`
  exists. Not worth the churn; noted in case a rail ever renders one frame too tall.

## Needs a change outside this family

Two, both one-liners, neither mine to make:

**1. `dots/.config/quickshell/ii/modules/common/models/AnimatedTabIndexPair.qml`** —
the shared indicator model hand-fits `Easing.OutSine` on both edges and defaults to
100/300. Its four call sites are `SecondaryTabBar`, `ToolbarTabBar` (both now pass
tokenised durations explicitly) and `modules/ii/bar/Workspaces.qml`, which is a
different row. `modules/common/models/` belongs to no family in this tranche. The
edit, once someone owns `Workspaces.qml`:

```qml
    property int idx1Duration: Appearance.animation.elementMoveSmall.duration
    property int idx2Duration: Appearance.animation.elementMove.duration

    Behavior on idx1 {
        NumberAnimation {
            duration: root.idx1Duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }
    Behavior on idx2 {
        NumberAnimation {
            duration: root.idx2Duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
    }
```
(plus `import qs.modules.common`). Until then the two tab bars ride token durations
on a hand-fitted sine, which is half the fix.

**2. `dots/.config/quickshell/ii/settings.qml:355`** — `spacing: 5` on the
`NavigationRail`, overriding the widget default that this row put on the 4dp grid.
Delete the line; the widget's own `spacing: 4` is then what applies.

Not a change, but worth recording for whoever owns `RippleButton` next: its
`StateOverlay` drives `focused` and `press` but not `hover`, so every caller that
wants a film for hover instead of a background colour has to hand-mix one. 36 files
set a pressed colour explicitly and 261 set a hover colour, so this is a rule-9
decision, not a cleanup.

## Still needs a running shell

- Whether **Tab actually walks into the rail and the secondary tabs** in the live
  settings app. `activeFocusOnTab` is true and `visualFocus` renders on a tab-reason
  focus — both measured — but the chain through `StyledFlickable` → `NavigationRail`
  → `NavigationRailTabArray` was not driven.
- The **rail expand at 500/130** against `settings.qml`'s own 200ms wrapper width.
  The wrapper is not this row's file; if the labels visibly trail the rail's edge,
  that wrapper Behavior is the thing to move, not these specs.
- The **indicator at 350/500** where it used to be 50/200 in `ToolbarTabBar`. Both
  numbers are now tokens and DESIGN.md 9 names `elementMoveSmall` outright, but a
  tab switch is the most-repeated motion in the cheatsheet and the region selector,
  so it is the first thing to look at on the smoke pass.

## The check this left behind

`tools/check-navigation-widgets.py` — three concerns, all invisible when broken:

1. The two `TabButton` roots and `ToolbarTextField` bind a focus film inside a
   `StateOverlay`; `SecondaryTabButton` binds hover and press there too, since it has
   no `RippleButton` under it. Fails if a **third** `TabButton`-rooted widget appears,
   because that one would silently ship three states as well.
2. `NavigationRailButton` names one transition toward `"expanded"` and one away from
   it, on **different** specs, and the two animations that have no state to read their
   direction from (`railSpec`, `turnSpec`) assign it from inside the driving binding
   rather than with a ternary in the `Behavior` — 2.9's trap.
3. Both tab bars' `idxNDuration` values come from `Appearance.animation.*`.

Mutation-tested: 12 mutations, 12 caught, plus the third-root guard.
