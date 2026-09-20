# ii-bar — cluster brief

The brief for seven rows: `ii-bar-cards`, `ii-bar-weather`, and the five the
9,535-line `ii-bar-root` row was split into — `ii-bar-chrome`, `ii-bar-widgets`,
`ii-bar-tray`, `ii-bar-popups`, `ii-bar-resources`. Written once, for all of
them, because the bar and its hover popups are one surface family and eight
briefs written apart do not come out coherent (`AUDIT.md`, *The brief*).

Read this, then your row's `brief.md`, then your row's `pack.md`. Then
`.github/DESIGN.md` §2, §3, §5, §6, §9.

---

## What the bar is

**Purpose.** Ambient status you read without stopping what you are doing, and a
row of handles that open the detail behind each one.

**Primary action.** The bar has no primary *action* — it is a status surface.
Its primary *interaction* is hover → popup. Everything in the bar is therefore
secondary to the windows behind it and must look it: no element in the strip may
draw more attention than the content it sits above.

**Hierarchy.** Left: workspaces — the one thing the bar is *steered* with, and
the only element allowed an accent fill. Centre: the clock, the thing most often
read, and the weather beside it. Right: the system cluster (tray, network,
battery), read only when something changes. Active-window title is third-rank
text, never competing with workspaces beside it.

**Reference.** The Android 16 status bar and its quick-settings detail popups:
a flat, quiet strip whose items expand into elevated `ArrowPopup` surfaces
anchored to the item that opened them.

---

## Contract 1 — the popup shell

Every hover popup in this cluster is a `StyledPopup`. `ii-bar-popups` owns that
file; every other row consumes it and may not edit it.

**Motion is the §9 *Popup / context menu* recipe, not a bespoke one.** It is
already transcribed into `Appearance.animationCurves.arrowPopup*` and already
assembled by `DockFolderPopup` and `DesktopMenu` — read one of those before
writing any of it:

- open: scale `arrowPopupScale` → `arrowPopupOvershoot` over
  `arrowPopupScaleDuration` on `emphasizedDecel`, then settle to 1 on
  `arrowPopupSettle`; alpha 0 → 1 linear over `arrowPopupFadeDuration`
- close: scale → `arrowPopupScale` over `arrowPopupCloseDuration` on
  `emphasizedAccel`; alpha 1 → 0 over `arrowPopupFadeDuration` after
  `arrowPopupFadeHold`
- **origin at the corner nearest the bar item that opened it** (§2.6) — not the
  centre, not a fixed edge. A popup under a right-hand tray icon grows from its
  top-right; one under the clock grows from the top-centre. For a bottom bar,
  from the bottom.
- radius `rounding.verylarge`, elevation 3 (`StyledRectangularShadow`), 10 from
  the anchor, 8 from the screen edge, dismiss on outside click and on Escape.

That replaces the current 35px slide + `380ms OutQuart` open + `260ms InCubic`
close. The slide is what an Android *notification shade* does; these are
anchored popups.

**Content entrance is one rule, everywhere.** Children of a popup enter
together, offset by `Appearance.animation.staggerStep` per index, capped at
`Appearance.animation.staggerCap` items (§2.8 — the token was added for this
cluster; it is the only stagger number any row may use):

```qml
readonly property int enterDelay: Appearance.animation.staggerStep
    * Math.min(index, Appearance.animation.staggerCap)
```

Each child's own entrance is **opacity on `elementMoveFast`** plus **one**
transform (a short translate toward its resting place, or a scale from ~0.9) on
**`elementMoveEnter`**. Not three transforms, not a rotation, and never an
overshooting curve on opacity or colour (§10.6).

**Exit is not the reverse of enter.** Enter decelerates on default spatial; exit
accelerates on fast effects at about half (§2.5). A popup whose content fades in
over 500ms and vanishes instantly is the bug this cluster has the most of.

**What dies in the shell.** `StyledPopup.childDelays`, `recalculateDelays()`,
`setupConnections()` and the `childrenChanged`/`visibleChanged` wiring feed
`updateChildrenAnimation()`, which is an **empty function with a comment saying
the children animate themselves**. ~90 lines of machinery, re-run on every open,
driving nothing. It goes.

