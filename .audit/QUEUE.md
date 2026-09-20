# Audit queue

One row per surface. Hand-edited — edit it directly to reorder, skip, or move a row
between lanes; the next session reads it as-is. Generated once by the setup session,
never regenerated. Protocol: `.github/AUDIT.md`.

Lane 1 = Claude end to end. Lane 2 = Claude brief, Sonnet-via-agy builds, Claude reviews.
Status: `todo` → `briefed` → `built` → `done`. Put the date in `done` when it lands.

`common-widgets` was a tranche and is now split into the fifteen `cw-*` rows below, one
session each — see `.audit/common-widgets/families.md` for membership and
`.audit/common-widgets/brief.md`, which is the brief for all fifteen. `settings-widgets`
was the other tranche and is now the ten `sw-*` rows, split the same way — but 120 of its
190 files are reached by nothing at all, so the first of those rows deletes 25.5k lines
rather than designing them. `.audit/settings-widgets/families.md` has the evidence.

The `cw-*` rows run in the order listed: `cw-buttons` first because fourteen library
widgets are rooted in `RippleButton`, then by caller count.

`ii-bar-root` was a 36-file / 9,535-line row, which is nearly four times the 2,500-line
split rule, so it is now the five `ii-bar-chrome` / `ii-bar-widgets` / `ii-bar-tray` /
`ii-bar-popups` / `ii-bar-resources` rows, cut by widget group exactly as the unit-of-work
table in `AUDIT.md` said it would be. Those five plus `ii-bar-cards` and `ii-bar-weather`
share one brief — `.audit/ii-bar/brief.md` — because the bar and its hover popups are one
surface family; each row's own `brief.md` is the slice. They ran as seven parallel
sessions behind the same four fences the `cw-*` and `sw-*` rows used, with two extra: the
popup shell (`StyledPopup`) and the card kit are frozen-API for every row that does not
own them, and no session may run `tools/audit/smoke.sh`, which `pkill`s every quickshell
on the machine.

The `sw-*` rows have exactly two orderings that matter: `sw-dead` first, so every later
pack is generated from 70 files rather than 190, and `sw-clock-configs` second, because it
is what puts the page header on `ContentPage`. The remaining eight are independent — their
file sets are disjoint and `sw-clock-configs` measured that a page which has not adopted
the header yet is not broken by one that has — so they ran as eight parallel sessions,
fenced the same way the twelve `cw-*` rows were.

