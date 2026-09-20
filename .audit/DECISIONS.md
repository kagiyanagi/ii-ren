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
| 1 | The M3 stretch overscroll was dead for everyone — `WheelScrollHandler` gated its own `visible` on `interactions.scrolling.fasterTouchpadScroll`, which is `false` by default, and an invisible `MouseArea` gets no wheel events | **Decouple, do not flip the default.** The key is a *speed* preference; the stretch is design law (3.6) and is not optional. The handler is always live now and hands the wheel back to the Flickable unless the key is on — except at a bound, where the Flickable has nothing to do and the leftover becomes stretch | **done** |
| 2 | `cw-overscroll`: a drag past the end *translates* the content, where 3.6 says stretch | **Do it now, with `boundsMovement: StopAtBounds`.** Qt's documented hook: the content stops, `verticalOvershoot` still reports the overhang. No new code to measure the drag, and the 500ms `Behavior` that would have fought a live drag is gone — the drag tracks 1:1 and only the release animates | **done** |
| 3 | The vendored p3drovfx trees (`ii-background-widgets`, 122 files / 27.7k lines) — redesign them or leave them out | **Leave them out permanently.** `port-widgets.sh` rsyncs with `--delete`, so a redesign is reverted by the next re-port, and re-porting is worth more than owning 27.7k lines that are not ours. Cost, accepted: the 8 `[undefined]` assignments and the worst of the 21 effects-in-delegates stay. Queue row `skip`, not `todo` | **done** (`AUDIT.md` scope) |
| 4 | Perf never entered the audit — no pack facts, no brief heading, no gate | **Take the cheap half.** `pack.py` now emits an **Effect budget** (every `layer.enabled` / `MultiEffect` / `OpacityMask` / `ShaderEffect` / shadow / `Canvas` and every sub-100ms `Timer`, flagged when it sits inside something that repeats) and the brief template gained a `**Cost.**` line. No new gate: `check-effect-budget.py` already fails on a new nested effect | **done** |
| 5 | `RippleButton`'s `StateOverlay` drives focus and press but not hover, so callers hand-mix a film — two ship 0.05 where the token is 0.08 | **Fix the two, not the base.** 261 files set a hover colour; making hover a film at the root is a redesign of the library's hover model and wants a measured before/after, not a default flip. `ToolbarTabButton`'s two alphas are now 0.08 / 0.10 | **done** + revisit queued |
| 6 | `CustomBatteryMeter.isCritical` is wired end to end and read by nothing — critical and merely low render identically | **Use the error *container* for the track.** One existing token, no new recipe, no pulse (rule 8), and it reads as louder than low without inventing anything DESIGN.md cannot source | **done** |
| 7 | Motion across the tranche is unverified — twelve families retimed animations and none could run the shell | **Verify once, in the cohesion pass**, against the list each row left in its `notes.md`, not per row. The standing list is below | **queued** (cohesion pass) |
| 8 | `settings-widgets` (191 files / 35k lines) is still a tranche | **Split it the same way `common-widgets` was**, in its own session. It is the other half of "fix the shared base first" | **queued** (`settings-widgets`) |
| 9 | The vision pass was 2-for-13 | **Keep it, once per tranche, never per surface, and never unverified.** It found the one defect the whole checker suite is structurally blind to. `vision.md` is evidence, not a to-do list | **done** (recorded) |
| 10 | Bar and dock paint separator bars (`Spacebar`, `SysTray`, `DockSeparator`/`SectionSeparator`) against law 11 | **Change what ships, keep what was chosen.** New spacers default to `empty`, the dock's `separatorStyle` defaults to `Empty`, `SysTray`'s dead `showSeparator` is gone. The styles stay for a config that explicitly picked one | **done** |
| 11 | `check-design.py`'s `no-separator-bars` matched `WindowDialogSeparator` **by name** | **Check the shape.** An outline colour used as a fill is a divider whatever the type is called. Catches `Spacebar`, `DockSeparator` and a third nobody had noticed (`sidebarPolicies/StatusSeparator.qml`); 16 hits, all legacy, all `warn` | **done** |
| 12 | The checker's exported-knob blind spot fired its third instance | **Tighten both halves.** `literal-duration` now reads an arithmetic expression (`duration: 300 / 2` hid a literal in a 471-caller widget), and a new `exported-motion-knob` rule flags a `*Duration` / `*Curve` property with a literal default | **done** |
| 13 | `ColorOverlay` → `Colorizer` (9 sites) and `StyledDropShadow` → `StyledRectangularShadow` (~20 sites) | **Do not bulk-migrate.** `ColorOverlay` blends and `Colorizer` flattens; the shadow swap is only right where the target is a plain rounded rectangle. Per-caller judgement, inside each caller's own row | **declined** as a batch |
| 14 | The `ArrowPopup` enter/exit recipe is transcribed in four files | **Extract it in the first popup row that opens**, not as a library change with no surface to test it on | **queued** |
| 15 | `WindowDialogSlider` — zero callers, fell between `cw-inputs` and `cw-dialogs` | **Delete.** Nothing imports it; `git revert` is the undo | **done** |
| 16 | `StyledScrollBar.active: hovered \|\| pressed` — the bar never appears while the content scrolls | **Restore what QQC2 binds.** A wheel or a flick shows the bar; the drop was not a decision anyone made | **done** |
| 17 | `AGENTS.md` / `AUDIT.md` still said one surface per session, and listed three built tools as "not built yet" | **Document what actually happened.** The tranche ran twelve families at once from a session that held no surface itself; that is the same rule, not an exception to it | **done** |
| 18 | The three `[undefined] to double` warnings in the Android quick toggles | **Fix at source, now.** They were a `Rectangle` state film over a `ShapeCanvas`, reading a `radius` that does not exist there. The film composites into the shape's own fill instead — no second canvas, correct shape, and the warnings are gone from the smoke run | **done** |
| 19 | `services/Ai.qml:396` called `addUserModels()`, which was never written | **Delete the call.** Both config-fed model lists (`modelsOfProviders`, `otherModels`) are bindings and already update when the config arrives | **done** |
| 20 | `modules/settings/widgets/LauncherResultsConfig.qml` assigns five properties `ConfigListView` never declared | **Delete the file; drop the three stray assignments in `BarLayoutConfig`.** It has zero callers, and its `SearchResultSectionRegistry` singleton and `Config.options.search.sectionOrder` path do not exist anywhere in the repo. **Measured, and the earlier `FINDINGS.md` claim was wrong:** re-adding one bogus assignment and opening the page shows it loads and works — QML accepted it silently — so this was dead weight, not a dead page | **done** |

## What the cohesion pass has to watch at 60fps

From the rows that retimed something and could not drive the shell:

- The **tab indicator**, 50/200 → 350/500 — the most repeated motion in the cheatsheet and
  the region selector (`cw-navigation`).
- The **40dp switch halo**, now on ~129 `ConfigSwitch` rows (`cw-config-rows`).
- **Notification group expansion**, which lands `contentHeight` in steps
  (`cw-notifications`).
- The **stretch overscroll** on a real touchpad: measured at 47px peak on a 750px viewport
  through a wheel, but the feel of the release is a hand judgement (this pass).
- **Swipe-to-dismiss** on the clipboard toast — `dismissFraction` and `escapeVelocity` are
  the two knobs, and synthetic drags cannot judge them (`ii-clipboardToast`).

## Still nobody's call but yours

- **Scroll speed.** `fasterTouchpadScroll` still defaults `false`, and now means only what
  its name says. If the shell's own factors (mouse 120, touchpad 450) feel better than
  Qt's, turn it on in Settings → Interface; nothing about the stretch depends on it any
  more.
- **Whether the two bar spacers should exist at all.** They are `empty` now, so they are
  8px of whitespace rather than pipes. Removing them entirely is one click each in
  Settings → Bar → layout.
