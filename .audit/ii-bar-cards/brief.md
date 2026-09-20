# ii-bar-cards — brief

Read `.audit/ii-bar/brief.md` first. It carries the contracts, the motion table
and the fences. This page is only what is specific to this row.

**Your files** (14, and nothing else):

```
dots/.config/quickshell/ii/modules/ii/bar/cards/*.qml
```

**Purpose.** The shared kit every bar popup is composed from. It has no surface
of its own; its job is to make whatever composes it legible without that caller
inventing anything.

**Primary action.** None of its own. Each card makes its *caller's* primary
thing the loudest element on the card.

**Hierarchy, per card.**

- `HeroCard` — the one big thing at the top of a popup. Shape+icon left, giant
  title right, subtitle under it, optional pill top-right. The title is the
  whole point; the shape is decoration and must never out-weigh it. The size
  ramp (`hugeass * 2.5`, `Font.Black`) is the hierarchy and stays — its
  *motion* is what is wrong.
- `SectionCard` — header row (shape, title, optional right-hand extra), then
  content. The title ranks above the content; the shape is a marker, not an
  actor.
- `InfoPill` — a full-radius row, shape at the left, optional action shape at
  the right, one line of text centred. The text is primary; the right shape is
  an action and must read as one.
- `MetricCard` / `MetricsGrid` — value first, label second, accent third.
- `AlarmsCard` — the only card with real editing in it (805 lines, two
  `ListView`s, three `MaterialTextField`s, a `StyledSwitch`). The list of
  alarms is primary; add/edit/delete are secondary and live in the header and
  in per-row affordances, not as a permanent button wall.
- `WorldClocksCard`, `ClockHeaderCard`, `HourlyForecast`, `InDayForecast`,
  `LocalSend*` — content blocks inside a `SectionCard`, third-rank.
- `LoadingPlaceholder` — the kit's empty/loading state. Anything in the kit
  that can be empty uses it rather than collapsing to nothing.

**Interaction.** Contract 2 in full. Specifically: `InfoPill`'s two circles and
the three raw `MouseArea`s get four states, a ≥32px hit area and a pointing-hand
cursor; `Qt.lighter(c, 1.15)` and `scale: 1.08` are both invented and go.
`AlarmsCard`'s two `ListView`s should be `StyledListView` (§9 *List*) unless
that costs a behaviour they need — say which in your report if you keep them.

**Edge states.** Loading and empty are `LoadingPlaceholder` (`loading`,
`loadingText`, `emptyText`). One item: a card holding one row must not look
broken or collapse to chrome. Error: the forecast cards have no error state at
all — a fetch that fails currently reads as "loading forever". Give the kit one
honest error line, styled `colOnSurfaceVariant`, not `colError` shouting.

**Cost.** `WorldClocksCard.qml:104` — `layer.enabled` + `OpacityMask` inside a
repeated delegate. That is the cluster's only true law-8 violation and it goes.
`ClockHeaderCard` has a `layer.enabled` and two `OpacityMask`s in one file: keep
at most one effect for that widget.

**Delete.** `SectionCard.showDivider` and its 2px rectangle — and, because you
may not edit the callers, leave the property *removed* and list the five
`showDivider:` lines that now need deleting in your report
(`HourlyForecast`, `InDayForecast`, `LocalSendSendCard`, `LocalSendTransferCard`
are yours to fix; `PrivacyIndicator` belongs to `ii-bar-tray`). Every
`PauseAnimation` ladder. `HeroCard`'s `duration: 1120`.

**Out of scope.** The popups that compose these cards. `startAnim`,
`*AnimDelay`, `compactMode`, `adaptiveWidth` and every other declared property
in `pack.md` keep their names.
