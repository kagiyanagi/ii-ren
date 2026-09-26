#!/usr/bin/env python3
"""The eye-protection dialog's switches follow their effects, and its sliders do not reload Hyprland per step.

Every row was a `ConfigSwitch`, which runs `checked = !checked` on click and breaks its
`checked:` binding. Worse, each one called its service from `onCheckedChanged`, so when the
binding did update -- automatic Night Light switching on at 19:00 with the dialog open -- the
row called `toggleTemperature(true)` as if it had been clicked, and the schedule became a
manual override. The rows own the state now: the switch is not checkable and the service
is called from `onClicked` only.

Comfort View's and Reading Mode's `applyShader` rewrite a GLSL file and run `hyprctl
reload`. `setIntensity` applied on every integer the slider crossed, and its config write
fired `onIntensityChanged`, which applied again: a drag across the track was ~200 Hyprland
reloads. Both paths go through one debounce now. Measured live: a 47-step drag, 2 reloads.

The status line is evaluated under node, since it is the only place the dialog says that
the schedule has an effect on while its switch is off.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
dialog = (II / "modules/ii/sidebarDashboard/nightLight/NightLightDialog.qml").read_text()

assert not re.search(r"\bConfigSwitch \{", dialog), "NightLightDialog: a ConfigSwitch toggles itself and breaks its checked binding"
assert "onCheckedChanged" not in dialog, "NightLightDialog: onCheckedChanged fires when the binding updates, not just on a click"
switch = re.search(r"StyledSwitch \{(.*?)\n            \}", dialog, re.S)
assert switch, "NightLightDialog: no StyledSwitch in SwitchRow"
assert re.search(r"checkable:\s*false", switch.group(1)), "NightLightDialog: the switch must not be checkable"
assert re.search(r"property string icon\b", dialog) is None, "NightLightDialog: `icon` is FINAL on AbstractButton; overriding it makes the type unavailable"

for name in ("HyprlandComfortView", "HyprlandReadingMode"):
    svc = (II / f"services/{name}.qml").read_text()
    set_fn = re.search(r"function setIntensity\(val\) \{(.*?)\n    \}", svc, re.S)
    assert set_fn and "applyShader" not in set_fn.group(1), f"{name}: setIntensity must not apply directly; a slider drag reloads Hyprland per step"
    assert "applyDebounce.restart()" in set_fn.group(1), f"{name}: setIntensity must go through applyDebounce"
    on_int = re.search(r"function onIntensityChanged\(\) \{(.*?)\n        \}", svc, re.S)
    assert on_int and "applyShader" not in on_int.group(1), f"{name}: onIntensityChanged re-applies on setIntensity's own config write"
    assert re.search(r"id: applyDebounce\s*\n\s*interval: \d+", svc), f"{name}: no applyDebounce Timer"

wifi = (II / "modules/ii/sidebarDashboard/wifiNetworks/WifiDialog.qml").read_text()
height = re.search(r"backgroundHeight:\s*(.+)", dialog)
assert height and height.group(1) == re.search(r"backgroundHeight:\s*(.+)", wifi).group(1), \
    "NightLightDialog: must share the Wi-Fi dialog's screen-scaled height, not a fixed one or its content's"
assert re.search(r"StyledFlickable \{[^}]*Layout\.fillHeight:\s*true", dialog), "NightLightDialog: the body must fill the card and scroll"

sunset = (II / "services/Hyprsunset.qml").read_text()
assert "Hyprland.dispatch(`hyprctl" not in sunset, "Hyprsunset: `hyprctl` is not a dispatcher; that line is a Lua error in this config"

body = re.search(r"function scheduleStatus\(on, automatic\) \{\n(.*?)\n    \}\n", dialog, re.S)
assert body, "NightLightDialog: could not lift scheduleStatus"
row = re.search(r'title: Translation\.tr\("Comfort View"\)\n\s+(?://.*\n\s+)*status: (.*)\n', dialog)
assert row, "NightLightDialog: could not lift Comfort View's status binding"
status = re.sub(r"\broot\.scheduleStatus\b", "scheduleStatus", row.group(1))

JS = """
const tr = s => Object.assign(new String(s), { arg(v) { return tr(this.replace('%%1', v)); } });
const Translation = { tr };
const Hyprsunset = { from: '19:00', to: '06:30' };
function scheduleStatus(on, automatic) { %s }
const cases = %s;
console.log(JSON.stringify(cases.map(HyprlandComfortView => String(%s))));
"""
cases = [
    (dict(manualEnable=True, automatic=False, effectiveActive=True), "On"),
    (dict(manualEnable=True, automatic=True, effectiveActive=True), "On"),
    (dict(manualEnable=False, automatic=True, effectiveActive=True), "On until 06:30"),
    (dict(manualEnable=False, automatic=True, effectiveActive=False), "Turns on at 19:00"),
    (dict(manualEnable=False, automatic=False, effectiveActive=False), "Off"),
]
src = JS % (body.group(1), json.dumps([c for c, _ in cases]), status)
got = json.loads(subprocess.run(["node", "-e", src], capture_output=True, text=True, check=True).stdout)
for (state, want), line in zip(cases, got):
    assert line == want, f"NightLightDialog status: {state} gave {line!r}, want {want!r}"

print(f"ok: switches are not checkable, both intensity paths debounce, and {len(cases)} status lines are right")
