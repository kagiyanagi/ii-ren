# DECISIONS.md — the open calls, decided

Every item the audit sessions raised and left to a human, with the call made and why.
Written 2026-09-20 in one pass over the twelve `cw-*` sessions, the pilot, the tranche
split and the vision pass. `FINDINGS.md` holds the bugs; this holds the judgements.

Nothing here is a new finding. If a row says **done**, it landed in the same pass and the
gates ran; if it says **queued**, the queue row named in the row is where it happens; if it
says **declined**, the reason is the whole point of writing it down.

## The calls

| # | Question | Decision | State |
|---:|---|---|---|
| 1 | The M3 stretch overscroll was dead for everyone — `WheelScrollHandler` gated its own `visible` on `interactions.scrolling.fasterTouchpadScroll`, which is `false` by default, and an invisible `MouseArea` gets no wheel events | **Decouple, do not flip the default.** The key is a *speed* preference; the stretch is design law (3.6) and is not optional. The handler is always live now and hands the wheel back to the Flickable unless the key is on — except at a bound, where the Flickable has nothing to do and the leftover becomes stretch | **reversed by 24** |
| 2 | `cw-overscroll`: a drag past the end *translates* the content, where 3.6 says stretch | **Do it now, with `boundsMovement: StopAtBounds`.** Qt's documented hook: the content stops, `verticalOvershoot` still reports the overhang. No new code to measure the drag, and the 500ms `Behavior` that would have fought a live drag is gone — the drag tracks 1:1 and only the release animates | **reversed by 24** |
| 3 | The vendored p3drovfx trees (`ii-background-widgets`, 122 files / 27.7k lines) — redesign them or leave them out | **Leave them out permanently.** `port-widgets.sh` rsyncs with `--delete`, so a redesign is reverted by the next re-port, and re-porting is worth more than owning 27.7k lines that are not ours. Cost, accepted: the 8 `[undefined]` assignments and the worst of the 21 effects-in-delegates stay. Queue row `skip`, not `todo` | **done** (`AUDIT.md` scope) |
| 4 | Perf never entered the audit — no pack facts, no brief heading, no gate | **Take the cheap half.** `pack.py` now emits an **Effect budget** (every `layer.enabled` / `MultiEffect` / `OpacityMask` / `ShaderEffect` / shadow / `Canvas` and every sub-100ms `Timer`, flagged when it sits inside something that repeats) and the brief template gained a `**Cost.**` line. No new gate: `check-effect-budget.py` already fails on a new nested effect | **done** |
| 5 | `RippleButton`'s `StateOverlay` drives focus and press but not hover, so callers hand-mix a film — two ship 0.05 where the token is 0.08 | **Fix the two, not the base.** 261 files set a hover colour; making hover a film at the root is a redesign of the library's hover model and wants a measured before/after, not a default flip. `ToolbarTabButton`'s two alphas are now 0.08 / 0.10 | **done** + revisit queued |
| 6 | `CustomBatteryMeter.isCritical` is wired end to end and read by nothing — critical and merely low render identically | **Use the error *container* for the track.** One existing token, no new recipe, no pulse (rule 8), and it reads as louder than low without inventing anything DESIGN.md cannot source | **done** |
| 7 | Motion across the tranche is unverified — twelve families retimed animations and none could run the shell | **Verify once, in the cohesion pass**, against the list each row left in its `notes.md`, not per row. The standing list is below | **queued** (cohesion pass) |
| 8 | `settings-widgets` (191 files / 35k lines) is still a tranche | **Split it the same way `common-widgets` was**, in its own session. It is the other half of "fix the shared base first" | **done** (ten `sw-*` rows) |
| 9 | The vision pass was 2-for-13 | **Keep it, once per tranche, never per surface, and never unverified.** It found the one defect the whole checker suite is structurally blind to. `vision.md` is evidence, not a to-do list | **done** (recorded) |
| 10 | Bar and dock paint separator bars (`Spacebar`, `SysTray`, `DockSeparator`/`SectionSeparator`) against law 11 | **Change what ships, keep what was chosen.** New spacers default to `empty`, the dock's `separatorStyle` defaults to `Empty`, `SysTray`'s dead `showSeparator` is gone. The styles stay for a config that explicitly picked one | **done** |
| 11 | `check-design.py`'s `no-separator-bars` matched `WindowDialogSeparator` **by name** | **Check the shape.** An outline colour used as a fill is a divider whatever the type is called. Catches `Spacebar`, `DockSeparator` and a third nobody had noticed (`sidebarPolicies/StatusSeparator.qml`); 16 hits, all legacy, all `warn` | **done** |
| 12 | The checker's exported-knob blind spot fired its third instance | **Tighten both halves.** `literal-duration` now reads an arithmetic expression (`duration: 300 / 2` hid a literal in a 471-caller widget), and a new `exported-motion-knob` rule flags a `*Duration` / `*Curve` property with a literal default | **done** |
| 13 | `ColorOverlay` → `Colorizer` (9 sites) and `StyledDropShadow` → `StyledRectangularShadow` (~20 sites) | **Do not bulk-migrate.** `ColorOverlay` blends and `Colorizer` flattens; the shadow swap is only right where the target is a plain rounded rectangle. Per-caller judgement, inside each caller's own row | **declined** as a batch |
| 14 | The `ArrowPopup` enter/exit recipe is transcribed in four files | **Extracted as `modules/common/widgets/ArrowPopupMotion.qml`, in `ii-dock`**, which held two of the four and so had two surfaces to test it on. Both had drifted, in opposite directions: `DockFolderPopup` into an inline bezier and six literal durations, `DockContextMenuBase` into no exit at all -- one spatial `Behavior` running both directions out of `Item.Center`. The caller still owns the `transformOrigin`, because that is the one part of the recipe that is per-surface. `DesktopMenu`, `HermesContextMeter` and `HermesApprovalModeMenu` still assemble it by hand and move over in their own rows | **done** (2 of 4) |
| 15 | `WindowDialogSlider` — zero callers, fell between `cw-inputs` and `cw-dialogs` | **Delete.** Nothing imports it; `git revert` is the undo | **done** |
| 16 | `StyledScrollBar.active: hovered \|\| pressed` — the bar never appears while the content scrolls | **Restore what QQC2 binds.** A wheel or a flick shows the bar; the drop was not a decision anyone made | **done** |
| 17 | `AGENTS.md` / `AUDIT.md` still said one surface per session, and listed three built tools as "not built yet" | **Document what actually happened.** The tranche ran twelve families at once from a session that held no surface itself; that is the same rule, not an exception to it | **done** |
| 18 | The three `[undefined] to double` warnings in the Android quick toggles | **Fix at source, now.** They were a `Rectangle` state film over a `ShapeCanvas`, reading a `radius` that does not exist there. The film composites into the shape's own fill instead — no second canvas, correct shape, and the warnings are gone from the smoke run | **done** |
| 19 | `services/Ai.qml:396` called `addUserModels()`, which was never written | **Delete the call.** Both config-fed model lists (`modelsOfProviders`, `otherModels`) are bindings and already update when the config arrives | **done** |
| 20 | `modules/settings/widgets/LauncherResultsConfig.qml` assigns five properties `ConfigListView` never declared | **Delete the file; drop the three stray assignments in `BarLayoutConfig`.** It has zero callers, and its `SearchResultSectionRegistry` singleton and `Config.options.search.sectionOrder` path do not exist anywhere in the repo. **Measured, and the earlier `FINDINGS.md` claim was wrong:** re-adding one bogus assignment and opening the page shows it loads and works — QML accepted it silently — so this was dead weight, not a dead page | **done** |
| 22 | 120 of the 190 files in `modules/settings/widgets` — 25,071 lines, 71% of the tranche — are reached by nothing: not instantiated, not named by any `Qt.resolvedUrl`, not in the widget registry | **Delete them, as row `sw-dead`, before any design row runs.** Same call as 20, at 120× the scale and with the same evidence: 486 of the 904 `Config.options.*` paths this directory reads do not exist in `Config.qml` (whole absent feature backends — `bar.portWatcher`, `phone.scrcpy`, `search.browserSites`, `calendar.timetable`, `appStats`), 66 of the 77 `check-design.py` hits are in those files, and every effect in the tranche is too. `git revert` is the undo, and the settings app is gated by the new `smoke-settings.sh` because `smoke.sh` never covered it | **queued** (`sw-dead`) |
| 24 | The stretch overscroll, once it was finally watched on a real desktop rather than measured | **Remove it entirely.** Glitchy at both anchors — decisions 1 and 2 are reversed, `verticalOvershoot`, `boundsMovement: StopAtBounds`, the `Scale` on `contentItem` and `WheelScrollHandler`'s whole accumulator are gone, and a drag past the end is Qt's own `DragOverBounds` rubber-band again. This is the shell's one deliberate departure from Android 16, so it is written into DESIGN.md 3.6 as an exception and `check-scaffold-containers.py` now fails if either flickable scales its content — the thing had already been built twice | **done** |
| 25 | `ii-bar-root` was 36 files / 9,535 lines, nearly four times the split rule, and the bar's popups and cards are shared by every row that touches them | **Split it five ways by widget group and write one brief for all seven bar rows.** The `cw-*` precedent: cohesion is bought at brief time, not at review time. Two fences on top of the usual four — the popup shell (`StyledPopup`) and the card kit are frozen-API for every row that does not own them, and no row may run `smoke.sh`, which `pkill`s every quickshell on the machine | **done** |
| 26 | `Workspaces`' monochrome icons were a `Desaturate` + `ColorOverlay` per app icon, on by default. Collapsing them into one `MultiEffect` cached at the icon row is this gate's own prescribed fix, but the row still sits inside the per-workspace Repeater, so `check-effect-budget.py` reads it as a new nested effect | **Amend `KNOWN`, with the argument written next to it.** Two framebuffers per icon became one per workspace, and it cannot rise further — one level up holds the number and the dot, which must not be desaturated. The list comes out shorter overall: the old `ColorOverlay` entry, `WorldClocksCard`'s pair and two stale `sw-dead` entries all went. Anything that lands there without that argument is a real hit | **done** |
| 27 | `PrivacyIndicator`'s `#10DB5C` and `#1589FA` are hex literals, which 6.1 forbids outright | **They stay.** They are Android 16's fixed privacy-chip colours: a green camera dot that shifts hue with the wallpaper stops meaning "camera". This is *not* the same as `BatteryPopup`'s charging green, which should be theme-derived and is only hand-rolled because `Appearance.colors` has no `colPositive`/`colOnPositive` role — two rows flagged that gap independently and it is the cheapest follow-up in the cluster | **done** (hexes), **open** (`colPositive`) |
| 23 | The 62 registry-fed `Desktop*Config.qml` pages configure a vendored tree that is permanently out of scope — are they out too | **No, they are in.** `port-widgets.sh` rsyncs `modules/ii/background/widgets` and the assets and never touches `modules/settings/`, so unlike decision 3 a redesign here survives the next re-port. The standing cost is the other direction: a re-port can add a registry entry whose `configPage` names a file we do not have. `reachable.py` after a re-port is what catches it | **done** (recorded, `notes.md`) |
| 28 | The periodic table needs to encode element family, block and five periodic trends in colour, which 6.1 forbids outright — every colour comes from `Appearance.colors.*` | **Fixed hexes, in one file, with the validation written next to them.** This is 27's precedent at larger scale: a family hue that shifts with the wallpaper stops meaning "halogen", and a heat map re-themed per wallpaper cannot be read against its own legend, so here the colour *is* the data. What makes it not a licence to sprinkle hex: every scale was produced by search and run through the data-viz validator rather than picked by eye (family, 10 slots, adjacent pairlist — CVD ΔE 11.9 against a target of 8, normal-vision ΔE 15.2 against a floor of 15; block, 4 slots, all-pairs — CVD 8.8, normal-vision 21.1, contrast ≥ 3:1; trend, 7 steps, one hue, monotone and ≥ 2:1 at the dim end), each mode is stepped for its own surface rather than flipped, and `check-periodic-table.py` fails if a step is edited by hand. Ten hues cannot pass all-pairs — no ten can — so the 4-colour **Block** mode is the colour-blind-safe view of the same table, every tile is directly labelled, and a legend is always on screen | **done** |

