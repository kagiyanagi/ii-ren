# ii-bar — notes

Seven rows, one brief, seven parallel sessions, one dispatching session that held
no surface of its own and owned only git, the gates and the merge. All seven
landed. `brief.md` is what was decided before the code; this is what the diffs
will not show.

| row | commit |
|---|---|
| packs, cluster brief, seven row briefs, the stagger token | `docs(ii-bar): one brief for seven rows…` |
| `ii-bar-chrome` | `refactor(ii-bar-chrome): a bar that slid in and out on the same spec…` |
| `ii-bar-weather` | `refactor(ii-bar-weather): a popup that stated four wrong numbers…` |
| `ii-bar-resources` | `refactor(ii-bar-resources): the same meter written three times…` |
| `ii-bar-popups` | `refactor(ii-bar-popups): ninety lines that computed a stagger…` |
| the popup-radius seam | `fix(ii-bar): two popups pinned to the radius the shell no longer uses` |
| `ii-bar-cards` | `refactor(ii-bar-cards): four effects for a glow on one corner…` |
| `ii-bar-tray` | `refactor(ii-bar-tray): two shader passes per tray icon…` |
| `ii-bar-widgets` | `refactor(ii-bar-widgets): an indicator that summed raw indices…` |

Gates at the end: `check-design.py --diff` clean across the cluster, qmllint 0
errors on all 52 files, `check-effect-budget.py` green, `check-m3-tokens.py`,
`check-button-states.py`, `check-scaffold-containers.py`,
`check-text-primitives.py` ok, and five new checks
(`check-bar-reveal`, `check-weather-hourly`, `check-resources-popup`,
`check-popup-pivot`, `check-bar-cards`, `check-systray-menu-origin`,
`check-workspace-indicator`). `tools/audit/smoke.sh` passes: shell up, all four
layers present, and **zero `modules/ii/bar` lines in the log**. The only log
noise is the eight known `[undefined]` assignments in
`modules/ii/background/widgets`, which are permanently out of scope
(`DECISIONS.md` 3).

## Taking a screenshot of this bar — read this first, it cost an hour

**A fullscreen window hides every layer surface on its workspace.** A bar
screenshot taken while anything is fullscreen shows bare wallpaper, which looks
exactly like a shell that renders nothing, and that reading survives a `qs`
restart, so it survives a bisect too. Half this session's closing time went into
bisecting a regression that did not exist.

Before believing a blank bar:

```sh
hyprctl clients -j | python3 -c "import json,sys; [print('FULLSCREEN:', c['class'], c['workspace']['id']) for c in json.load(sys.stdin) if c.get('fullscreen')]"
hyprctl layers | sed -n 's/.*namespace: \([^,]*\).*/\1/p' | sort -u   # is quickshell:bar even up
```

Shoot on an empty workspace with no fullscreen window anywhere, and confirm the
switch landed before grabbing:

```sh
hyprctl dispatch 'hl.dsp.focus({ workspace = 9 })'   # Lua, not hyprlang: plain `dispatch workspace 9` is a Lua syntax error here
hyprctl activeworkspace -j                            # assert id == 9, windows == 0
grim shot.png
```

`smoke.sh` says the layer exists, not that it drew anything — its own docstring
says a QML error that blanks a panel family prints nothing at all. A still frame
is the only thing that catches a blank surface, and it only counts if the
desktop state is known.

## Parallel dispatch, for the next cluster that wants it

The four fences from `.audit/common-widgets/notes.md` plus two this cluster
needed (`DECISIONS.md` 25). What actually mattered in practice:

- **`smoke.sh` cannot run while siblings are editing.** It `pkill`s every
  quickshell, which would kill the user's desktop and gate six half-finished
  rows at once. Defer it to the end, once, and say so in every row brief.
- **`check-design.py --diff` is repo-wide**, so every session sees every other
  session's added lines. Each row filters to its own paths; the dispatcher runs
  it unfiltered at the end.
- **`mkshadow.sh` `rm -rf`s its output**, so a shared shadow dir races. One per
  row.
- **The seams are the dispatcher's job and they are real.** Two landed here: the
  popup radius default moved while two files outside that row pinned the old
  value, and `showDivider` had to be deleted at the callers *before* the
  property, in the opposite order to the fence's natural instinct — a stale
  assignment to a property a type no longer has is the one failure that stops
  the shell booting.
