# ii-bar-resources — brief

Read `.audit/ii-bar/brief.md` first. One fifth of the old `ii-bar-root` row, and
the largest single file in the cluster.

**Your files** (2, and nothing else):

```
dots/.config/quickshell/ii/modules/ii/bar/ResourcesPopup.qml   (2021 lines)
dots/.config/quickshell/ii/modules/ii/bar/DockerSection.qml    (711 lines)
```

**Purpose.** What the machine is doing right now, in one glance, with the detail
underneath for when the glance was bad news.

**Primary action.** The four meters — CPU, RAM, swap, disk — answering "is
something wrong" before anything is read. Everything else in the popup is
support.

**Hierarchy.** Meters first, at the top, large. Then the graphs (CPU/GPU
history) that say whether the number is a spike or a trend. Then temperatures
and the machine's identity (`cleanDistro`, `cleanCpu`, `cleanGpu`) as a quiet
footer. `DockerSection` is last and is a power-user extra — it is gated on
`Config.options.bar.resources.showDocker` and must never outrank a meter.

**Interaction.** Contract 1 — this is a `StyledPopup` and inherits its open and
close from `ii-bar-popups`; do not re-implement them and do not edit
`StyledPopup.qml`. Your `getDelay()` becomes the one stagger rule
(`staggerStep` × min(i, `staggerCap`)). A meter's value change animates on
`elementMove`; its colour crossing a warning threshold on `elementMoveFast`,
using `colError`/`colErrorContainer` — `cw-battery` settled that the *container*
token is what a track uses. The graphs are the existing shared `Graph` widget:
reuse, do not rebuild. Docker's per-container actions are buttons and take
`RippleButton` conventions (§9) with all four states.

**Edge states.** No GPU; no swap (`alwaysShowSwap` off and swap absent); docker
not installed at all (`DockerService` sits idle — the section must say so once,
quietly, or not render); docker installed with zero containers; a container
name long enough to elide; the first 30 seconds where the graph has no history
yet.

**Cost.** This file holds **five** `layer.enabled` + `OpacityMask` pairs (822,
1070, 1102, 1384, 1665). None is inside a delegate, so none is a law-8 breach on
its own, but five masks in one popup is over the effect budget for integrated
graphics (§8). Keep the one that masks scrolling content against its container's
radius; remove the rest — a mask whose only job is rounding a corner is what
`radius` + `clip` already do.

**Delete.** The four repeated `innerStartAnim` / `_percent` / `_fillColor`
blocks are the same meter written four times; if they collapse into one
component the diff shrinks by hundreds of lines and the four meters can no
longer drift apart. Do that if it is clean; say so in your report if it is not.
Every literal duration and curve. Any declared property nothing reads.

**Out of scope.** `Resources.qml` and `Resource.qml` (the bar-side widgets —
`ii-bar-widgets`), `cards/*.qml`, `StyledPopup.qml`, `services/DockerService.qml`
and `services/AlarmService.qml`. `modules/ii/verticalBar/Resources.qml`
instantiates `ResourcesPopup` by name.
