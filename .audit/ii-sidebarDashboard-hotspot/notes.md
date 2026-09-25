# ii-sidebarDashboard-hotspot — notes

**Opening it.** `qs -c ii ipc call sidebarRight openDialog Hotspot`.

**The hotspot was never switched on during this session.** The machine's only Wi-Fi
adapter was carrying the session's uplink (`Excitel_ansh_5g`), and turning the hotspot on
would have dropped it. So "Turning on…", "N devices connected · X used" and a failed start
were not seen live. `check-hotspot-dialog.py` evaluates each of those lines. The off state
("Disconnects from Excitel_ansh_5g"), the dimmed password field for an open network, and
Save disabling again once a change is undone were all driven with real clicks.
`shot-after.png` is the resting dialog.

**"Disconnects from %1" assumes one Wi-Fi adapter.** With two, `nmcli dev wifi hotspot` may
pick the one that is not connected, and then the line is wrong. Laptops with two Wi-Fi
adapters are rare enough that counting devices was not worth a second nmcli call.

**Unverified, in the service and not in scope: "None" security.** `applyHotspotConfig`
writes `key-mgmt none` with an empty psk. In NetworkManager, `key-mgmt=none` means static
WEP, and a truly open AP removes the `802-11-wireless-security` setting. The dialog offered
this option before this row too. Test it before trusting it.

**Tried and rejected.** Hiding the password field when "None" is picked. `WindowDialog`
centres the card on its height, so the card shrank from both ends and the Security row
moved up under the pointer. In testing, the next click landed outside the card and
dismissed the dialog.

**Not done.**
- `tools/audit/smoke.sh` was not run, because it `pkill`s the shell and the user was on the
  desktop. The running shell hot-reloaded both files, rendered the dialog, and logged
  nothing from either. The 18 `modelData` role warnings in the log come from elsewhere:
  the count did not move when the dialog opened.
- The agy/Gemini vision pass was not run.

**Gotcha for the next session driving this.** `hl.dsp.cursor.move` warps the pointer
without sending motion to the client, so no hover shows until a real `ydotool mousemove`
nudge. The eye button's layer-3 hover film was confirmed that way.

**For the cohesion pass (motion).** Nothing is retimed. Two new fades, both on
`elementMoveFast`: the switch icon's colour to primary, and the password column's dim to
0.4.
