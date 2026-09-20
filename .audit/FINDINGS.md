# Pre-existing findings

Bugs already in the shell, found incidentally rather than by auditing a surface. Each is
assigned to the surface that owns it; fix it when that surface comes up, not before.

## From `tools/audit/smoke.sh` on a clean tree, 2026-09-20

The shell boots and renders with all of these; they are silent in normal use.

| where | error | owner |
|---|---|---|
| `modules/ii/sidebarDashboard/quickToggles/androidStyle/AndroidBluetoothToggle.qml:422:37` | `Unable to assign [undefined] to double` | `ii-sidebarDashboard-quickToggles` |
| `.../AndroidBluetoothToggle.qml:511:37` | `Unable to assign [undefined] to double` | `ii-sidebarDashboard-quickToggles` |
| `.../AndroidNetworkToggle.qml:81:25` | `Unable to assign [undefined] to double` | `ii-sidebarDashboard-quickToggles` |
| `services/Ai.qml:396` | `TypeError: Property 'addUserModels' of object Ai is not a function` | `services-Ai` — **row added 2026-09-20** |

The 2026-09-20 run was made with no media player running. With one playing, five more
appear — all pre-existing, confirmed against a stashed tree while auditing `cw-buttons`:

| where | error | owner |
|---|---|---|
| `modules/ii/background/widgets/media/ExpressiveMediaWidget.qml:334,344` | `Unable to assign [undefined] to int` | `ii-background-widgets` |
| `.../ExpressiveMediaWidget.qml:390` | `Unable to assign [undefined] to bool` | `ii-background-widgets` |
| `.../ExpressiveMediaWidget.qml:410,453` | `Unable to assign [undefined] to QColor` | `ii-background-widgets` |

## From auditing `ii-clipboardToast`, 2026-09-20

| where | issue | owner |
|---|---|---|
| `modules/common/widgets/RippleButton.qml` | Renders hover, pressed and disabled but no focus state. `Button.visualFocus` is never read, so DESIGN.md 3.1's four states are three on every caller. Harmless on a layer surface with `keyboardFocus: None`; not harmless in the settings app. | `cw-buttons` — **fixed 2026-09-20** |

## From `tools/p3-widget-port/check-config-paths.py`

10 unresolved `Config.options.*` paths, all in the vendored widget tree. Expected per that
tool's README — a missing member reads as `undefined` silently. Revisit with
`ii-background-widgets`, which is deferred anyway.

## From auditing `cw-scaffolding`, 2026-09-20

| where | issue | owner |
|---|---|---|
| `modules/common/Config.qml` `interactions.scrolling.fasterTouchpadScroll` | Defaults `false`, and `WheelScrollHandler` gates its own `visible` on it. An invisible `MouseArea` gets no wheel events, so the Android stretch overscroll in `StyledListView`/`StyledFlickable` — verified working when driven — never engages for anyone on a default config. The key reads as a scroll-*speed* preference but is also the on switch for an M3 behaviour DESIGN.md 3.6 asks for unconditionally. | `config-defaults` — **row added 2026-09-20** |
| `modules/common/widgets/StyledListView.qml`, `StyledFlickable.qml` | `boundsBehavior: DragOverBounds` means a drag past the end *translates* the content. 3.6: "Do not translate the content; stretch it." Needs `StopAtBounds` plus feeding the drag overhang into `overscroll`; not a small change. `cw-gestures` established it needs no code of its own — Qt's `Flickable.verticalOvershoot` already reports the overhang — but the 500ms `Behavior on overscroll` will fight a live drag, so it wants a measured session. | `cw-overscroll` — **row added 2026-09-20** |
| `modules/common/widgets/animations/PlaceholderOpeningAnimation.qml` | Its `PropertyAnimation` writes `iconWidget.rotation`, which destroys `PagePlaceholder`'s own `rotation: shown ? 0 : -70` binding on first trigger (2.9, 10.4). After one trigger, `shown` no longer rotates the icon. Also 250/350/400ms and three `Easing.OutCubic` hand-fits. | `cw-motion` — **fixed 2026-09-20**, it animates its own `iconRotationOffset` and `PagePlaceholder` composes it in |
| `modules/settings/QuickConfig.qml:218` | `Appearance.font.pixelSize.body` does not exist — the ladder is smallest/smaller/smallie/small/normal/large/larger/huge/hugeass/title — so it reads `undefined`: `Unable to assign [undefined] to int`. | `settings-QuickConfig` |
| `modules/settings/QuickConfig.qml` ~214 | Hand-rolls an empty state ("No favourites yet / Add some from wallpaper selector") out of a symbol and two `StyledText`s. 9 says that is `PagePlaceholder`. The chip grid in the same section is also clipped mid-row — visible in `.audit/cw-scaffolding/shot-before.png`, pre-existing. | `settings-QuickConfig` |
| `modules/common/widgets/ColorPreviewButton.qml` | Logs `[ColorPreviewButton] Parse error:` with an empty value, repeatedly, on every settings launch. | `cw-buttons` owns `ColorPreviewButton` per `families.md` — still open, that row ran before this was traced |

