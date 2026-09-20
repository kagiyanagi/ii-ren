# ii-bar-tray — brief

Read `.audit/ii-bar/brief.md` first. One fifth of the old `ii-bar-root` row.

**Your files** (7, and nothing else):

```
SysTray.qml  SysTrayItem.qml  SysTrayMenu.qml  SysTrayMenuEntry.qml
PrivacyIndicator.qml  RecordIndicator.qml  ScreenShareIndicator.qml
```

all under `dots/.config/quickshell/ii/modules/ii/bar/`.

**Purpose.** Two different jobs that happen to sit next to each other: other
applications' icons and menus (the tray), and the three indicators that say
something is using your microphone, camera or screen.

**Primary action.** Tray: open the item's menu. Indicators: be *noticed* — they
are the one place in this cluster where drawing attention is the point.

**Hierarchy.** An active privacy/record/screenshare indicator outranks every
tray icon beside it. A tray icon is fourth-rank chrome. The overflow chevron is
a control, not a status.

**Interaction.**

- `SysTrayMenu` is a menu, so it takes the §9 *Popup / context menu* recipe in
  full — the `arrowPopup*` composite, origin at the corner nearest the icon that
  opened it, radius `verylarge`, elevation 3 — and §3.7 keyboard: Escape closes,
  arrows move, the focused entry shows the 0.10 focus film. Sub-menus grow out
  of their parent entry, not out of the screen.
- `SysTrayMenuEntry` is already a `RippleButton`; check it renders all four
  states and that the icon and "special interaction" columns do not shift the
  label when one entry has an icon and another does not.
- `SysTrayItem` is a bare `MouseArea`: four states, ≥32px hit area,
  pointing-hand cursor, and §3.5's button conventions (left opens the menu,
  middle and right are the item's own activate/secondary — do not invent).
- The three indicators appear and disappear as devices come and go. That is an
  enter/exit pair (§2.5) plus a width change on `elementResize`;
  `PrivacyIndicator.grown` and `setVisible()` already imply the states.
- Indicator colour is `colError`/`colErrorContainer` for recording and
  `colTertiary`-family for passive use — one accent, no pulse, no blink (law 8).

**Edge states.** No tray items at all (the whole group must vanish, not leave an
empty background); more items than fit (`trayOverflowOpen` / the chevron); an
item with no icon; a menu with one entry; a menu taller than the screen; two
indicators active at once.

**Cost.** `SysTrayItem.qml:124`'s `ColorOverlay` runs **once per tray icon**
under `Config.options.tray.monochromeIcons` — `SysTrayItem` is instantiated per
item, so this is an effect inside something that repeats (law 8) even though the
pack's heuristic did not flag it across the file boundary. Replace it with
`IconImage`'s own colouring or drop the monochrome path's effect; say which in
your report. `SysTrayMenu.qml:58`'s shadow is elevation and stays.

**Delete.** `PrivacyIndicator` composes `SectionCard`, which loses
`showDivider` in `ii-bar-cards` this pass — remove the `showDivider:` line here
if it passes one. `SysTray.showSeparator` is already gone (`DECISIONS.md` 10);
do not bring a separator back.

**Out of scope.** `cards/*.qml`, `StyledPopup.qml`, `BarComponent.qml`.
`modules/ii/lock/LockSurface.qml` instantiates `SysTray` — freeze its API.