## Contract 2 — the card vocabulary

`modules/ii/bar/cards/` is the shared kit every popup composes: `SectionCard`
(titled block), `HeroCard` (the one big thing at the top of a popup),
`InfoPill` (a full-radius row with a shape at each end), `MetricCard` /
`MetricsGrid`, `LoadingPlaceholder`. `ii-bar-cards` owns them; every other row
consumes them and may not edit them.

- **Layers nest by depth (§6.1).** The popup surface is the container; a card on
  it is `colLayer1` / `colSurfaceContainerHigh`; a block *inside* a card is
  `colLayer2`. No card may paint the same layer as the surface under it.
- **`SectionCard.showDivider` and its 2px `colSurfaceContainerHighest`
  rectangle are a separator bar.** Design law 11 / §5.5. Delete the property and
  the rectangle; the header–content gap becomes 12–16 on the 4dp grid. Five
  callers pass it today and none of them may keep it.
- **Every interactive part gets four states (§3.1).** `InfoPill`'s two circles
  and every raw `MouseArea` in the kit are hover-only today, via
  `Qt.lighter(colour, 1.15)` and `scale: 1.08` — both invented. Replace with
  `RippleButton` (§9 *Icon button*) or a `StateLayer`, with hover 0.08 / focus
  0.10 / pressed 0.10 taken from the `colLayerNHover`/`colLayerNActive` sibling
  of whatever layer the part paints, plus `Qt.PointingHandCursor` and a ≥32px
  hit area (§3.4).
- **`startAnim` stays as the entry point, its insides are retokenised.** Every
  card resets its children and fires a `SequentialAnimation` of
  `PauseAnimation { duration: 60|80|120|160|200 }` + `OutCubic`/`OutBack` at
  250–1120ms. Keep the `startAnim` and `*AnimDelay` properties — three other
  rows drive them and the API is frozen this pass — and rebuild the bodies on
  the enter rule in Contract 1. `HeroCard`'s `duration: 1120` shape scale is the
  worst offender in the cluster; nothing here is screen-sized, so nothing here
  may exceed 500ms (§2.4).
- Sizes and gaps on the 4dp grid (§5.1). `horizontalCenterOffset: 9`,
  `implicitWidth + 20`, `spacing: 6`, `topMargin: 1`, `padding: 5` are not.

## Contract 3 — the bar strip itself

- Every bar item is a hover target that opens something: it needs all four
  states, a ≥32px hit area, and `Qt.PointingHandCursor`. Several are bare
  `MouseArea`s that render hover only.
- Bar items sit on `colLayer0`; their hover/pressed films are
  `colLayer0Hover` / `colLayer0Active`, never a hand-mixed tint (§6.1).
- **Icon-sized items scale, filled items do not** (§3.3): hover 1.1 over 300ms
  `emphasizedDecel` multiplied by a 0.88 press squish, as `DockButton` composes
  it. A filled or carded item takes the state layer and, if it changes shape, a
  shape morph on `elementMoveSmall` — never a growing rectangle (§9 *Button*).
- Width and visibility changes as widgets appear and vanish animate on
  `elementResize` / `elementMove`; an item appearing must specify both
  directions (§2.5).
- No separator bars (law 11). `Spacebar` already defaults to `empty`
  (`DECISIONS.md` 10) — the styles stay for a config that explicitly picked one,
  and nothing new may paint one.

---

## The motion table every row uses

| What | Spec |
|---|---|
| position, size, layout | `Appearance.animation.elementMove` |
| small widget, chip, radius morph | `elementMoveSmall` |
| something appearing | `elementMoveEnter` |
| something leaving | `elementMoveExit` |
| colour, opacity, tint | `elementMoveFast` |
| implicit size | `elementResize` |
| press springing back | `clickBounce` |
| popup open/close | the `arrowPopup*` composite (Contract 1) |
| sibling stagger | `staggerStep` × min(i, `staggerCap`) |