## Found after the fact

**21 — `ContentSubsection` lost its implicit width** (`cw-scaffolding`, 74f5253d6). Moving
the header from a `RowLayout` into an `Item` that reported only `implicitHeight` took the
section's whole implicit width with it: measured 106→0, 124→0, 154→0, 196→0. Every
`ConfigRow` cell with `Layout.fillWidth: false` collapsed, so its chips stacked in a column
and its card drew as a 4px sliver, with the titles of two such cells overlapping each
other. Fixed in both section widgets, with the content wrapper now reporting its
`ContentGroup`'s width too, so a card hugs its chips rather than its title -- measured
better than the pre-audit layout, which wrapped "Group style" into three rows.
`check-scaffold-containers.py` gained the assertion; it caught the second wrapper while
being written. **The lesson for the rest of the audit:** a widget that wraps a child for a
layout has to report both implicit dimensions, and nothing in the toolchain says otherwise
-- not Qt, not qmllint, not `check-design.py`, and not a still frame of the surface that
row owns.

## What the cohesion pass has to watch at 60fps

From the rows that retimed something and could not drive the shell:

- The **tab indicator**, 50/200 → 350/500 — the most repeated motion in the cheatsheet and
  the region selector (`cw-navigation`).
- The **40dp switch halo**, now on ~129 `ConfigSwitch` rows (`cw-config-rows`).
- **Notification group expansion**, which lands `contentHeight` in steps
  (`cw-notifications`).
