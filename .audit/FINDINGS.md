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

## From auditing `ii-clipboardToast`, 2026-09-20

| where | issue | owner |
|---|---|---|
| `modules/common/widgets/RippleButton.qml` | Renders hover, pressed and disabled but no focus state. `Button.visualFocus` is never read, so DESIGN.md 3.1's four states are three on every caller. Harmless on a layer surface with `keyboardFocus: None`; not harmless in the settings app. | `cw-buttons` |

## From `tools/p3-widget-port/check-config-paths.py`

10 unresolved `Config.options.*` paths, all in the vendored widget tree. Expected per that
tool's README — a missing member reads as `undefined` silently. Revisit with
`ii-background-widgets`, which is deferred anyway.
