# ii-sidebarDashboard-notifications — brief

**Purpose.** Catch up on what arrived while the popups were suppressed (the dashboard
being open times every popup out), then clear it.

**Primary action.** Reading the list. Clearing it is second, and is a labelled "Clear all"
pill at the foot, which is where the Android shade keeps it.

**Hierarchy.** The notification cards first, then "Clear all", then the count, in
`colSubtext`, then the silent toggle.

**Reference.** The Android 16 notification shade (SystemUI's `NotificationStackScrollLayout`).
It is one stack of cards with small corners where cards meet (`notification_corner_radius_small`)
and full corners at the ends. A card that is being swiped rounds off by itself. The footer
has a "Clear all" pill and no count. This panel keeps a count because there's no status bar
icon row to carry it.

**Interaction.**
- *Stack.* When not a popup, the groups sit 4 apart (`ButtonGroup`'s gap, not the popup's 8).
  The first card's top corners and the last card's bottom corners are `rounding.small`, nested
  in the `rounding.normal` card the list sits on at a 4 inset. Every join is
  `rounding.unsharpenmore`. A dragged card takes `rounding.small` on all four corners, on
  `elementMoveSmall` (a shape, so spatial). The popup's cards are unchanged: standalone,
  `rounding.large`, 8 apart.
- *Clip.* The list's rounded clip is `rounding.small`, the same as the stack's outer corners. A
  card scrolled halfway under the edge then has the same corners as a card at rest. It used to
  be `normal`, bigger than the cards and the same as the parent (7).
- *Footer.* A `RowLayout`, not a `ButtonGroup`. The middle of the group was a disabled button
  pretending to be a label, drawn at 0.4 opacity as though it could be pressed but wasn't.
  - Silent: a round 40px `RippleButton` icon toggle (primary when on), with a tooltip. The
    user's quick panel doesn't carry the silent toggle, so this is the only one in reach.
  - Count: `StyledText`, `colSubtext`, singular and plural.
  - "Clear all": a `RippleButtonWithIcon` pill, `rounding.full`, `colLayer2`.
- *App name.* The group header capped the name at `TextMetrics.width`, which is rounded to an
  integer: "kitty" (26.11px) got 26 and showed as "ki…". It's capped at the ceiling of
  `advanceWidth` now. That is a fix to the shared card, so the popup gets it too.

**Edge states.**
- *Empty:* `PagePlaceholder` "No notifications" (was "Nothing"). The count and "Clear all"
  hide, and the silent toggle stays, because silencing an empty shade still means something.
- *One item:* one card, all four corners outer. "1 notification".
- *Many:* the list scrolls under the rounded clip, and the footer stays put.

**Cost.** One `OpacityMask` layer over the list, as before, not repeated. The cards' shadow is
still drag-only in the sidebar.

**Delete.** The `ButtonGroup` and its three `GroupButtonWithIcon`s. The unused imports.

**Out of scope.** The dashboard's layout, meaning how tall this card gets. That belongs to
`ii-sidebarDashboard-root`. The popup. A "History" button: history is in Settings → Interface,
and a shortcut here is a feature, not an audit fix. The other two `TextMetrics.width` caps,
in `WTextWithFixedWidth` and the bar's `Resource`.
