# settings-widgets — notes

Tranche split only. **No QML changed in this session**, same as `common-widgets`. What
landed: `families.md`, `brief.md`, `dead.txt`, a regenerated `pack.md`, two tools
(`tools/audit/reachable.py`, `tools/audit/smoke-settings.sh`), a fix to `pack.py`, the new
rows in `QUEUE.md` and decision 22 in `DECISIONS.md`.

## Read this before `sw-dead`

**Regenerate `dead.txt` before deleting anything.** `python3 tools/audit/reachable.py
modules/settings/widgets --dead`. It takes five seconds, and a list that is a few commits
old can only be wrong in the dangerous direction.

**The three paths the tool cannot produce** are in `families.md` and are all OSD triplet
copies: `widgets/OsdPositionPicker.qml` (dead — the live copy is the `configs/widgets/`
one, and the tool cannot tell two files of the same name apart), plus
`configs/widgets/OsdIndicatorsConfig.qml` and `configs/widgets/OsdPreviewCard.qml` (dead in
both copies).

**Also delete `modules/settings/widgets/qmldir`** — 85 lines declaring
`module qs.modules.settings.configs.widgets`, which is not this directory's URI. Four files
import that URI: `BannerImageConfig`, `DateDesktopWIdgetConfig`, `TouchEdgeGesturesConfig`
(all three dead) and `DateDesktopWidgetConfig` (live). The live one wants
`DesktopWidgetVisualOptions`, which is its own directory sibling and needs no import at
all, so the import line goes with the qmldir. Whether that URI resolves *today* is
untested — the page is loaded on demand, so a broken import would not show at startup, and
the smoke gate below is what proves it after the change.

**`DateDesktopWIdgetConfig.qml`** (capital I) is a typo twin of `DateDesktopWidgetConfig.qml`,
dead, and in the list. Do not "fix" the name.

**Gate it with `tools/audit/smoke-settings.sh`, not `smoke.sh`.** The settings app is a
second quickshell process; `smoke.sh` starts `qs -c ii` and proves nothing about it. The
new script starts `qs -p …/settings.qml`, waits for the window, greps the log, and kills
only the pid it started — it never `pkill`s, which would take the live shell down. It
passed clean before this session's changes, so any error it reports afterwards is ours.

Then click the five entry points by hand, because a sub-page loads on demand and no script
opens it: **Widgets** → any widget's cog (the 61 registry pages), **Lock** → Fingerprint,
**Widgets** → Extensions and Community, **Advanced** → Themed icons and Custom cursor,
**Interface** → the OSD position picker.

## How the dead half was found, and the one false positive it produced

`pack.py`'s reverse-dependency scan matched `Type {` only. Settings sub-pages are loaded by
url string — `Qt.resolvedUrl("widgets/Foo.qml")`, or a `"configPage"` entry in
`WidgetsRegistry.qml` — so the scan reported this entire directory as self-contained and
three sessions' worth of packs would have said the same. `pack.py` now matches both forms
and prints a **No caller anywhere** list; `reachable.py` does it transitively for a whole
directory.

The first version of that pattern let the url's path prefix be any `[\w./]*?`, so
`"widgets/DesktopBluetoothBatteryConfig.qml"` also read as a use of **`BatteryConfig`** —
158 lines that looked reached and are not. The prefix now has to end at a `/`, and the name
alternation is longest-first so a name that is a prefix of another cannot shadow it. If a
future row finds a file that looks alive on one caller alone, check that the caller is not
just a longer filename.

## The 62 registry-fed pages and the re-port

`modules/settings/widgets/Desktop*Config.qml` is the config UI for
`modules/ii/background/widgets`, which is vendored from ii-p3drovfx and permanently out of
scope (`DECISIONS.md` 3). The config pages are **not** in that deal:
`tools/p3-widget-port/port-widgets.sh` rsyncs the widget tree and the assets and never
touches `modules/settings/`, so a redesign here is not reverted by the next re-port. That
is why these rows exist at all.

What a re-port *can* do is add a widget to `WidgetsRegistry.qml` whose `"configPage"` names
a file this fork does not have — a cog that opens an empty pane. Run
`reachable.py modules/settings/widgets` after any re-port: a registry string with no file
behind it is invisible to every other check in this repo.

## What is already clean in the live half

Nothing here needs fixing before the rows run, and two things are worth not re-deriving:

- **`check-design.py` finds 11 hits in the 70 live files** — seven literal durations in
  `WidgetExtensionsContent`, one in `WidgetCommunityContent`, two 750ms and a
  `ringRadius: 70` in `FingerprintEnrollOverlay`, one `spacing: 1`. The other 66 hits in
  this directory are all in files `sw-dead` removes.
- **The live half has no effects at all** — no `layer.enabled`, no `MultiEffect`, no
  `OpacityMask`, no shadow, no `Canvas`, no sub-100ms `Timer`. Every entry in the pack's
  effect budget is in a dead file. The brief's `Cost.` line is therefore "zero, and it
  stays zero", which is a much easier rule to hold than a budget.

## Motion for the cohesion pass

Nothing yet — no row here has retimed anything. `ConfigSubPageHost`'s slide is already
audited and is the only motion these pages own; when `sw-clock-configs` moves the header
into `ContentPage`, what the cohesion pass has to watch is that the header does not
animate in separately from the page that carries it.