| id | path | cluster | lane | files | lines | open with | status | done | notes |
|---|---|---|---:|---:|---:|---|---|---|---|
| `common-widgets` | `modules/common/widgets` | shared-widgets | 1 | 169 | 14176 | n/a | done | 2026-09-20 | tranche split only, no QML changed — see `families.md`, `brief.md`, `notes.md` |
| `cw-buttons` | `modules/common/widgets` | shared-widgets | 1 | 21 | 1471 | `qs -p ~/.config/quickshell/ii/settings.qml` · any `RippleButton` caller | done | 2026-09-20 | focus + pressed at the root; `check-button-states.py`. See `notes.md` before changing a state default |
| `cw-primitives` | `modules/common/widgets` | shared-widgets | 1 | 18 | 1017 | everywhere | done | 2026-09-20 | `StyledText` elides, `MaterialSymbol` must not; `check-text-primitives.py`. See `notes.md` — 8 `spatial-on-effects` hits left for other rows |
| `cw-scaffolding` | `modules/common/widgets` | shared-widgets | 1 | 14 | 1044 | `qs -p ~/.config/quickshell/ii/settings.qml` | done | 2026-09-20 | header states + keyboard; `check-scaffold-containers.py`. See `notes.md` — the overscroll stretch is gated off by default, and the expand/collapse still snaps |
| `cw-config-rows` | `modules/common/widgets` | shared-widgets | 1 | 12 | 1517 | `qs -p ~/.config/quickshell/ii/settings.qml` | done | 2026-09-20 | `ConfigTextField` had no focus state at all; `ConfigSwitch` dimmed twice. `check-config-row-cards.py` |
| `cw-inputs` | `modules/common/widgets` | shared-widgets | 1 | 16 | 1648 | `qs -p ~/.config/quickshell/ii/settings.qml` | done | 2026-09-20 | none of the 7 value controls rendered focus; combo popups highlighted nothing under arrow keys. `check-input-states.py` |
| `cw-navigation` | `modules/common/widgets` | shared-widgets | 1 | 13 | 830 | `qs -p ~/.config/quickshell/ii/settings.qml` | done | 2026-09-20 | `TabButton` roots sat outside `check-button-states.py`'s net. `check-navigation-widgets.py`. See notes before retiming the indicator |
| `cw-dialogs` | `modules/common/widgets` | shared-widgets | 1 | 14 | 929 | `ipc call session`, hotspot/bluetooth dialogs | done | 2026-09-20 | deleted `WindowDialogSeparator`; sharp mode had zeroed all dialog padding. `check-dialog-surfaces.py` |
| `cw-progress` | `modules/common/widgets` | shared-widgets | 1 | 13 | 1060 | `ipc call osdVolume`, bar cards | done | 2026-09-20 | both duration/easing knobs had zero callers and died; the indeterminate bar was painting Qt's greys. `check-progress-indicators.py` |
| `cw-notifications` | `modules/common/widgets` | shared-widgets | 1 | 6 | 612 | `notify-send test` | done | 2026-09-20 | groups snapped open and animated shut. `check-notification-expansion.py`. See notes before swapping the OpacityMask pairs |
| `cw-effects` | `modules/common/widgets` | shared-widgets | 1 | 8 | 234 | wallpaper + any shadowed surface | done | 2026-09-20 | `samples` off `radius` recompiled the blur shader every dock hover; kept both shadow wrappers. `check-effect-budget.py` |
| `cw-media` | `modules/common/widgets` | shared-widgets | 2 | 8 | 1007 | `ipc call mediaControls` | done | 2026-09-20 | `Lyrics` was coded against a `LyricsService` API that does not exist. `Player`/`PlayerControls*` have zero callers |
| `cw-motion` | `modules/common/widgets` | shared-widgets | 2 | 15 | 858 | wallpaper switch, `ipc call wallpaperSelector` | done | 2026-09-20 | defaults tokenised, parameters kept; fixed the `PagePlaceholder` rotation clobber. `check-motion-defaults.py` |
| `cw-gestures` | `modules/common/widgets` | shared-widgets | 2 | 6 | 446 | `wl-copy x`, notification swipe | done | 2026-09-20 | loosened the owner coupling behind a `hasSharedDragState` guard. `check-swipe-dismissible.py`. See notes — overscroll split out to its own row |
| `cw-misc` | `modules/common/widgets` | shared-widgets | 2 | 4 | 463 | `ipc call sidebarRight` | done | 2026-09-20 | `AttachedFileIndicator.scale` shadowed `Item.scale`; `CalendarView` imported waffle's look system |
| `cw-battery` | `modules/common/widgets` | shared-widgets | 2 | 1 | 1040 | `ipc call bar` | done | 2026-09-20 | the brief's hex/duration claims were wrong — the real fix was `m3colors.m3error` → `colors.colError` |
| `settings-widgets` | `modules/settings/widgets` | shared-widgets | 1 | 190 | 35099 | n/a | done | 2026-09-20 | tranche split only, no QML changed — 120 of 190 files are reached by nothing; see `families.md`, `brief.md`, `notes.md` |
| `sw-dead` | `modules/settings/widgets` + `configs/widgets` | settings | 1 | 122 | 25531 | `qs -p ~/.config/quickshell/ii/settings.qml` | done | 2026-09-20 | `dead.txt` regenerated first and came back identical. 122 files / 25,531 lines, the qmldir and one live import line. 70 files left |
| `sw-clock-configs` | `modules/settings/widgets` | settings | 1 | 6 | 1970 | `qs -p ~/.config/quickshell/ii/settings.qml` → Widgets → a clock widget's cog | done | 2026-09-20 | `ContentPage` now carries `title`/`showBackButton`/`goBack()` and the header. New gate `tools/audit/probe-settings-pages.sh` instantiates all 61 sub-pages; `check-scaffold-containers.py` section 6. See `notes.md` |
| `sw-clock-styles` | `modules/settings/widgets` | settings | 2 | 12 | 1228 | `qs -p ~/.config/quickshell/ii/settings.qml` → Widgets → a clock widget's cog | done | 2026-09-20 | twelve clones made to agree; names now come from `WidgetsRegistry`. `DesktopWordClockConfig` had 11 untranslated strings and its own switch on the global shadow key |
| `sw-weather-calendar` | `modules/settings/widgets` | settings | 2 | 15 | 1198 | `qs -p ~/.config/quickshell/ii/settings.qml` → Widgets → a weather or calendar widget's cog | done | 2026-09-20 | 13 of 15 configure nothing about their own widget — placeholder + the shared block only. The brief's units-first call was vacuous; both options live in `ServicesConfig` |
| `sw-media-configs` | `modules/settings/widgets` | settings | 2 | 7 | 944 | `qs -p ~/.config/quickshell/ii/settings.qml` → Widgets → a media widget's cog | done | 2026-09-20 | five switches bound to keys no widget reads; the dead shadow switch replaced by `DesktopWidgetVisualOptions`, which writes the key the widget does read |
| `sw-system-pills` | `modules/settings/widgets` | settings | 2 | 11 | 969 | `qs -p ~/.config/quickshell/ii/settings.qml` → Widgets → a cpu/ram/disk/battery widget's cog | done | 2026-09-20 | no row on any of these pages was carded — `ContentGroup` does not reach through the gating wrapper. Worked around with `ContentSubsection`; the real fix is a `cw-scaffolding` revisit |
| `sw-desktop-misc` | `modules/settings/widgets` | settings | 2 | 11 | 1353 | `qs -p ~/.config/quickshell/ii/settings.qml` → Widgets → notes/quote/photo/notification widget's cog | done | 2026-09-20 | both photo pages still carried the pre-extraction copy-paste, so one global option was reachable from one of them and not the other |
| `sw-fingerprint` | `modules/settings/widgets` | settings | 2 | 3 | 966 | `qs -p ~/.config/quickshell/ii/settings.qml` → Lock → Fingerprint | done | 2026-09-20 | four enrolment states where there were two; ring is `CircularProgress` now, which brings the tranche's only `layer.enabled` — deliberate, see `notes.md`. Retry is derived because the bridge discards it |
| `sw-extensions` | `modules/settings/widgets` | settings | 2 | 3 | 865 | `qs -p ~/.config/quickshell/ii/settings.qml` → Widgets → Extensions / Community | done | 2026-09-20 | the settings overlay could not render a text option; `probe-settings-pages.sh` gained the three Widgets-tab files because nothing instantiated them |
| `sw-advanced-pages` | `modules/settings/widgets` | settings | 2 | 2 | 535 | `qs -p ~/.config/quickshell/ii/settings.qml` → Advanced → Themed icons / Custom cursor | done | 2026-09-20 | the icons page picked but never applied. Preview is the primary element now; the apply button and its 2s toast are gone |
| `cw-overscroll` | `modules/common/widgets` | shared-widgets | 1 | 3 | 0 | any list or flickable | done | 2026-09-20 | **superseded — the stretch was removed the same day** (`DECISIONS.md` 24): glitchy on a real desktop at both anchors. Qt's `DragOverBounds` rubber-band is what a drag past the end does now |
| `config-defaults` | `modules/common/Config.qml` | common | 1 | 1 | 0 | n/a | done | 2026-09-20 | resolved without touching the default: the handler no longer gates `visible` on `fasterTouchpadScroll`, so the key means only what its name says and the stretch is unconditional |
| `services-Ai` | `services/Ai.qml` | services | 2 | 1 | 0 | n/a | done | 2026-09-20 | the `addUserModels()` call went — the two config-fed model lists are bindings. Boot is clean of it |
| `ii-altTab` | `modules/ii/altTab` | ii | 1 | 1 | 243 | `ipc call altTab` | done | 2026-09-21 | ran lane 1, not 2. The card now waits 150ms before it draws anything, which is what let every invented number go; tiles wrap into a balanced `Grid` (`check-alttab-grid.py`). See `notes.md` before driving it — `currentWorkspaceOnly` is `true` on this machine |
| `ii-background-widgets` | `modules/ii/background/widgets` | background | 2 | 122 | 27746 | ? | skip | 2026-09-20 | **out permanently** — vendored and rsynced with `--delete`; decided in `DECISIONS.md` 3 and `AUDIT.md`'s re-port hazard |
| `ii-background-root` | `modules/ii/background/*.qml` | background | 2 | 3 | 1437 | always on screen; `hyprctl dispatch 'hl.dsp.focus({ workspace = 9 })'` for a bare one | done | 2026-09-21 | ran lane 1, not 2. Parallax was NaN whenever every window sat in one workspace chunk, and the wallpaper plane ran on different timings from the widget canvas over it (`check-desktop-parallax.py`). Seven dead properties gone. **Still frames prove nothing here** — see `notes.md` for the 60fps list and for two findings left to `ii-overview` and the re-port |
| `ii-bar-cards` | `modules/ii/bar/cards` | bar | 1 | 14 | 3204 | hover any bar item with a popup | done | 2026-09-21 | the kit every bar popup composes. `WorldClocksCard` was the cluster's one law-8 breach; `ClockHeaderCard` ran four effects for a glow on one corner. `SectionCard.showDivider` deleted. `check-bar-cards.py` |
| `ii-bar-weather` | `modules/ii/bar/weather` | bar | 1 | 2 | 385 | hover the weather widget | done | 2026-09-21 | `Weather.data` ships a complete placeholder, so `?? "--°"` could never fire and the popup stated four wrong numbers. Loading/error/no-city states added; `check-weather-hourly.py` |
| `ii-bar-chrome` | `modules/ii/bar/*.qml` | bar | 1 | 6 | 971 | `ipc call bar` | done | 2026-09-21 | `ii-bar-root` split 1/5. The bar entered and left on one effects spec; `root.vertical` resolved to BarContent and silently read undefined. `check-bar-reveal.py` |
| `ii-bar-widgets` | `modules/ii/bar/*.qml` | bar | 1 | 16 | 2287 | `ipc call bar` | done | 2026-09-21 | `ii-bar-root` split 2/5. The workspace indicator summed raw child indices while its width counted visible ones. `NetworkSpeed` destroyed its own `visible` binding and wrote `displayMode` into the user config. `check-workspace-indicator.py` |
| `ii-bar-tray` | `modules/ii/bar/*.qml` | bar | 1 | 7 | 1259 | hover or click a tray icon | done | 2026-09-21 | `ii-bar-root` split 3/5. Monochrome icons cost two shader passes each, on the default config. Menu got the `arrowPopup*` motion and keyboard. `check-systray-menu-origin.py` |
| `ii-bar-popups` | `modules/ii/bar/*.qml` | bar | 1 | 5 | 2286 | hover the battery / clock / media / network widget | done | 2026-09-21 | `ii-bar-root` split 4/5. Owns `StyledPopup`: ~90 lines computed a stagger for an empty function. BatteryPopup 901 → 331. `check-popup-pivot.py`. See `notes.md` before re-porting |
| `ii-bar-resources` | `modules/ii/bar/*.qml` | bar | 1 | 2 | 2732 | hover the resources widget | done | 2026-09-21 | `ii-bar-root` split 5/5. 2,020 → 658: three meters were one meter written three times. All five OpacityMasks removed — two were load-bearing and the check script caught it. `check-resources-popup.py` |
| `ii-cheatsheet` | `modules/ii/cheatsheet` | ii | 2 | 6 | 1122 | `ipc call cheatsheet` | todo | |  |
| `ii-clipboardToast` | `modules/ii/clipboardToast` | ii | 1 | 1 | 497 | `wl-copy "text-$RANDOM"` | done | 2026-09-20 | pilot; ran lane 1 end to end. See notes.md before driving it |
| `ii-desktopMenu` | `modules/ii/desktopMenu` | ii | 2 | 2 | 843 | `ipc call desktopMenu` | todo | |  |
| `ii-dock` | `modules/ii/dock` | ii | 1 | 23 | 3860 | ? | todo | |  |
| `ii-dropover` | `modules/ii/dropover` | ii | 2 | 3 | 339 | `ipc call dropShelf` | todo | |  |
| `ii-fastPair` | `modules/ii/fastPair` | ii | 2 | 1 | 307 | ? | todo | |  |
| `ii-immersiveMedia` | `modules/ii/immersiveMedia` | ii | 2 | 5 | 1025 | `ipc call immersiveMedia` | todo | |  |
| `ii-keypressDisplay` | `modules/ii/keypressDisplay` | ii | 2 | 1 | 176 | ? | todo | |  |
| `ii-lock` | `modules/ii/lock` | ii | 2 | 3 | 915 | ? | todo | |  |
| `ii-mediaControls` | `modules/ii/mediaControls` | ii | 1 | 3 | 1278 | `ipc call mediaControls` | todo | |  |
| `ii-notificationPopup` | `modules/ii/notificationPopup` | ii | 1 | 1 | 76 | ? | todo | |  |
| `ii-onScreenDisplay` | `modules/ii/onScreenDisplay` | ii | 1 | 17 | 3451 | `ipc call osdVolume` | todo | |  |
| `ii-onScreenKeyboard` | `modules/ii/onScreenKeyboard` | ii | 2 | 3 | 338 | `ipc call osk` | todo | |  |
| `ii-overlay` | `modules/ii/overlay` | ii | 2 | 21 | 2532 | `ipc call overlay` | todo | |  |
| `ii-overview` | `modules/ii/overview` | ii | 1 | 7 | 2324 | `ipc call search` | todo | |  |
| `ii-polkit` | `modules/ii/polkit` | ii | 2 | 2 | 121 | ? | todo | |  |
| `ii-regionSelector` | `modules/ii/regionSelector` | ii | 2 | 9 | 1476 | `ipc call region` | todo | |  |
| `ii-screenCorners` | `modules/ii/screenCorners` | ii | 2 | 1 | 172 | ? | todo | |  |
| `ii-screenTranslator` | `modules/ii/screenTranslator` | ii | 2 | 3 | 526 | `ipc call screenTranslator` | todo | |  |
| `ii-sessionScreen` | `modules/ii/sessionScreen` | ii | 2 | 2 | 398 | `ipc call session` | todo | |  |
| `ii-settings` | `modules/ii/settings` | ii | 2 | 6 | 864 | ? | todo | |  |
| `ii-sidebarDashboard-bluetoothDevices` | `modules/ii/sidebarDashboard/bluetoothDevices` | sidebarDashboard | 1 | 2 | 194 | ? | todo | |  |
| `ii-sidebarDashboard-calendar` | `modules/ii/sidebarDashboard/calendar` | sidebarDashboard | 1 | 4 | 370 | ? | todo | |  |
| `ii-sidebarDashboard-hotspot` | `modules/ii/sidebarDashboard/hotspot` | sidebarDashboard | 1 | 1 | 309 | ? | todo | |  |
| `ii-sidebarDashboard-nightLight` | `modules/ii/sidebarDashboard/nightLight` | sidebarDashboard | 1 | 1 | 228 | ? | todo | |  |
| `ii-sidebarDashboard-notifications` | `modules/ii/sidebarDashboard/notifications` | sidebarDashboard | 1 | 1 | 74 | ? | todo | |  |
| `ii-sidebarDashboard-pomodoro` | `modules/ii/sidebarDashboard/pomodoro` | sidebarDashboard | 1 | 3 | 373 | ? | todo | |  |
| `ii-sidebarDashboard-quickToggles` | `modules/ii/sidebarDashboard/quickToggles` | sidebarDashboard | 1 | 47 | 4723 | ? | todo | |  |
| `ii-sidebarDashboard-todo` | `modules/ii/sidebarDashboard/todo` | sidebarDashboard | 1 | 3 | 367 | ? | todo | |  |
| `ii-sidebarDashboard-volumeMixer` | `modules/ii/sidebarDashboard/volumeMixer` | sidebarDashboard | 1 | 3 | 233 | ? | todo | |  |
| `ii-sidebarDashboard-wifiNetworks` | `modules/ii/sidebarDashboard/wifiNetworks` | sidebarDashboard | 1 | 2 | 181 | ? | todo | |  |
| `ii-sidebarDashboard-root` | `modules/ii/sidebarDashboard/*.qml` | sidebarDashboard | 1 | 5 | 1019 | `ipc call sidebarRight` | todo | | top-level files only |
| `ii-sidebarPolicies-aiChat` | `modules/ii/sidebarPolicies/aiChat` | sidebarPolicies | 1 | 8 | 1430 | ? | todo | |  |
| `ii-sidebarPolicies-anime` | `modules/ii/sidebarPolicies/anime` | sidebarPolicies | 1 | 2 | 465 | ? | todo | |  |
| `ii-sidebarPolicies-continuity` | `modules/ii/sidebarPolicies/continuity` | sidebarPolicies | 1 | 2 | 339 | ? | todo | |  |
| `ii-sidebarPolicies-hermes` | `modules/ii/sidebarPolicies/hermes` | sidebarPolicies | 1 | 14 | 4504 | ? | todo | |  |
| `ii-sidebarPolicies-translator` | `modules/ii/sidebarPolicies/translator` | sidebarPolicies | 1 | 2 | 126 | ? | todo | |  |
| `ii-sidebarPolicies-root` | `modules/ii/sidebarPolicies/*.qml` | sidebarPolicies | 1 | 13 | 4416 | `ipc call sidebarLeft` | todo | | top-level files only |
| `ii-topLayer` | `modules/ii/topLayer` | ii | 2 | 20 | 1859 | ? | todo | |  |
| `ii-verticalBar` | `modules/ii/verticalBar` | ii | 1 | 9 | 1046 | `ipc call bar` | todo | |  |
| `ii-wallpaperSelector` | `modules/ii/wallpaperSelector` | ii | 2 | 6 | 1292 | `ipc call wallpaperSelector` | todo | |  |
| `ii-wrappedFrame` | `modules/ii/wrappedFrame` | ii | 2 | 1 | 177 | ? | todo | |  |
| `waffle-actionCenter` | `modules/waffle/actionCenter` | waffle | 2 | 21 | 1942 | `ipc call sidebarLeft` | todo | |  |
| `waffle-background` | `modules/waffle/background` | waffle | 2 | 1 | 47 | ? | todo | |  |
| `waffle-bar` | `modules/waffle/bar` | waffle | 1 | 22 | 1658 | `ipc call bar` | todo | |  |
| `waffle-lock` | `modules/waffle/lock` | waffle | 2 | 1 | 373 | ? | todo | |  |
| `waffle-looks` | `modules/waffle/looks` | waffle | 2 | 48 | 2400 | ? | todo | |  |
| `waffle-notificationCenter` | `modules/waffle/notificationCenter` | waffle | 2 | 13 | 1097 | `ipc call sidebarRight` | todo | |  |
| `waffle-notificationPopup` | `modules/waffle/notificationPopup` | waffle | 1 | 1 | 75 | ? | todo | |  |
| `waffle-onScreenDisplay` | `modules/waffle/onScreenDisplay` | waffle | 1 | 4 | 274 | `ipc call osd` | todo | |  |
| `waffle-polkit` | `modules/waffle/polkit` | waffle | 2 | 2 | 225 | ? | todo | |  |
| `waffle-screenSnip` | `modules/waffle/screenSnip` | waffle | 2 | 3 | 562 | `ipc call region` | todo | |  |
| `waffle-sessionScreen` | `modules/waffle/sessionScreen` | waffle | 2 | 4 | 390 | `ipc call session` | todo | |  |
| `waffle-startMenu` | `modules/waffle/startMenu` | waffle | 2 | 17 | 1896 | `ipc call search` | todo | |  |
| `waffle-taskView` | `modules/waffle/taskView` | waffle | 2 | 4 | 714 | `ipc call search` | todo | |  |
| `settings-About` | `modules/settings/About.qml` | settings | 2 | 1 | 309 | ? | todo | |  |
| `settings-AdvancedConfig` | `modules/settings/AdvancedConfig.qml` | settings | 2 | 1 | 425 | ? | todo | |  |
| `settings-BackgroundConfig` | `modules/settings/BackgroundConfig.qml` | settings | 2 | 1 | 1156 | ? | todo | |  |
| `settings-BarConfig` | `modules/settings/BarConfig.qml` | settings | 2 | 1 | 1273 | ? | todo | |  |
| `settings-EasterEggWindow` | `modules/settings/EasterEggWindow.qml` | settings | 2 | 1 | 376 | ? | todo | |  |
| `settings-ExtensionsConfig` | `modules/settings/ExtensionsConfig.qml` | settings | 2 | 1 | 207 | ? | todo | |  |
| `settings-GeneralConfig` | `modules/settings/GeneralConfig.qml` | settings | 2 | 1 | 765 | ? | todo | |  |
| `settings-HermesConfig` | `modules/settings/HermesConfig.qml` | settings | 2 | 1 | 792 | ? | todo | |  |
| `settings-HyprlandConfig` | `modules/settings/HyprlandConfig.qml` | settings | 2 | 1 | 422 | ? | todo | |  |
| `settings-InterfaceConfig` | `modules/settings/InterfaceConfig.qml` | settings | 2 | 1 | 1730 | ? | todo | |  |
| `settings-LockConfig` | `modules/settings/LockConfig.qml` | settings | 2 | 1 | 188 | ? | todo | |  |
| `settings-QuickConfig` | `modules/settings/QuickConfig.qml` | settings | 2 | 1 | 659 | ? | todo | |  |
| `settings-ServicesConfig` | `modules/settings/ServicesConfig.qml` | settings | 2 | 1 | 1043 | ? | todo | |  |
| `settings-WallpaperEffectPreview` | `modules/settings/WallpaperEffectPreview.qml` | settings | 2 | 1 | 72 | ? | todo | |  |
| `settings-WidgetsConfig` | `modules/settings/WidgetsConfig.qml` | settings | 2 | 1 | 1091 | ? | todo | |  |
