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
| `services/Ai.qml:396` | `TypeError: Property 'addUserModels' of object Ai is not a function` | `services` — no queue row yet, add one |

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
| `modules/common/Config.qml` `interactions.scrolling.fasterTouchpadScroll` | Defaults `false`, and `WheelScrollHandler` gates its own `visible` on it. An invisible `MouseArea` gets no wheel events, so the Android stretch overscroll in `StyledListView`/`StyledFlickable` — verified working when driven — never engages for anyone on a default config. The key reads as a scroll-*speed* preference but is also the on switch for an M3 behaviour DESIGN.md 3.6 asks for unconditionally. | config defaults — **no queue row owns `interactions.scrolling`**, add one |
| `modules/common/widgets/StyledListView.qml`, `StyledFlickable.qml` | `boundsBehavior: DragOverBounds` means a drag past the end *translates* the content. 3.6: "Do not translate the content; stretch it." Needs `StopAtBounds` plus feeding the drag overhang into `overscroll`; not a small change. | `cw-gestures`, with the drag work |
| `modules/common/widgets/animations/PlaceholderOpeningAnimation.qml` | Its `PropertyAnimation` writes `iconWidget.rotation`, which destroys `PagePlaceholder`'s own `rotation: shown ? 0 : -70` binding on first trigger (2.9, 10.4). After one trigger, `shown` no longer rotates the icon. Also 250/350/400ms and three `Easing.OutCubic` hand-fits. | `cw-motion` |
| `modules/settings/QuickConfig.qml:218` | `Appearance.font.pixelSize.body` does not exist — the ladder is smallest/smaller/smallie/small/normal/large/larger/huge/hugeass/title — so it reads `undefined`: `Unable to assign [undefined] to int`. | `settings-QuickConfig` |
| `modules/settings/QuickConfig.qml` ~214 | Hand-rolls an empty state ("No favourites yet / Add some from wallpaper selector") out of a symbol and two `StyledText`s. 9 says that is `PagePlaceholder`. The chip grid in the same section is also clipped mid-row — visible in `.audit/cw-scaffolding/shot-before.png`, pre-existing. | `settings-QuickConfig` |
| `modules/common/widgets/ColorPreviewButton.qml` | Logs `[ColorPreviewButton] Parse error:` with an empty value, repeatedly, on every settings launch. | whichever `cw-*` row owns it — see `families.md` |
