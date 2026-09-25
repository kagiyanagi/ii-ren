# ii-sidebarDashboard-nightLight — brief

**Purpose.** Turn the screen's eye-protection effects on or off, set how strong each one
is, and let them follow the evening schedule. Four quick tiles open this one dialog on a
long press: Night Light, Comfort View, Reading Mode and Anti-flashbang.

**Primary action.** Each effect's own switch. Before, the dialog was a 520px scroll box, so
only Night Light and half of Comfort View were on screen, and three rows said "Enable now".
It fits its content at 1080p now. The scroll box stays only as a cap for a shorter sidebar.

**Hierarchy.** One card per effect, in the order the tiles sit. Its first row is the
effect's name, a status line and the switch. Under it is the intensity slider, then
Automatic. Reading Mode adds Paper tone. The two anti-flashbang switches share a card under
one small label, "Anti-flashbang (experimental)". Done sits in the button row.

**Reference.** Android 16 Settings → Display → Night Light. There is a main switch whose
summary says when the schedule will act ("Will turn on automatically at 19:00"), then
Intensity, then Schedule. The rows are the Wi-Fi and hotspot dialogs' switch row: a
`DialogListItem` with a non-checkable `StyledSwitch` on a `colSurfaceContainerHigh` card.
The three sidebar dialogs read as one family.

**Interaction.**
- The row owns the state, and the switch never toggles itself. `ConfigSwitch` set
  `checked = !checked` on a click, which broke its binding. Each row also called its
  service from `onCheckedChanged`, so a binding update looked like a click. The worst case:
  with the dialog open, Night Light's schedule switching it on made the row call
  `toggleTemperature(true)`, and the schedule became a manual override.
- Status lines: "On" / "Off" when manual, and "On until 06:30" / "Turns on at 19:00" when
  automatic. Comfort View's and Reading Mode's switches show the manual state, because
  that is what a tap changes. The schedule can have one of them on while its switch is
  off, and the status line says so.
- Night Light's slider retints live: hyprsunset is cheap, and seeing it matters. The
  Comfort View and Reading Mode sliders reload Hyprland on every apply, so the service
  debounces them (see Cost).
- No new motion. `WindowDialog` owns the enter and exit. The shared widgets supply the four
  states.

**Edge states.**
- *Automatic, inside the window*: the main switch follows the schedule, and the status
  line says "On until 06:30".
- *Automatic off while on*: Night Light stays on (the service's existing behaviour), and
  the status line drops to "On".
- *A shorter sidebar*: the body scrolls under a fixed title and button row.

**Cost.** No effects. Service side: one debounce `Timer` in each shader service. Before,
a drag was a `hyprctl reload` for every integer crossed, twice over, because
`setIntensity`'s config write fired `onIntensityChanged`, which applied again.

**Delete.** The "Brightness" and "Gamma" sections. The sidebar's default quick slider
behind this dialog already does both (the gamma slider's top 70% is brightness).
Removing them also drops the `screen` and `brightnessMonitor` properties. The six
subsection headers, all seven tooltips (the status lines carry the two anti-flashbang
trade-offs), and the fixed `backgroundHeight: 670`. The row icons: without them the
sub-rows and the main rows start on one edge. Hyprsunset's `Hyprland.dispatch("hyprctl
…")`, which dispatches a dispatcher that does not exist.

**Out of scope.** The shader services' conflict over `decoration:screen_shader`. The
double reload on a Comfort View / Reading Mode toggle. Editing the schedule times (that is
in Settings). See `notes.md`.
