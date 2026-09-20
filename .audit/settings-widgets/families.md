# settings-widgets — the family split

`modules/settings/widgets` is a tranche, not a session: 190 files, 35,099 lines. It is cut
below the same way `common-widgets` was, with one difference that dominates everything
else in this directory:

> **120 of the 190 files — 25,071 lines, 71% of the tranche — are reached by nothing.**

So the split is one delete row and nine design rows, not sixteen design rows. Redesigning
a page the settings app cannot open is the most expensive way to change nothing.

## How "reached by nothing" was established

`tools/audit/reachable.py modules/settings/widgets` (written for this row, re-runnable,
cheap). It follows both reference forms and does so transitively — a file reached only by a
file that nothing reaches is dead too:

```
Type { … }          instantiation
"…/Type.qml"        Qt.resolvedUrl / Loader.source / a registry string
```

The second form is the only one the settings sub-pages use, which is why nobody saw this
until now: `pack.py`'s reverse-dependency scan matched `Type {` only, and reported this
whole directory as self-contained. It matches both forms as of this row.

The live half has exactly five entry points:

| entry point | reaches | lines |
|---|---:|---:|
| `modules/ii/background/widgets/WidgetsRegistry.qml` — `"configPage"` per widget, opened by `WidgetsConfig.qml` | 62 | 7,662 |
| `modules/settings/LockConfig.qml` → `FingerprintConfig` → enroll overlay → hand picker | 3 | 966 |
| `modules/settings/WidgetsConfig.qml` — extensions and community tabs | 3 | 865 |
| `modules/settings/AdvancedConfig.qml` — themed icons, custom cursor | 2 | 535 |
| `modules/settings/InterfaceConfig.qml` — `import "configs/widgets"`, the OSD position picker | 1 | 117 |

Three corroborating facts, all from `pack.md`, none needed to reach the same conclusion:

- **486 of the 904 `Config.options.*` paths this directory reads do not exist in
  `Config.qml`** and read as `undefined` silently. They are concentrated in the dead half —
  whole feature surfaces (`bar.portWatcher`, `phone.scrcpy`, `search.browserSites`,
  `calendar.timetable`, `mediaDownloader`, `appStats`) whose backend this fork never had.
- **66 of the 77 `check-design.py` hits are in dead files.** The delete removes 86% of this
  tranche's mechanical debt and no design work does.
- **Every effect in the tranche is in a dead file** — `WallpaperEngineConfig`'s two masked
  layers inside a delegate, `ConfigBannerSelector`'s three, `TimeDatePreview`,
  `CoreGoogleTasksConfig`, `OverviewGridPreview`'s `Canvas`. The live half has no
  `layer.enabled`, no `MultiEffect`, no shadow and no sub-100ms `Timer` at all.

## The rows

Run in the order listed. `sw-dead` is first because every pack after it is generated from a
directory of 70 files instead of 190.

Regenerate any row's pack with the regex in its row:

```
python3 tools/audit/pack.py modules/settings/widgets --only '<regex>' --id <id>
```

| row | files | lines | `--only` regex |
|---|---:|---:|---|
| `sw-dead` | 122 | 25,531 | — delete: the 119 paths in `dead.txt`, plus the three named below |
| `sw-clock-configs` | 6 | 1970 | `^Desktop(ConcentricClock\|ClockWidget\|WearOSClockWidget\|WearOSArcClock\|DialClock\|MonthClock)Config\.qml$` |
| `sw-clock-styles` | 12 | 1228 | `^(Desktop(ScallopDotClock\|NothingClock\|ScallopNumberClock\|WordClock\|CirclePointerClock\|TripleRingClock\|FlexClock\|HoriClock\|NagasakiTextClock\|NagasakiClock\|NothingWheelClock)Config\|DateDesktopWidgetConfig)\.qml$` |
| `sw-weather-calendar` | 15 | 1198 | `^Desktop(Weather(Widget\|Icon\|Forecast\|Card\|Hourly\|Circle\|Typography\|Pill)\|NothingWeather\|Calendar(Grid2x1\|MinimalWidget\|Upcoming3Days\|NextEvent\|Pill\|Agenda))Config\.qml$` |
| `sw-media-configs` | 7 | 944 | `^Desktop(MediaWidget\|CircularMediaWidget\|ExpressiveMedia\|CompactMedia\|CdMedia\|NothingRingMedia\|VolumeMute)Config\.qml$` |
| `sw-system-pills` | 11 | 969 | `^Desktop(ResourceFillCards\|CpuPill\|RamPill\|DiskPill\|DevicesBatteryList\|DevicesBatteryList1x1\|PcBatteryBars\|PcBatteryCable\|BluetoothBattery\|BluetoothEarbudsStem\|BluetoothFillCards)Config\.qml$` |
| `sw-desktop-misc` | 11 | 1353 | `^Desktop(NotificationList\|Quote\|AtAGlance\|WaterReminder\|PhotoWidget\|Photo1x1\|NotesWidget\|PhotoMinimalTemp2x1Widget\|PhotoWeather2x1Widget\|PhotoPill2x1Widget)Config\|^DesktopWidgetVisualOptions\.qml$` |
| `sw-fingerprint` | 3 | 966 | `^Fingerprint(Config\|EnrollOverlay\|HandPicker)\.qml$` |
| `sw-extensions` | 3 | 865 | `^(WidgetExtensionsContent\|WidgetCommunityContent\|ExtensionWidgetSettingsRenderer)\.qml$` |
| `sw-advanced-pages` | 2 | 535 | `^(CustomCursorConfig\|ThemedIconsConfig)\.qml$` |

**Live total** 70 files / 10,028 lines — 29% of the tranche, and less than `common-widgets`
was in total.

**The three paths `dead.txt` cannot know about**, all three of them the OSD triplet that
exists twice, byte for byte, in `widgets/` and in `configs/widgets/`:

```
modules/settings/widgets/OsdPositionPicker.qml
modules/settings/configs/widgets/OsdIndicatorsConfig.qml
modules/settings/configs/widgets/OsdPreviewCard.qml
```

`InterfaceConfig.qml` imports `"configs/widgets"` and nothing imports `widgets/` by path,
so of the two `OsdPositionPicker.qml` the live one is the `configs/widgets/` copy — which
is the one thing `reachable.py` cannot see, since both files answer to the same type name.
The other two files in that directory are reached by nobody in either copy.

The surviving `configs/widgets/OsdPositionPicker.qml` (117 lines) is not a row here: it is
the OSD's position picker and belongs to `ii-onScreenDisplay`, which is where its brief
gets written.

## What the live half has in common

61 of the 70 live files — every registry page, both Advanced pages, `FingerprintConfig` —
are the same shape: a hand-rolled header row (a 40dp circular `RippleButton` with
`arrow_back`, then a title `StyledText`), `property bool showBackButton: false`,
`signal goBack()`, then `ContentSection`s of `ConfigSwitch` / `ConfigSlider` /
`ConfigSelectionArray` rows, with a `PagePlaceholder` for "this widget is off". 61 copies
of a header that `ConfigSubPageHost`'s own docstring already claims lives in `ContentPage`
— it does not.
Closing that gap is the first row's job and is why `sw-clock-configs` is lane 1; see
`brief.md`.

Excluded from every row: nothing. There is no submodule and no vendored subtree *inside*
this directory — but see `notes.md` on why the 62 registry-fed files are nonetheless the
config UI for a widget tree that is out of scope, and what that does and does not imply.