- **Swipe-to-dismiss** on the clipboard toast — `dismissFraction` and `escapeVelocity` are
  the two knobs, and synthetic drags cannot judge them (`ii-clipboardToast`).
- The **desktop menu's close**, 190/60 → `arrowPopupCloseDuration` 233 / `arrowPopupFadeHold`
  150 — AOSP's own numbers, but on a menu that is dismissed constantly, and the comment
  they replaced argued that is exactly where AOSP drags (`ii-desktopMenu`).
- The **dock context menus' enter and exit**, which did not exist — one `Behavior on
  scale` and one `Behavior on opacity`, both `elementResize`, both directions, out of
  `Item.Center`. Now the `ArrowPopup` composite out of the dock's edge. Most-opened
  popup in the surface and the biggest motion change in the row (`ii-dock`).
- The **dock icon hover**, same 300ms `emphasizedDecel` but now `alwaysRunToEnd: false`
  via `Appearance.animation.iconHover`. A pointer flicked along the strip should
  reverse mid-flight rather than finish each icon's growth (`ii-dock`).
- The **notification stack's exit**, which did not play at all: the layer surface unmapped
  on the frame the list emptied, so the last card of every burst — usually the only card —
  cut rather than slid. A 130ms grace keeps the window mapped for `StyledListView`'s
  `remove`; what to watch is whether 130ms reads as a slide or as a stutter now that it is
  visible for the first time (`ii-notificationPopup`).
- The **notification stack's sidebar dodge**, `elementMoveEnter` → `elementMove`, i.e. the
  slide became interruptible. Unreachable under the shipped config — opening the dashboard
  times every popup out first — so set `sidebar.position` to `inverted`, raise a
  notification, and open and close the policies sidebar before the slide lands
  (`ii-notificationPopup`).

## Still nobody's call but yours

- **Scroll speed.** `fasterTouchpadScroll` still defaults `false`, and now means only what
  its name says. If the shell's own factors (mouse 120, touchpad 450) feel better than
  Qt's, turn it on in Settings → Interface. With the stretch gone (24) that key is the only
  thing `WheelScrollHandler` still does.
- **Whether the two bar spacers should exist at all.** They are `empty` now, so they are
  8px of whitespace rather than pipes. Removing them entirely is one click each in
  Settings → Bar → layout.