- **Rows find each other's bugs.** Four of the eight routed findings below came
  from a row that was fenced out of fixing them. Ask for that section explicitly
  in the brief; it is most of the value of running them together.

## Routed — real, found with evidence, outside every row's fence

Each needs a queue row or an owner; none is speculative.

- **`services/LocalSend.qml` is missing four members `cards/LocalSendSendCard`
  calls** — `scanning`, `startScanning()`, `stopScanning()`, `openFilePicker()`
  exist nowhere on the singleton. `Component.onCompleted` and `onDestruction`
  throw on every card create and destroy, "Add Files…" does nothing, and "Scan"
  never spins. Pre-existing.
- **`services/Weather.qml`** — `getData()`'s ip-api branch and
  `fetchCoordinates`'s empty-results branch both return without clearing
  `forecastLoading` or arming a retry, so a misspelt city spins forever; and
  `refineData` walks `hourly.time` while indexing `hourly.temperature_2m` with
  no length check, which is where the `"NaN"` strings come from. `WeatherPopup`
  works around both from outside.
- **`BarGroup` / `BarComponent` paint no hover or press state anywhere**, so
  Contract 3's four states have no implementation for `Resources`,
  `ClockWidget`, `BatteryIndicator`, `NetworkSpeed` or `Media`. The fix belongs
  in `BarGroup`, which already owns the background, the per-group radii and the
  colour Behavior; five copies inside individual widgets would be five films at
  the wrong radius (anti-pattern 13). **Deliberately left undone rather than
  done badly** — it is the cluster's one real gap.
- **`BarComponent.toggleVisible()` persists into
  `Config.options.bar.layouts.*`**, so a widget that auto-hides writes its own
  removal into the user's bar. Two widgets poke `visible` directly to avoid it.
  Wants a non-persisting transient-visibility entry point.
- **`RippleButton.qml:185` sets `layer.enabled` unconditionally** on its
  background, so every RippleButton used as a delegate carries a texture. This
  is why `SysTrayItem` stayed a `MouseArea` — converting it would have traded a
  removed effect straight back. `modules/common/widgets` is closed; wants a row.
- **`Appearance.colors` has no `colPositive`/`colOnPositive`** (`DECISIONS.md`
  27). Two hand-rolled greens are waiting on it.
- **`verticalBar/VerticalMedia.qml:96` overwrites `StyledPopup`'s `active`
  binding** with its own hover condition, so that popup is destroyed the instant
  the pointer leaves and has never played a close animation. `externalOpen`
  exists for exactly this, and it is more visible now that the close is 233ms of
  real motion.
- **`verticalBar/VerticalBarContent.qml:19`** declares
  `HorizontalBarSeparator` — a separator bar (law 11) that nothing instantiates.
- **`dock/widgets/DockIcon.qml:28-47`** has the identical two-pass
  `Desaturate` + `ColorOverlay` shape the tray row just collapsed into one
  `MultiEffect`.
- **`PoliciesPanelButton.qml:23` and `DashboardPanelButton.qml:35` use a
  top-level `onPressed:` on a `RippleButton`** whose internal MouseArea never
  emits `pressed()`. Either both handlers are dead or the reading is wrong.
  These are the bar's two sidebar buttons — **needs one live click before
  anyone touches it**.

## Watch at 60fps — the cohesion pass list

Still frames prove none of this. Grouped by what to do, not by which row found
it.

**Open something**

1. Popup open/close and its pivot, every bar orientation, and a tray icon hard
   against the right edge against the clock in the centre. The arithmetic is
   asserted by `check-popup-pivot.py`; the look is not.
2. The 1.02 overshoot against the 10px elevation margin — ~8px on a 380px
   popup, inside the margin, but confirm the widest popup never clips its own
   window.
3. Reopen: pointer leaves and comes straight back mid-close. The `interval: 1`
   timer is kept rather than dropped to 0 precisely because it waits on Qt's
   `DeferredDelete`; if a popup ever fails to reopen, that is the number.
4. Content entrance now crosses the `> 0.6` gate at ~50ms instead of ~130ms, so
   the stagger tail finishes with the surface. Check it reads as one motion, not
   as content arriving before its card.
