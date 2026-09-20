# ii-bar-weather — brief

Read `.audit/ii-bar/brief.md` first.

**Your files** (2, and nothing else):

```
dots/.config/quickshell/ii/modules/ii/bar/weather/WeatherBar.qml
dots/.config/quickshell/ii/modules/ii/bar/weather/WeatherPopup.qml
```

**Purpose.** The current condition at a glance in the strip; the day's shape on
hover.

**Primary action.** In the bar: the current temperature, with the condition icon
supporting it. In the popup: today — the hero (now, city) and the hourly curve.

**Hierarchy (popup).** `HeroCard` (temperature, condition, city pill) → hourly
forecast → in-day forecast → `MetricsGrid` (wind, humidity, the rest). The grid
is last because nobody opens a weather popup to read humidity first.

**Interaction.** `WeatherBar` is a bare `MouseArea` that renders hover only —
it is a bar item and takes Contract 3: four states off `colLayer0Hover` /
`colLayer0Active`, ≥32px hit area, pointing-hand cursor, and the §3.3 scale
composition if you scale it at all. The popup is a `StyledPopup` and inherits
Contract 1 from `ii-bar-popups` — do not re-implement open/close motion here,
and do not edit `StyledPopup.qml`. Your `getDelay()` becomes the one stagger
rule (`staggerStep` × min(i, `staggerCap`)).

**Edge states.** This is the row's real find, not the 13 mechanical hits:

- **loading** — `forecastLoading` exists; make sure every block that can be
  empty shows `LoadingPlaceholder`, not blank space.
- **error** — `fetchForecast` has no failure path that reaches the user. A
  failed or timed-out fetch currently reads as loading forever. One honest line
  in `colOnSurfaceVariant` plus a way to retry (re-hover is enough) — say what
  you did in your report.
- **no city configured** — `Config.options.bar.weather.city` empty. Do not show
  a blank hero.
- **one hour of data** — the hourly chart must not divide by a zero span
  (`getHourlyTempRange` / `tempSpan`); `0/0` is NaN and a clamp does not catch
  it. `ii-background-root` shipped exactly this bug; see
  `tools/check-desktop-parallax.py` for the shape of the check it left behind.
  If the arithmetic here can go NaN, leave a `tools/check-*.py` that proves it
  cannot (pure asserts, one concern, no framework).

**Cost.** Nothing — this row has no effects and no fast timers. Keep it that way.

**Delete.** Nothing structural. `compactMode` is read by
`Config.options.bar.tooltips.compactPopups` and stays.

**Out of scope.** `cards/*.qml` (you compose them, you do not edit them),
`StyledPopup.qml`, `BarComponent.qml` (which instantiates `WeatherBar`).
