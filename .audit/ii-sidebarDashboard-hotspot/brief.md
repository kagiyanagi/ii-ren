# ii-sidebarDashboard-hotspot — brief

**Purpose.** Share this computer's connection over Wi-Fi: turn the hotspot on or off, see
who is on it, and set the name and password other devices will type.

**Primary action.** The on/off switch. Before, it was the one thing not on screen: the
content was taller than its 490px scroll box, and `shot-before.png` opens with the
"Status" section scrolled out above the top edge. The dialog fits its content now and has
no scroll box at all.

**Hierarchy.** Title, then the switch row on its own card, then the settings: name,
password, band, security. Cancel and Save sit in the button row, as in every
`WindowDialog`. The switch row's status line carries what the two "Activity & Usage" stat
cards did: "2 devices connected · 14.2 MB used" while on. The cards showed "--" twice
whenever it was off, which is most of the time.

**Reference.** Android 16 Settings → Hotspot & tethering → Wi-Fi hotspot: a main switch on
top, then Hotspot name, Hotspot password, Security and Speed & compatibility, each saying
its current value. The switch row is the Wi-Fi dialog's power-saving row: the same
`DialogListItem` on a `colSurfaceContainerHigh` card, with a non-checkable
`StyledSwitch`, so the two sidebar network dialogs read as one family.

**Interaction.**
- The row owns the state, and the switch never toggles itself. `ConfigSwitch` did
  `checked = !checked`, which broke its `checked: Network.hotspotToggled` binding, so a
  hotspot that failed to start still showed as on.
- Band and security are connected button groups (`SelectionGroupButton`, 2px gaps), as in
  `KeybindEditor`. Two and three options fit on one line, where a combo box elided
  "2.4 GHz (bg) - Broader compa…".
- Name and password are `MaterialTextField`s whose own outlined label names them. The
  separate label above each field, which repeated the placeholder, goes. The
  reveal-password button is a round `RippleButton` inside the field's trailing edge, M3's
  trailing icon.
- Save is enabled only when a field differs from what NetworkManager has *and* the
  password is valid. The four states and the 0.4 disabled state come from the shared
  widgets. No new motion; `WindowDialog` owns the enter and exit.

**Edge states.**
- *Unsupported adapter*: the row is disabled, and its status line says "Not supported by
  this Wi-Fi adapter". Before, a greyed switch gave no reason.
- *Turning on / off*: the status line says so while the nmcli call runs, and a tap is
  ignored. `Network.hotspotSwitching` is new for this.
- *Off while on Wi-Fi*: "Disconnects from %1". The hotspot takes the only adapter, so
  the machine loses its uplink and the clients get no internet. Nothing said so before.
- *On, nobody connected*: "No devices connected · 0 B used".
- *Open security*: the password field dims to 0.4 in place, and its supporting line says
  "Not used by an open network". Hiding it was tried first: that shrank the card, which
  re-centres, and moved the security buttons out from under the pointer.
- *Invalid password*: the supporting line "At least 8 characters" is always under the
  field, and turns error colour once the field holds a short password.

**Cost.** None. No effects. The `StyledFlickable` and its scrollbar go.

**Delete.** The scroll box. The "Status", "Activity & Usage" and "Network Settings"
subsection headers. The two stat cards. The four field labels. Both combo boxes. The
hand-set `opacity: 0.4` on Save, which `RippleButton` already applies. The fixed
`backgroundHeight: 640`.

**Out of scope.** `Network.qml`'s nmcli scripts, beyond the one busy flag. The hotspot
quick toggle. The 2s usage poll, which runs only while the dialog is open and the hotspot
is on.
