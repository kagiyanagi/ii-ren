# ii-sidebarDashboard-notifications — brief

**Purpose.** Catch up on what arrived while the popups were suppressed (the dashboard
being open times every popup out), then clear it.

**Primary action.** Reading the list. Clearing it is second, and is a labelled "Clear all"
pill at the foot, which is where the Android shade keeps it.

**Hierarchy.** The notification cards first, then "Clear all", then the count, in
`colSubtext`, then the silent toggle.

**Reference.** The Android 16 notification shade (SystemUI's `NotificationStackScrollLayout`).
The footer has a "Clear all" pill and no count. This panel keeps a count because there's no status bar
icon row to carry it.

**Interaction.**
- *Cards.* Unchanged from before the audit, by the owner's choice: each group is its own
  `rounding.large` card, 8 apart, under a `rounding.normal` clip at a 5 inset. An Android-shade
  stack (small joins, 4 apart) was built, then reverted on review. See `notes.md`.
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
- *Empty:* `PagePlaceholder` "No notifications" (was "Nothing"). The count fades out and
  "Clear all" dims to disabled. The silent toggle stays, because silencing an empty shade still means something.
- *One item:* one card. "1 notification".
- *Many:* the list scrolls under the rounded clip, and the footer stays put.

**Cost.** One `OpacityMask` layer over the list, as before, not repeated. The cards' shadow is
still drag-only in the sidebar.

**Delete.** The `ButtonGroup` and its three `GroupButtonWithIcon`s. The unused imports.

**Out of scope.** The dashboard's layout, meaning how tall this card gets. That belongs to
`ii-sidebarDashboard-root`. The popup. A "History" button: history is in Settings → Interface,
and a shortcut here is a feature, not an audit fix. The other two `TextMetrics.width` caps,
in `WTextWithFixedWidth` and the bar's `Resource`.