## From the twelve parallel `cw-*` sessions, 2026-09-20

The shared-widget tranche ran as twelve sessions at once, each fenced to its own family's
files. Anything a family found outside its fence was reported instead of applied. What was
*caused by* a family's change is in commit `92004dec5`; what follows is pre-existing, and
each line is owned by a row that has not run yet.

| where | issue | owner |
|---|---|---|
| `modules/ii/background/widgets/media/ExpressiveMediaWidget.qml:241` | `Unable to assign [undefined] to bool` — same class as the 334/344/390/410/453 lines above, seen on the 2026-09-20 smoke run with a player active | `ii-background-widgets` |
| 21 effects nested in repeated delegates | Enumerated in `tools/check-effect-budget.py`'s `KNOWN` set, which fails on a *new* one. Worst: `background/widgets/bluetooth/BluetoothFillCardsWidget.qml` puts a whole `StyledDropShadow` — a live gaussian — inside a `Repeater` delegate beside a `layer.enabled`/`OpacityMask` pair; `background/widgets/DateWidget/CalendarAgendaWidget.qml` instantiates a raw Qt5Compat `DropShadow` in a delegate instead of the shared widget. §8/§10.11 | each delegate's own row |
| `ColorOverlay` → `Colorizer` | `Colorizer` never worked (it set `colorization: 1` and never `colorizationColor`, whose `MultiEffect` default is opaque red) and now does, so the 9 live `ColorOverlay` sites can migrate: `CustomIcon`, `MediaWidget`, `BluetoothEarbudsStemWidget` (×4), `SysTrayItem`, `Workspaces`, `DockIcon`. Per-surface judgement, **not** a bulk rename — `ColorOverlay` blends, `Colorizer` flattens to one tone | each caller's own row |
| `StyledDropShadow` → `StyledRectangularShadow` | For the subset whose target is a plain rounded `Rectangle` (`PhotoWidget`, `Photo1x1Widget`, `OnScreenDisplay`, the pill widgets) this trades a live gaussian for an analytic cached shadow. ~20 caller edits. Both wrappers are deliberately kept — see `cw-effects` notes | each caller's own row |
| `modules/settings/widgets/BarLayoutConfig.qml`, `LauncherResultsConfig.qml` | Assign properties `ConfigListView` does not declare (`availableComponents` in both; `addButtonText`, `infoProvider`, `normalizeEntry` in the latter). None ever existed. Assigning a non-existent property is a load error, so both sub-pages should be failing to load today and `ConfigSubPageHost` logging `LOADER_ERROR`. Fixing it is an API decision on `ConfigListView`, not an audit edit | `settings-widgets` |
| `modules/ii/settings/ExtensionConfigPanel.qml:78` | `anchors.left: parent.left` on a `ConfigSwitch` inside a `ColumnLayout`, with the comment "i have no fricking idea why configswitch applies parent margins twice". Anchoring an item a layout manages is Qt-undefined; the anchor fighting the layout is almost certainly the doubled margin | `ii-settings` |
| `modules/ii/overlay/media/MediaContent.qml` | Its `LyricScroller` has no `!hasSyncedLines` fallback, unlike `bar/Media.qml` and `ImmersiveLyricsPane.qml` — the latter uses `PagePlaceholder`, the worked example to copy | `ii-overlay` |
| `modules/ii/bar/Media.qml` | Could drop `LyricsStatic` for `LyricLine` (the closer building block — `Lyrics` is a 7-line stack sized for a 250px background widget). `LyricsStatic` was deliberately **not** deleted, so nothing is broken; exact snippet in `.audit/cw-media/notes.md`. Note `LyricLine` does not call `initiliazeLyrics()` itself | `ii-bar-root` |
| `modules/common/widgets/WidgetCanvas.qml:48` | qmllint `[unqualified]` on the outer `root` id inside the `dotGrid` nested `Canvas`, wanting `pragma ComponentBehavior: Bound`. Deliberately not added: that structure carries comments about a fixed ~20k dots/frame lock-animation regression, and the pragma cannot be cleared without a 60fps measurement | a session that can run the shell |
| `modules/common/widgets/CustomBatteryMeter.qml` | `isCritical` is wired end to end from `Battery.isCritical` through `BarConfig.qml:732`, but nothing in the widget ever reads it — critical and merely-low render pixel-identical. DESIGN.md has no critical-battery recipe, so this was flagged rather than invented | a future battery pass |
| `modules/common/widgets/RippleButton.qml` | Its `StateOverlay` drives `focused` and `press` but **not** `hover`, so every caller wanting a hover film hand-mixes one — `ToolbarTabButton` and `IconToolbarButton` both ship a 0.05 tint where the token is 0.08. 261 files set a hover colour and 36 a pressed one, so this is a rule-9 decision, not a cleanup | a `cw-buttons` revisit |
| `modules/common/widgets/WindowDialogSlider.qml` | Zero callers. `cw-inputs` owned the file but deferred the delete to `cw-dialogs`, who did not own it, so it fell between the two. Nothing breaks; a dead widget survives | a later shared-widget pass |
| The `ArrowPopup` enter/exit recipe | Now transcribed in four separate files. A `Transition`-rooted `ArrowPopupEnter`/`Exit` would collapse the library's most-copied 40 lines. Recorded, not filled — the tranche brief forbids adding widgets | a later shared-widget pass |

