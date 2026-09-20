# ii-bar-chrome — brief

Read `.audit/ii-bar/brief.md` first. This row is one fifth of what the queue
called `ii-bar-root`; it was split because 9,535 lines in one session is the
failure `AUDIT.md` was written to prevent.

**Your files** (6, and nothing else):

```
dots/.config/quickshell/ii/modules/ii/bar/Bar.qml
dots/.config/quickshell/ii/modules/ii/bar/BarContent.qml
dots/.config/quickshell/ii/modules/ii/bar/BarComponent.qml
dots/.config/quickshell/ii/modules/ii/bar/BarGroup.qml
dots/.config/quickshell/ii/modules/ii/bar/ScrollHint.qml
dots/.config/quickshell/ii/modules/ii/bar/Spacebar.qml
```

**Purpose.** The strip itself: the window, its background, its corners, its
auto-hide, and the three layout lists that everything else lands in.

**Primary action.** None. This row succeeds by being unnoticeable — a frame that
never competes with the widgets in it or the windows under it.

**Hierarchy.** Left list, centre list, right list, with the centre reserved for
the clock and its neighbour. `BarComponent` is the per-item wrapper
(highlight, isolation, group style, spacer) and decides how much of the strip
an item can claim; `BarGroup` is the rounded container behind a run of items.
A group's fill is `colLayer0`-family and must stay quieter than any widget it
holds.

**Interaction.**

- **Auto-hide is the motion that matters here.** `Bar.superShow` / `mustShow` /
  `toggle` / `open` / `close` reveal and hide the whole strip. That is a
  screen-edge panel: enter on default spatial from its own edge, exit
  accelerating on fast effects at about half (§2.5, §2.6). Both directions must
  be spelled out — a strip that slides in and vanishes is the cluster's most
  common motion bug.
- `BarComponent.toggleVisible` / `toggleHighlight` change an item's width and
  fill. Width on `elementResize`, fill on `elementMoveFast`.
- `ScrollHint` is a `Revealer` — check its enter/exit pair and its tooltip
  (§9 *Tooltip*: fade only, no scale).
- `Spacebar` stays `empty` by default (`DECISIONS.md` 10). Do not revive a
  separator, and do not delete the styles someone may have configured.

**Edge states.** No widgets in a list at all (an empty side must not leave a
floating group background); one widget; a vertical bar
(`Config.options.bar.vertical` — the same files serve it through
`verticalBar/`); `cornerStyle` 0/1/2 and `barBackgroundStyle`, each of which
changes what the background is.

**Cost.** `BarContent.qml:65`'s `StyledRectangularShadow` is the float-style
elevation and stays (§6.2). Nothing else in this row may add an effect.

**Delete.** `BarGroup.qml:8`'s `padding: 5` is off the 4dp grid. Any property
in `pack.md` that nothing reads.

**Out of scope.** Every widget the lists contain — they belong to
`ii-bar-widgets`, `ii-bar-tray` and `ii-bar-weather`. `modules/ii/verticalBar/**`
reads `BarComponent` and `BarContent` by name and passes properties to them:
freeze those names.
