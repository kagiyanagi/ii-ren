# Audit queue

One row per surface. Hand-edited — edit it directly to reorder, skip, or move a row
between lanes; the next session reads it as-is. Generated once by the setup session,
never regenerated. Protocol: `.github/AUDIT.md`.

Lane 1 = Claude end to end. Lane 2 = Claude brief, Sonnet-via-agy builds, Claude reviews.
Status: `todo` → `briefed` → `built` → `done`. Put the date in `done` when it lands.

`common-widgets` was a tranche and is now split into the fifteen `cw-*` rows below, one
session each — see `.audit/common-widgets/families.md` for membership and
`.audit/common-widgets/brief.md`, which is the brief for all fifteen. `settings-widgets`
is still a tranche (191 files) and splits the same way when reached, per the 2,500-line
rule in AUDIT.md.

The `cw-*` rows run in the order listed: `cw-buttons` first because fourteen library
widgets are rooted in `RippleButton`, then by caller count.

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
| `settings-widgets` | `modules/settings/widgets` | shared-widgets | 1 | 191 | 35432 | ? | todo | | settings widget library |
| `cw-overscroll` | `modules/common/widgets` | shared-widgets | 1 | 3 | 0 | any list or flickable | todo | | split out of `cw-gestures`: `StopAtBounds` + feed `verticalOvershoot` into `overscroll` in `StyledListView`/`StyledFlickable`. Needs a 60fps harness — the existing 500ms `Behavior on overscroll` will fight a live drag, and `WheelScrollHandler` is invisible on a default config (see `cw-gestures`/`cw-scaffolding` notes) |
| `config-defaults` | `modules/common/Config.qml` | common | 1 | 1 | 0 | n/a | todo | | no row owned `interactions.scrolling`. `fasterTouchpadScroll` defaults false and gates `WheelScrollHandler.visible`, so the M3 stretch overscroll is dead for everyone. Reads as a speed preference, is actually an on switch |
| `services-Ai` | `services/Ai.qml` | services | 2 | 1 | 0 | n/a | todo | | `Ai.qml:396` `TypeError: Property 'addUserModels' of object Ai is not a function` on every boot. First row in a `services` cluster that did not exist |
| `ii-altTab` | `modules/ii/altTab` | ii | 2 | 1 | 243 | `ipc call altTab` | todo | |  |
| `ii-background-widgets` | `modules/ii/background/widgets` | background | 2 | 122 | 27746 | ? | todo | | **deferred — vendored, see re-port hazard** |
| `ii-background-root` | `modules/ii/background/*.qml` | background | 2 | 3 | 1437 | ? | todo | | top-level files only |
| `ii-bar-cards` | `modules/ii/bar/cards` | bar | 1 | 14 | 3204 | ? | todo | |  |
| `ii-bar-weather` | `modules/ii/bar/weather` | bar | 1 | 2 | 385 | ? | todo | |  |
| `ii-bar-root` | `modules/ii/bar/*.qml` | bar | 1 | 36 | 9541 | `ipc call bar` | todo | | top-level files only |
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