No literal `duration:`, no literal curve, no hex, no literal radius — anywhere,
including inside a `SequentialAnimation` and including `PauseAnimation`. There
are 321 mechanical hits across this cluster (192 top level, 116 cards, 13
weather); most are durations in the vendored popups.

## Cost

From each row's *Effect budget*. The rule is one layer or effect per widget and
none inside something that repeats (law 8, §8):

- `cards/WorldClocksCard.qml:104` — `layer.enabled` + `OpacityMask` **inside a
  repeater delegate**. That is the one true violation in the cluster and it goes:
  a per-clock fade mask is not worth a texture per delegate.
- `Workspaces.qml:534` — `ColorOverlay` **per workspace icon**. Same rule. Use
  a tinted `MaterialSymbol`/`CustomIcon` or `IconImage`'s own colouring.
- `ResourcesPopup.qml` — five `layer.enabled` + `OpacityMask` pairs in one file.
  They are not in delegates, but five masks in one popup is over budget: keep
  the one that masks the scrolling content, drop the rest.
- `StyledPopup.qml` — `Timer 60ms`, `Timer 30ms`, `Timer 1ms`. A 1ms timer is a
  frame-order hack; name what it is waiting for and use `Qt.callLater` or the
  property change that actually signals it.
- Shadows (`BarContent`, `SysTrayMenu`, `StyledPopup`) are elevation and stay.

## Delete

Standing across the cluster, no per-row permission needed:

1. `SectionCard.showDivider` and its rectangle, and the `showDivider:` line at
   every caller.
2. `StyledPopup`'s `childDelays` / `recalculateDelays` / `setupConnections` /
   `updateChildrenAnimation` machinery.
3. Every `PauseAnimation` ladder replaced by the one stagger rule.
4. Any property the pack lists that nothing reads (`reachable.py`-style dead
   props — several rows have them; `ii-background-root` found seven).

## Out of scope

- `modules/common/widgets/**` — audited and closed (`cw-*`). Reuse, do not edit.
  The one exception is `Appearance.animation.staggerStep`/`staggerCap`, added by
  the dispatching session for this cluster.
- `modules/ii/verticalBar/**` — its own surface, and it instantiates `Bar.*`,
  `BatteryPopup`, `ClockWidgetPopup`, `MediaPopup`, `ResourcesPopup`,
  `Resources` by name. Nothing here may rename a type or change a property those
  files pass.
- `Config.qml` and the config schema. No new options, no renamed keys.
- `services/**`.
- The re-port hazard: `cards/*.qml` and the five popups are vendored from
  ii-p3drovfx by `tools/p3-bar-popups/port-popups.sh`, which `cp`s named files.
  It is a manual, deliberate run (`AUDIT.md`, *The re-port hazard*; only
  `ii-background-widgets` is `--delete`-rsynced and permanently out), so this
  redesign stands — but a future re-port overwrites it and must be reviewed
  file by file rather than run blind. Recorded in each row's `notes.md`.

## Fences — read before touching anything

Seven sessions run at once on one live desktop. The repo **is** the running
shell (`~/.config/quickshell/ii` is a symlink into it), so an edit is live the
moment it is saved.

1. **Your files only.** Your row's `brief.md` lists them. Not one line outside
   that list — not a caller, not a shared widget, not `Appearance.qml`. If your
   row needs a change in someone else's file, write it in your report and let
   the dispatching session route it.
2. **Frozen APIs.** Every `property`, `signal` and `function` name in your
   row's `pack.md` *Declared API* that another file reads stays. Add freely;
   do not rename or remove. This is what lets seven rows land without a merge.
3. **No git. No shell. No `pkill`.** Do not commit, stage, stash, checkout or
   revert; the dispatching session owns git. Do not run `iiren run`,
   `tools/audit/smoke.sh` or anything that `pkill`s `qs` — smoke.sh kills every
   quickshell on the machine, including the user's desktop and the other six
   sessions' work. The dispatching session runs the shell gates once, at the end.
4. **Path-filtered checks.** `python3 tools/check-design.py --diff` reports every
   session's added lines at once. Filter to your own files
   (`| grep -E 'YourFile|OtherFile'`) and judge only those. qmllint is yours to
   run, in your own shadow directory — never a shared one.
