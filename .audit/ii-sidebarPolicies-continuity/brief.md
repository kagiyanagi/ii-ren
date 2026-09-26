# ii-sidebarPolicies-continuity — brief

**Purpose.** See at a glance which of your other devices are here — the phone, whatever is on
your head, the tailnet — and do the one thing you came to do with one of them.

**Primary action.** Per card, the disclosure: tapping the phone card opens its notifications,
tapping a tailnet peer reveals its actions. The action pills inside a card are the secondary
layer and keep their own clicks.

**Hierarchy.** The phone card first (the one prominent card: larger icon, larger name,
primary container while it is reachable). Then each device's name, then its status line,
then its battery. The peer's route hint and exit-node badge last.

**Reference.** Android 16's Bluetooth device details / Quick Share device rows: a tonal card
per device, a supporting line under the name, the M3 linear progress indicator for battery.
A device that is out of reach drops to the neutral surface tone rather than fading — Android
never ghosts a card that still holds a live control.

**Interaction.**
- *Both cards.* One `MouseArea` under the content is the whole-card target, so the pills
  inside accept their own press first and a tap on a pill never also toggles the card (the
  peer used a `TapHandler` on the root, which also toggled on a tap in the gaps between its
  buttons with no press feedback at all). Hover and pressed films via `StateOverlay` in the
  card's content colour, pointing-hand cursor. No focus state: nothing on this page is in the
  tab order, as the anime row accepted.
- *Chevron.* Both cards carry one when they expand (the peer had none, so nothing said it
  would). It flips on `elementMove`, the spatial spec the peer's height change already runs
  on, not `elementMoveFast`, which is an effects curve.
- *Peer expand.* Height on `elementMove` as before. The action row fades in on
  `elementMoveFast` and out on `elementMoveExit` before the height drops, the
  `BluetoothDeviceItem` forget-button choreography, and the card clips so the row does not
  paint over the next peer while the card is still growing.
- *Battery.* `StyledProgressBar` — the M3 track, gap and stop point, and a non-overshooting
  value spec. The hand-built bar overshot on `elementMove`, reporting a charge that never
  happened.
- *Out of reach.* The phone card goes `colPrimaryContainer` → `colLayer2` on the effects
  spec, replacing `opacity: 0.55`, which also ghosted the "Open KDE Connect" pill — the only
  thing the card offers in that state.
- *Exit node.* The peer card stays `colTertiaryContainer`, and its text follows to
  `colOnTertiaryContainer`; it used to keep layer-2 text and lose its hover.

**Edge states.**
- *No phone / not installed:* the prominent card in the neutral tone, with the host's pairing
  pill. Unchanged apart from the tone.
- *No battery reported:* no bar and no percentage, as before.
- *Offline peer:* subtext name and icon, and the presence dot in `colSubtext`.
- *One peer:* a single card; nothing depends on count.

**Cost.** No effects before or after. `StateOverlay` loads its films only while shown. The
peer's clip is a scissor, not a layer.

**Delete.** The peer's `TapHandler` and hover-colour swap. `opacity: 0.55` dimming and the
status line's `opacity: 0.85`. The hand-built battery track and fill, and the dead
`colOutlineVariant` branch of `chargeColor`. Off-grid 14 / 10 / 5 / 1 and the 30px buttons
(under the 32px hit minimum).

**Out of scope.** `Continuity.qml` (the page, the notification swap, `ActionPill`, the empty
state) belongs to `ii-sidebarPolicies-root`. Grouping the peers into one connected run
(DESIGN.md 5.6) would need the host's spacing and the run position, so it is noted there.
