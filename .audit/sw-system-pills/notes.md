# sw-system-pills — notes

Lane 2, 11 files. 980 lines in, 585 out.

## Header

All eleven adopted `ContentPage`'s `title` via `sw-clock-configs`' `adopt_header.py`, no
hand fixes needed — the eleven were mechanically identical (two whitespace dialects, one
with aligned colons, one without; the script does not care). Every `implicitHeight: 250`
(and the four resource pages' `implicitHeight: 200`, which the brief did not know about)
is now `Appearance.sizes.pagePlaceholderHeight`.

## The pattern `DesktopResourceFillCardsConfig` sets

Page title `"<Name> Options"`, section title `"<Name> Settings"` — kept from
`sw-clock-configs` rather than deduplicated, because dropping the section title is a
directory-wide convention call and not an eleven-page one. Flagged for the cohesion pass.

**Names and icons come from `WidgetsRegistry.qml`, not from the page.** The placeholder
sentence sends the reader to Desktop Widgets settings, which lists the widget under the
registry's `name` — so a page that calls it something else sends them looking for a string
that is not there. Three pages were lying:

| page | said | registry says |
|---|---|---|
| `DesktopBluetoothBatteryConfig` | Bluetooth Battery | Bluetooth Device Battery |
| `DesktopDevicesBatteryListConfig` | Devices Battery List | Connected Devices Battery List (2x1) |
| `DesktopDevicesBatteryList1x1Config` | Devices Battery List 1x1 | Connected Devices Battery List (1x1) |

Icons already matched the registry on all eleven; nothing to change there. The one internal
contradiction fixed: `DesktopBluetoothEarbudsStemConfig`'s placeholder said "Earbuds Stem"
while its own title said "Bluetooth Earbuds Stem".

Placeholder copy is now the family vocabulary on all eleven — `"<Name> disabled"` /
`"Enable the <Name> in Desktop Widgets settings to use this page."` The four resource pages
had ended theirs "…to configure options.", the seven device pages had an extra "widget"
in both strings.

**Section order, the four pages that have options:** Shape → Size → Details/Resources.
Already the order; only the vocabulary was invented per page ("Widget Grid Size & Aspect
Ratio", "Scale & Size", "Layout Orientation", "Active Resource Cards"). One noun each, and
`Size` is now literally the same string on all four. Row labels moved to sentence case, as
in the clock family.

## The real defect: the options had no cards

Every one of the eleven wrapped its rows in a bare

```qml
ColumnLayout { visible: Config.isWidgetActive(...); ContentSubsectionLabel {...}; ConfigSwitch {...} }
```

`ContentSection` hands its *direct* children to a `ContentGroup`, and that draws a card per
child with `wantsCard === true`. A bare `ColumnLayout` has no such property, so the group
saw one uncarded child and drew nothing — every `ConfigSwitch`, `ConfigSlider` and
`ConfigSelectionArray` on these pages was sitting bare on layer 0, with no container card,
against DESIGN.md §5.6 and the brief's "options grouped into container cards".

Each group is now a `ContentSubsection` (its own `ContentGroup`, its own label, its own
`SearchHandler`, `Layout.topMargin: 8`), which is what `BarConfig.qml` does and what the
clock pages do for their larger groups. That also deleted the `Item { Layout.preferredHeight: 4 }`
hand-rolled spacers — the gap is now 4 (group spacing) + 8 (subsection top margin) = 12,
on the grid and inside §5.3's 12–16 for sections.

The `visible:` gate moved from the one wrapper onto each subsection. Placeholder still
outranks: gate and negated gate are the only two states, so no page can show both.

## `DesktopWidgetVisualOptions` — present iff the widget reads the option

The seven device pages have nothing *but* this block. The four resource pages had none.
Rather than guess, I grepped the widgets: all seven device widgets and
`ResourceFillCardsWidget` read `enableShadows`/`enableInnerShadow`;
`CpuPillWidget`, `RamPillWidget` and `DiskPillWidget` never mention them.

So it was added to `DesktopResourceFillCardsConfig` (last, with a comment saying why) and
deliberately **not** to the three pill pages, where it would be anti-pattern 16 — a control
that changes nothing you can see from the page you changed it on. A later row that
"makes the family agree" by pasting it onto the three pills would be undoing that. The rule
is written in the comment in the file.

Its wrapper `ColumnLayout` is gone from the seven device pages; `DesktopWidgetVisualOptions`
is itself a `ColumnLayout` and its own docstring shows the intended
`DesktopWidgetVisualOptions { visible: ... }` usage.

## Findings outside the fence

- **`modules/settings/widgets/DesktopWidgetVisualOptions.qml:15`** — same card bug as above,
  unfixed because the file belongs to `sw-desktop-misc`. It is a bare `ColumnLayout` holding
  a `ContentSubsectionLabel` and two `ConfigSwitch`es, so its two switches get no card on
  any of the ~50 pages that use it, while every other row on those pages now does. It wants
  to be `ContentSubsection { title: Translation.tr("Visual Options") }` — the label then
  comes free and the body is unchanged.
- **`modules/settings/widgets/DesktopClockWidgetConfig.qml:31`** (`sw-clock-configs`, already
  landed) — the options `ColumnLayout` has no `visible: Config.isWidgetActive("clock_cookie")`
  gate, while the placeholder at :20 has the negation. With the widget off the page renders
  the placeholder *and* the full option set under it, so the placeholder does not outrank,
  it just stacks. Five `visible:` lines in the file, none of them on that layout.
- **Config schema gap, for FINDINGS.md** — the seven device pages
  (`bluetooth_battery`, `bluetooth_earbuds_stem`, `bluetooth_fill_cards`,
  `devices_battery_list`, `devices_battery_list_1x1`, `pc_battery_bars`,
  `pc_battery_cable`) have no per-widget option in `Config.qml` at all. Their "primary
  action under the first section header" is therefore a pair of global shadow switches.
  Not fixed here: the brief puts schema additions out of scope.

## Motion

None. Nothing in these eleven animates, nothing was retimed, and no `Behavior`,
`layer.enabled`, effect, shadow or `Timer` was added — the row's cost stays zero. The only
motion on these pages is `ContentGroup`'s corner-radius `Behavior` on `elementMoveFast`,
which the rows now get for free by being carded, and `ConfigSubPageHost`'s page transition.

## Gates

`check-design.py --diff` — 0 hits in the fence. qmllint on all eleven — clean apart from
the standing `Member "…" not found on type "QObject"` / `"qs::io::JsonObject"` blind spot
on `Appearance.sizes.*` and `Config.options.*`. No runtime probe run: the parent gates that
once, after all eight lanes finish.