### Resolved while auditing, recorded so it is not re-investigated

- **`Material.*` attached properties are inert shell-wide.** All four entry points
  (`shell.qml`, `settings.qml`, `welcome.qml`, `killDialog.qml`) set
  `//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic`, under which `Material.accent` and
  friends do nothing. `StyledIndeterminateProgressBar` had been painting Qt's
  `palette.dark`/`palette.midlight` greys in two dialogs and the wallpaper selector.
  `check-design.py` cannot see this — the violation lives in Qt's own file. A repo-wide
  grep after the fix finds **no remaining users** outside `user_widgets/`, so this is
  closed, not a queue row.
- **The checker's exported-knob blind spot has now hit its third instance**
  (`CircularProgress.animationDuration`, `StyledText`'s `duration: 300 / 2`, and
  `AnimatedTabIndexPair.idx1Duration`). `.audit/common-widgets/notes.md` set "a third
  shape turns up" as the trigger to tighten `check-design.py`'s `duration:` regex to
  `[\d\s+\-*/().]+` and add a rule for a `property` whose name ends in `Duration` or
  `Curve` inside `modules/common/widgets`. All three instances are now fixed at source,
  so the tightening is prophylactic — but the trigger has fired.

## From the vision pass over the tranche's after-shots, 2026-09-20

`gemini-3.1-pro-high` via agy, per AUDIT.md step 6. Full result and the false-positive
tally in `.audit/common-widgets/vision.md` — one genuine defect out of thirteen claims,
so verify anything else that pass produced before acting on it.

| where | issue | owner |
|---|---|---|
| `modules/ii/bar/Spacebar.qml`, `modules/ii/bar/SysTray.qml` | The bar paints **vertical separator bars** — `Spacebar` draws a pipe in `colOutlineVariant` (its comment: "Matches DockSeparator.qml"), and `SysTray` ships `showSeparator: true`. Design law 11 and DESIGN.md §5.5 forbid separator lines outright; sections separate by whitespace on the 4dp grid and layer cards. Instantiated via `BarComponent.qml`. Confirmed in the pixels and the source | `ii-bar-root` |
| `modules/ii/dock/widgets/SectionSeparator.qml` | The dock's copy of the same shape, which is what `Spacebar`'s comment points at | `ii-dock` |
| `tools/check-design.py` `no-separator-bars` | **Blind spot.** The rule matches `WindowDialogSeparator` by *name*, so a separator class called `Spacebar`, `DockSeparator` or `SectionSeparator` passes it silently — which is how the two rows above survived every automated gate. Worth widening to a thin-`Rectangle`-in-`colOutlineVariant` shape check when either row above is worked, rather than adding names one at a time | whichever row fixes the two above |