5. Tray menu open/close, plus a submenu push (the card resizes while the content
   crossfades), and the one-frame teardown after `menuClosed`.
6. Double opacity ramp in the weather popup: each card fades as a unit while its
   own children fade inside it. Both on `elementMoveFast`, so it should read as
   one — but it is opacity².

**Move between workspaces**

7. The workspace indicator: slide and stretch, icons on *and* off,
   `dynamicWorkspaces` on *and* off, and while a workspace's width is changing
   (open a window on the workspace you are leaving). Geometry is asserted by
   `check-workspace-indicator.py`; the **timing composite is not** —
   `AnimatedTabIndexPair` 350/500, the delegates' `elementResize` 350 and
   `visualInset` on `elementMove` 500 all overlap. If it reads wrong, the inset
   is the knob.

**Make something appear or vanish in the strip**

8. The auto-hide reveal at both edges, with `pushWindows` on and off — the
   `exclusiveZone` flip is Hyprland's own animation running alongside. Confirm a
   reversal mid-slide cuts in rather than finishing.
9. Super-press reveal — same motion, different trigger.
10. A widget collapsing out of the row (start a recording or a timer, empty the
    tray): the 4px spacing dropping at the end of the collapse must not read as
    a hitch, and the neighbours' corner morph should land with it.
11. `toggleVisible(false)` writes the bar layout to disk at the end of the exit —
    watch for a hitch on the last frame.
12. `NotificationUnreadCount`'s ping, which now grows from `Item.BottomLeft`.
13. `TimerWidget` when the second chip appears; `DashboardPanelButton` when a
    toggle changes, now that the gap rides the same spec as the width.

**Look at it at rest**

14. `ClockHeaderCard` without the frosted corner — the soft blur is gone; judge
    the flat face against `colPrimaryContainer`.
15. `WorldClocksCard`'s decorative blob at 1, 2 and 4 clocks, and in sharp mode.
16. The resources meter below ~17%, where the scissor shows the track's left cap
    truncated — confirm it reads as a meter, not a blob.
17. The graph well's bottom-left corner: the Canvas's 2px stroke may clip ~1px
    where the arc turns in. Predicted sub-pixel; no off-grid fudge was added.
18. Sizes shifted: bar padding 5 → 4, `CircleUtilButton` 26 → 32,
    `PoliciesPanelButton` 29.5 → 32. Check the strip still reads balanced and
    that `Appearance.sizes.barHeight` still contains them.
19. Tray icon hover: the icon now carries `layer.enabled` (monochrome default)
    *and* scales to 1.1, so a 20px texture is upscaled 10%. If it looks soft,
    the fix is `layer.textureSize` or moving the scale off the layered item.
20. The stagger cap — everything past the sixth sibling lands together, visible
    on a 24-bar hourly forecast and a long alarm list. Intended per 2.8.

**Re-measure if it feels wrong**

21. `Visualizer` 80ms → 130ms. There is no faster token in `Appearance`; if the
    bars read laggy against the audio, the fix is a new sub-130ms effects
    duration, which is a token change.
22. `Media` width, `elementMoveFast` (200, no overshoot) → `elementResize` (350,
    overshoots). Track changes now nudge the centre group; `elementMove` is the
    fallback.
23. Keyboard in the tray menu: `hyprland-focus-grab-v1` enters "a
    compositor-picked surface in the whitelist" and `SysTray` whitelists both
    the bar and the menu. If Hyprland picks the bar, Escape and the arrows are
    inert. No regression — there was no key handling at all before — but it
    needs one live confirmation.

## Re-port hazard

`cards/*.qml` and the five popups are vendored from ii-p3drovfx by
`tools/p3-bar-popups/port-popups.sh`. Unlike the background widget tree it `cp`s
named files rather than rsyncing with `--delete`, and it only runs when someone
deliberately points `P3=` at a fresh clone, so this redesign stands. But a
re-port overwrites all of it, and `BatteryPopup` in particular is now
structurally different — four `MetricCard`s where there were 400 lines of
hand-rolled cells. Review file by file, never run it blind. None of the chrome,
widgets or tray files is touched by that script.

## Superseded

`.audit/ii-bar-root/pack.md` is kept, not deleted: its **Used by** section is the
only place the cross-group caller picture for the 36 top-level files exists. The
five sub-packs replaced it for reading.
