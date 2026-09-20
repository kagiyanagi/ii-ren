# ii-bar-popups — brief

Read `.audit/ii-bar/brief.md` first. One fifth of the old `ii-bar-root` row —
and the one that owns **Contract 1**, the popup shell every other row inherits.

**Your files** (5, and nothing else):

```
StyledPopup.qml  BatteryPopup.qml  ClockWidgetPopup.qml
MediaPopup.qml  NetworkSpeedPopup.qml
```

all under `dots/.config/quickshell/ii/modules/ii/bar/`.

**Do `StyledPopup.qml` first.** Six other popups in three other sessions are
built on it, and its motion is the thing that makes the cluster read as one
surface family. Rule 9 applies: it has six callers in your own files plus
`PrivacyIndicator`, `RecordIndicator`, `ResourcesPopup` and
`weather/WeatherPopup` outside them. Additive changes only to its declared API.

**Purpose.** The detail behind a bar item, one hover away.

**Primary action, per popup.**

- `BatteryPopup` — how long you have left. `hasTimeData` is the answer; the
  percentage is support.
- `ClockWidgetPopup` — the date and what is coming: alarms, world clocks, the
  stopwatch/timer. The hero is time and date; alarms are second.
- `MediaPopup` — what is playing and the transport.
- `NetworkSpeedPopup` — current up/down, then totals.

**Hierarchy.** Hero first (`HeroCard`), then at most three `SectionCard`s, then
nothing. A popup that needs a fourth section is a sidebar, not a popup.

**Interaction.** Contract 1 in full:

- the `arrowPopup*` composite for open/close, origin at the corner nearest the
  bar item, radius `verylarge`, elevation 3, 10 from the anchor, 8 from the
  screen edge. `DockFolderPopup.qml` and `DesktopMenu.qml` are the worked
  examples — read one before writing any of it. The current 35px slide plus
  `380ms OutQuart` / `260ms InCubic` goes.
- content entrance = `staggerStep` × min(i, `staggerCap`), each child opacity on
  `elementMoveFast` and **one** transform on `elementMoveEnter`. Every
  `getDelay()` in these four files becomes that.
- exit accelerating on fast effects at about half the enter (§2.5).
- Escape closes; outside click dismisses; hover-out respects
  `Config.options.bar.tooltips.closeDelay` as it already does.

**Edge states.** No battery; no player (`MediaPopup` with a null
`activePlayer`); no alarms and no world clocks configured (`ClockWidgetPopup`
gates three sections on config — with all three off it must not open an empty
card); a vertical or bottom bar, where the anchor edge and the origin both
change; a popup taller than the screen (`maxAllowedHeight` already clamps —
check what happens to the content when it does).

**Cost.** `StyledPopup` runs three timers: 60ms, 30ms and **1ms**. A 1ms timer
is a frame-ordering hack — find what it is actually waiting for and use
`Qt.callLater` or the property change that signals it, or leave a comment
naming the Qt behaviour it works around. `StyledPopup.qml:441`'s shadow is
elevation and stays.

**Delete.**

- `childDelays`, `recalculateDelays()`, `setupConnections()`,
  `updateChildrenAnimation()` and the `childrenChanged` / `visibleChanged`
  wiring. `updateChildrenAnimation()` is an empty function with a comment saying
  the children animate themselves; the ~90 lines that compute its input run on
  every open and drive nothing.
- `BatteryPopup`'s ~50 literal durations — it is the worst file in the cluster.
- Any declared property `pack.md` shows nothing reads.

**Out of scope.** `cards/*.qml`, `weather/*.qml`, `ResourcesPopup.qml`,
`DockerSection.qml`, `BatteryIndicator.qml`, `ClockWidget.qml`, `Media.qml`,
`NetworkSpeed.qml` — other rows. `modules/ii/verticalBar/**` instantiates
`BatteryPopup`, `ClockWidgetPopup` and `MediaPopup` by name.
