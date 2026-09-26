# ii-sidebarPolicies-root — brief

**Purpose.** The frame of the left sidebar: the floating sheet, the tab toolbar, the page
card the tabs share, and the page chrome of the two tabs whose host files live at the top
level (Hermes's status pill, list and composer, and Anime's list and tag composer). Also
the small widgets those two share (`ScrollToBottomButton`, `ApiInputBoxIndicator`,
`DescriptionBox`, `StatusItem`, `ApiCommandButton`).

**Primary action.** None of its own. The frame shows a tab, and every tab row
(`-anime`, `-continuity`, `-translator`, the three `-hermes-*` rows) was redesigned inside
it. So this is a repair, as `ii-sidebarDashboard-root` was: the layout already reads as
an Android 16 sheet with a floating tab toolbar over one content card.

**Hierarchy.** Unchanged: the tab toolbar, then the page card. On Hermes: the transcript,
then the composer, with the status pill as quiet chrome. On Anime: the grid, then the tag
composer.

**Reference.** The Android 16 Gemini/Messages sheet. A floating toolbar picks the page, one
tonal card holds it, and a pill jump-to-bottom chip rises out of the bottom edge of the list.

**Interaction.**
- *The sheet* slides from its edge on Hyprland's layer springs. The QML keeps no motion of
  its own, the same as the right sidebar. *Pin* springs height and y on `elementResize` but
  snapped its radius from concentric to 0 on the first frame. The radius is shape, so it
  moves on the same spec now.
- *Scroll to bottom* is a `rounding.full` pill (it was `verysmall`) that grows out of the
  bottom edge it is anchored to (`Item.Bottom`). It enters on `elementMoveEnter` for scale
  and `elementMoveFast` for opacity, and leaves on `elementMoveExit` for both. It used to run
  both directions on one spec each (2.5).
- *The model readout* (`ApiInputBoxIndicator` with a `clickAction`, one caller: Hermes's
  composer) opens `/model`, but it showed no hover or press. It gets a `StateOverlay` with
  hover and press films (law 6). The read-only form is unchanged.
- *Anime's send button* was a `RippleButton` with a `MouseArea` over it. That area took the
  press, so the button never showed its ripple or its pressed state. It uses `releaseAction`.
- *Anime's NSFW row* flipped `nsfwSwitch.checked` from JS, which broke its binding. The
  switch also toggled itself on click, which broke it a second way. After one click,
  choosing zerochan left the switch reading "on". The row owns the state now
  (`checkable: false`, the `HotspotDialog` recipe) and writes `Persistent` directly. On
  zerochan the row dims to `opacity 0.4` instead of recolouring its label, and it does not
  take the click.
- *Anime's type-anywhere* stole focus on every key, including a modifier's own key-down.
  It takes Hermes's guard (`modifierKeys`), so Ctrl+C still copies.

**Edge states.**
- *Closet anime (`policies.weeb: 2`)*: the anime page exists with no tab. It sat in the
  middle of the page list, so with Continuity or any extension enabled every tab after it
  opened the page before it: the Continuity tab showed the anime grid. The closet page now
  goes last, after the extensions, and is reached by swiping past the last tab.
- *No tabs at all*: the placeholder shows when the tab list is empty. That condition was a
  two-branch expression equal to exactly this. It is a `PagePlaceholder` now, not a bare
  line of grey text.
- *Hermes, empty*: the placeholder's description is centred under its centred title (it was
  left-aligned) and drops the Enter / Shift+Enter / Ctrl+Enter line, which the send button's
  tooltip already carries.
- *Detached window*: its visibility handler registered `panelWindow`, an id that lives in the
  other window's component, so every show and hide threw a ReferenceError. A floating window
  has no outside click to dismiss on, so the handler goes.

**Cost.** One `OpacityMask` stays on the `SwipeView`, and it is load-bearing. A message card
cut by the transcript's clip squares off at the 4px inset, which sits 1.4px outside a 17px
arc. But it masked at `rounding.small` inside a card rounded `rounding.normal`, so it
clipped to the wrong arc. It now masks at the card's own radius. The sheet's
`StyledRectangularShadow` and the status pill's shadow stay. Nothing is added: the one
`StateOverlay` is a `Rectangle` with loaders, not a layer.

**Delete.** `StatusSeparator.qml` and its two dots in the status pill, and Anime's `•`
between the provider and the NSFW row (5.5). The pill's gap goes to 12. The detached
window's dismissable handler. Anime's send `MouseArea`. The placeholder's compound
condition. Off-grid 5s in Anime's composer, the suggestion row and `DescriptionBox` become
4, the value Hermes's composer already uses. The status pill's padding goes 10 to 12, and its
38 minimum goes to 40.

**Out of scope.**
- `InputIconButton` → `hermes/HermesIconButton.qml` (contract 5). That file is created by
  `ii-sidebarPolicies-hermes-panels`, which has not run yet. Whoever lands second points
  `InputIconButton` at it.
- The history and work sheets' blocks in `Hermes.qml`, which are panels'.
- The sidebar's width rule (`weeb == 1 && wallpapers && translator`). It is a stale proxy for
  "four tabs", but `ToolbarTabBar` already hides the labels past `maxTextTabs`, so nothing
  overflows.
- The `SwipeView` page change. It is Qt's `ListView` highlight move, which takes a duration
  but no curve, so no token fits without replacing the view.
- `sidebarPadding` 10 and the text areas' padding 10, which the right sidebar shares.
- The pin workaround process (cursor dodge), which works.
