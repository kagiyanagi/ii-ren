#!/usr/bin/env python3
"""The battery acts on the machine only the way its settings say, and the page tells the truth.

services/Battery.qml can suspend, hibernate or power off the laptop, switch its power
profile and turn its screen off, all unattended. None of that is visible until the
battery is nearly empty or the laptop sits idle, so a regression here is found by a
dead battery or a machine that sleeps on its own.

- The critical action maps each choice to its own command. Hibernate falls back to
  suspend: a failed hibernate would otherwise leave nothing between the session and
  an empty battery.
- The battery idle monitors run only on battery, with the option on, and never with a
  zero timeout, which ext-idle-notify reports as idle at once: suspend on every unplug.
- Auto power saver hands back only a profile it took, and only if the user has not
  picked another since.
- The Battery page's charge-limit switch does not toggle itself: it asks UPower and
  shows UPower's answer (TASTE 3.1). Nor does it say "Not supported" in the ~50ms
  before UPower has answered. Every option the page writes exists in Config.

The history maths is modules/settings/batteryHistory.test.js, run here too.
"""
import pathlib, re, subprocess

II = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
battery = (II / "services/Battery.qml").read_text()
page = (II / "modules/settings/BatteryConfig.qml").read_text()
config = (II / "modules/common/Config.qml").read_text()

crit = re.search(r"onIsSuspendingAndNotChargingChanged: \{(.*?)\n    \}", battery, re.S)
assert crit, "Battery: no critical action handler"
body = crit.group(1)
assert '"hibernate" ? "systemctl hibernate || systemctl suspend' in body, "Battery: hibernate must fall back to suspend"
assert '"poweroff" ? "systemctl poweroff' in body, "Battery: poweroff lost its own command"
assert body.rstrip().endswith(': "systemctl suspend || loginctl suspend"]);'), "Battery: anything else must suspend"
assert "if (!root.available || !isSuspendingAndNotCharging) return;" in body, "Battery: the action must wait for the critical level off the charger"
assert re.search(r"isSuspendingAndNotCharging: allowAutomaticSuspend && isSuspending && !isCharging", battery), \
    "Battery: Nothing (automaticSuspend off) must stop the action"

assert re.search(r"batteryIdle: available && UPower\.onBattery && Config\.options\.battery\.idle\.enable", battery), \
    "Battery: the idle monitors must be on battery and opted into"
monitors = re.findall(r"IdleMonitor \{(.*?)\n    \}", battery, re.S)
assert len(monitors) == 2, f"Battery: expected the screen-off and sleep monitors, found {len(monitors)}"
for m in monitors:
    assert re.search(r"enabled: root\.batteryIdle && timeout > 0", m), "Battery: an idle monitor with timeout 0 is idle at once"
assert "respectInhibitors: false" not in battery, "Battery: a playing video must hold the battery timeouts"

low = re.search(r"onIsLowAndNotChargingChanged: \{(.*?)\n    \}", battery, re.S).group(1)
assert "Config.options.battery.autoPowerSaver && PowerProfiles.profile !== PowerProfile.PowerSaver" in low, \
    "Battery: power saver must be opt-in and remember only a profile it replaced"
plug = re.search(r"onIsPluggedInChanged: \{(.*?)\n    \}", battery, re.S).group(1)
assert "if (PowerProfiles.profile === PowerProfile.PowerSaver) PowerProfiles.profile = root.profileBeforeSaver" in plug, \
    "Battery: plugging in must not override a profile picked by hand"

limit = re.search(r"ConfigSwitch \{\n(?:\s*//[^\n]*\n)*\s*enabled: !page\.propsLoaded \|\| page\.props\.ChargeThresholdSupported === true(.*?)\n            \}", page, re.S)
assert limit, "BatteryConfig: the charge-limit switch must wait for UPower before dimming as unsupported"
assert "if (!page.propsLoaded || thresholdProc.running) return;" in limit.group(1), "BatteryConfig: a tap before UPower answers must do nothing"
assert 'text: !page.propsLoaded ? ""' in page, "BatteryConfig: \"Not supported\" must wait for UPower's answer"
assert "toggles: false" in limit.group(1), "BatteryConfig: the charge-limit switch toggles itself and hides a failed call"
assert "checked: page.props.ChargeThresholdEnabled === true" in limit.group(1), "BatteryConfig: the switch must show UPower's state"

battery_block = re.search(r"property JsonObject battery: JsonObject \{\n(                property int low.*?)\n            \}\n", config, re.S)
assert battery_block, "Config: no top-level battery group"
for key in set(re.findall(r"Config\.options\.battery\.(\w+(?:\.\w+)?)", page + battery)):
    leaf = key.split(".")[-1]
    assert re.search(rf"property \w+ {leaf}\b", battery_block.group(1)), f"Config: battery.{key} is written but not declared"

subprocess.run(["node", "modules/settings/batteryHistory.test.js"], cwd=II, check=True, capture_output=True)
print("ok: critical action, idle monitors, power saver and charge limit hold; history maths passes")
