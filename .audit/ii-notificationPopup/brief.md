# ii-notificationPopup — brief

**Purpose.** Put a notification in front of the user the moment it arrives, in the
top-right corner, without taking anything away from what they are doing — and take it
away again when it has had its time.

**Primary action.** Dismissing or acting on the newest notification. The card kit
(`cw-notifications`, done) owns every control; **this surface owns only where the stack
sits, how long the surface stays on screen, and what it publishes to its neighbours.**
Everything here is placement and lifetime.

**Hierarchy.** Newest card at the top of the stack, hard against the right gutter, below
whatever the bar reserves. Nothing else is on this surface.

**Reference.** Android 16's heads-up notification stack: a floating, elevated column in
the corner that yields to any panel opening in the same corner, and never takes focus.

**Interaction.**
- Per-card enter and exit are `NotificationListView`'s `add`/`remove` transitions and are
  already right. This surface's job is **not to cut the exit off**: the window must stay
  mapped until the last card has finished leaving (2.5).
- The sidebar dodge is a toggle-driven slide that has to reverse mid-flight, so
  `elementMove`, not `elementMoveEnter` (2.7). Same call `ii-clipboardToast` made.
- No keyboard. `WlrKeyboardFocus.None`, stated rather than defaulted.

**Edge states.**
- *Empty* — unmapped, but only after the last exit has played. No `PagePlaceholder`:
  the window hiding itself is the empty state (`cw-notifications` notes).
- *One item* — the common case, and therefore the case the exit bug ruined every time.
- *Pinned monitor disconnected* — falls back to the focused monitor, not to `null`,
  which hands the choice to the compositor.
- *Stack taller than the screen* — the list scrolls; the published height is clamped to
  what fits so a long stack cannot push its neighbours off the display.

**Cost.** No effects, no timers under 100ms. It stays that way: the one timer added is
the exit grace, which runs once per emptied stack for the length of `elementMoveExit`.

**Delete.** The two literal margins (a 4 where every sibling in this corner uses
`hyprlandGapsOut`), the enter spec on a reversible slide, and the 180-column `screen`
ternary that reads its config twice.

**Out of scope.** The card kit, the sidebar's `NotificationList`, and
`waffle-notificationPopup` — its own queue row.
