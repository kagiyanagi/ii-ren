# sw-weather-calendar — notes

Lane 2. Fifteen pages: nine weather, six calendar. 108 lines in, 706 out.

## Header adoption

All fifteen took `ContentPage`'s `title` / `showBackButton` / `goBack()` from
`sw-clock-configs` via `adopt_header.py`, unmodified — no page's shape defeated it. The
`implicitHeight: 250` on every placeholder wrapper became
`Appearance.sizes.pagePlaceholderHeight`.

## One template, thirteen pages

Thirteen of the fifteen turned out to be the *same page*: a placeholder, and
`DesktopWidgetVisualOptions`. They are now emitted from one 38-line template, so the only
thing that differs between them is the widget id and the three strings that name it. Two
pages have real options and were written by hand: `DesktopWeatherWidgetConfig` (background
shape, Expressive style only) and `DesktopWeatherIconConfig` (background shape).

The `ColumnLayout { visible: … }` wrapper around a lone `DesktopWidgetVisualOptions` is
gone on all thirteen — `visible:` sits on the block itself, which is what that component's
own docstring shows as the usage. On the two pages that gate more than one child the
wrapper stays and its `spacing` went 4 → 12: it separates *groups* (a `ContentSubsection`
from the visual-options block), not rows, and DESIGN §5.3 puts groups 12–16 apart.
`DesktopWeatherWidgetConfig` had been buying that gap with an
`Item { Layout.preferredHeight: 16 }` spacer; that is gone too.

## Family vocabulary

Weather (9) was already coherent — section `Weather Settings` / `cloud`, placeholder
`cloud_off` — and kept it.

Calendar (6) was not. Section title named its own widget six different ways, section icon
and placeholder icon were each one of `event` / `calendar_month` / `calendar_today` /
`calendar_view_day`, and the placeholder icon was the widget's *own* glyph rather than an
off state — a lit calendar icon telling you the calendar is off. All six are now section
`Calendar Settings` / `calendar_month`, placeholder `event_busy`. `event_busy` was not used
anywhere in the repo before; it is present in the shipped
`MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf` (checked with fontTools, not assumed).

Strings are `<Widget Name> disabled` and `Enable the <Widget Name> in Desktop Widgets
settings to use this page.`, and `<Widget Name> Options` for the page title. **The widget
name is `WidgetsRegistry.qml`'s `name` field, verbatim**, because the description tells the
user to go find that exact row in the Desktop Widgets list. That is why titles gained size
suffixes they did not have (`Calendar Agenda 1x1`, `Weather Icon Shape`,
`Calendar Month Grid 2x1`): the registry has them and the list shows them. Before this,
several pages used three different names for one widget — page title, placeholder title and
placeholder description each naming it differently on the same screen.

One deliberate exception: `DesktopWeatherWidgetConfig` is the config page for *two* registry
entries, `weather_default` and `weather_expressive`. It is `Weather Options` /
`Weather widgets disabled` / "Enable the Default Weather or Expressive Weather in …", and
carries a comment saying why. A later row that mechanically re-derives names from the
registry must not flatten it back to one name.

## The brief's one design call — vacuous here, and that is the finding

"A weather page that exposes a units option must place it first; a calendar page that
exposes a 'which calendar' option must place that first."

**No page in this row exposes either.** Both options exist and both live somewhere else:

- units → `Config.options.bar.weather.useUSCS`, the only control is
  `modules/settings/ServicesConfig.qml:998`
- which calendar → `Config.options.calendar.icsUrls`, the only control is
  `modules/settings/ServicesConfig.qml:125`

So the ordering rule had nothing to order. Not adding them here was a decision, not an
oversight: they are *global* service options, and duplicating a global option across nine
pages is the exact mistake `DesktopWidgetVisualOptions` exists to undo — its docstring says
that block was copy-pasted into 50 pages before someone extracted it. Nine copies of a
units switch would be the 51st. If the parent wants units reachable from a weather widget
page, the answer is one shared block, the same shape as `DesktopWidgetVisualOptions`, not
nine switches — and that is a new file, which this row was fenced against.

## Findings outside the fence

- `modules/settings/ServicesConfig.qml:998` / `:125` — as above. A user who opens
  "Weather Card 1x1 Options" from the desktop and wants °F has to leave and find
  Settings → Services.
- **Thirteen of these fifteen pages have no per-widget option at all.** Their entire
  content is a global block plus a placeholder. `WidgetsRegistry.qml` gives every one of
  them a `configPage`, so the desktop offers a settings screen that settings nothing about
  that widget. Either the widgets gain options or the registry stops linking a page; both
  are outside this row.
- `modules/common/Config.qml:761` — the Expressive Weather widget's shape lives under the
  key `weather`, while the widget ids are `weather_default` and `weather_expressive`.
  Nothing uses a `weather_expressive` config group. It reads like a leftover from before
  the style split and it is why that page's gating needs three `isWidgetActive` calls to
  say something simple.
- `sw-clock-configs`' six, for the cohesion pass: `DesktopMonthClockConfig.qml:24` uses
  `calendar_month` as its placeholder icon where the other five use `watch`, and
  `DesktopDialClockConfig.qml:27` says "Enable the Dial Clock **widget** in …" where the
  other five omit "widget". Same two inconsistencies this row just removed from calendar.
  `DesktopMonthClockConfig.qml:24-27` also aligns its property colons with runs of spaces,
  which nothing else in the directory does.

## Motion

None. Nothing in these fifteen files animates, before or after; the page's own enter/exit
is `ConfigSubPageHost`'s and the header now rides it as part of the page. Effect budget
still zero — no `layer.enabled`, `MultiEffect`, `OpacityMask`, shadow, `Canvas` or `Timer`
in any of the fifteen.

## Gates

`check-design.py --diff` 0 findings / 0 errors · qmllint clean on all fifteen against a
fresh shadow tree, modulo the standing `Member "x" not found on type "QObject"` blind spot
on `Appearance.sizes` and the same thing as `qs::io::JsonObject` on
`Config.options.background.widgets` (both pre-existing, both singleton sub-objects). No
runtime gate run — the parent owns that.
