# sw-desktop-misc — notes

Lane 2. Eleven files, the odd ones out: notification list, quote, at a glance, water
reminder, photo (×4 pages), notes, plus `DesktopWidgetVisualOptions`.

## Header adoption

`adopt_header.py` ran clean on the seven pages that had a hand-rolled header. The three
9-line photo variants never had one (they inherit `DesktopPhotoWidgetConfig`) and
`DesktopWidgetVisualOptions` is a block, not a page. All seven `implicitHeight: 250`
became `Appearance.sizes.pagePlaceholderHeight`.

`DesktopPhotoWidgetConfig`'s `property string titleText` is **gone**. After the transform
its only reader was the `title: root.titleText` line the transform itself wrote, and its
only writers were the three alias files — so the alias files now set `ContentPage.title`
directly and the indirection is deleted. They are still 9 lines each.

## The name token, and why the family needed one

The clock family's placeholder copy is `"<Widget Name> disabled"` /
`"Enable the <Widget Name> in Desktop Widgets settings to use this page."`, where
`<Widget Name>` is the widget's registry name. That does not transfer here: this family's
registry names are bare nouns — "Quote", "Photo", "Notes", "At a Glance" — and
"Enable the Quote in Desktop Widgets settings" is not English.

So the token is the name **the page title already used**, which in every case is the
registry name plus "Widget" where the bare noun does not stand alone:

| page | `<Widget Name>` |
|---|---|
| `DesktopNotificationListConfig` | Notification List |
| `DesktopQuoteConfig` | Quote Widget |
| `DesktopAtAGlanceConfig` | At a Glance Widget |
| `DesktopWaterReminderConfig` | Water Reminder Widget |
| `DesktopPhotoWidgetConfig` | Photo Widget |
| `DesktopPhoto1x1Config` | Photo 1x1 Widget |
| `DesktopNotesWidgetConfig` | Notes Widget |

One token drives three strings per page: `title` (`<Name> Options`), the `ContentSection`
title (`<Name> Settings`) and the placeholder (`<Name> disabled` / `Enable the <Name> in
Desktop Widgets settings to use this page.`). No new copy was invented — every string is
the page's own title reused. Four of the seven already matched; three did not
(`Notification list` lowercase, `At a Glance`/`Photo 1x1` using "to configure options."
instead of the family sentence, `Photo widget` lowercase).

The notification-list description keeps a second sentence about lock-screen behaviour.
It is extra information, not different wording, and the option it points at lives on the
Desktop Widgets page — unreachable from here, and unreachable at all once the widget is
off, which is exactly when the placeholder shows.

## Icons

Every placeholder and section icon is now the widget's own registry icon
(`WidgetsRegistry.qml`). Only one was wrong: `at_a_glance` used `schedule` in both places —
a clock icon on a context widget, and the same icon the clock family uses — where the
registry says `dashboard`.

Placeholder shape was already `MaterialShape.Shape.Circle` on all seven. Unlike the clock
family, **no page here was missing its placeholder** — all seven had one.

## `DesktopWidgetVisualOptions`, judged

It does its job. The two toggles are global, the block is 42 lines with a docstring that
states the usage line, and it is the right shape for the header extraction to copy. It was
**not changed** — seven rows are live and rule 9 says leave shared vocabulary alone unless
the change is additive and every caller is checked.

What it was missing was callers. Both photo pages still carried the copy-pasted original:
`DesktopPhotoWidgetConfig` had the full "Visual Options" label + both switches inline, and
`DesktopPhoto1x1Config` had a lone "Enable Shadows" with no label and no inner-shadow
toggle — the same global option, reachable from one photo page and not the other. Both now
use the shared block, last on the page.

`DesktopNotesWidgetConfig` used it wrapped in a `ColumnLayout` that existed only to carry
`visible:`. The block is a `ColumnLayout`; it now carries `visible:` itself, which is what
its own docstring shows.

**At a Glance and Notification List deliberately do not get the block.** Checked the
widgets, not the pages: `AtAGlanceWidget.qml` and `NotificationListWidget.qml` are the only
two in this family that never read `enableShadows` or `enableInnerShadow`. Their absence is
correct, not a gap to fill.

## Reuse: two hand-rolled buttons deleted

- `DesktopQuoteConfig`'s "Fetch new quote" was a `RippleButton` with a
  `contentItem: RowLayout { anchors.centerIn: parent }` — an anchor inside the thing a
  Control already sizes. Now `RippleButtonWithIcon`.
- `DesktopWaterReminderConfig`'s "Reset today's count" was an `Item { implicitHeight: 44 }`
  wrapping a `RippleButton { anchors.left/right; implicitHeight: 40 }` with the same
  anchored `RowLayout` inside. Now `RippleButtonWithIcon`, which the photo pages in this
  same family were already using for exactly this.

Both inherit all four states from the audited root instead of declaring three colours each,
and three literals (44, 40, 36) go with them.

## Motion

One change, and it is a removal: the quote refresh button's icon had
`RotationAnimation on rotation { loops: Infinite; duration: elementMove.duration * 4 }`
spinning while `QuoteService.loading`. `RippleButtonWithIcon` does not expose its icon, so
the spin is gone. Replaced by `enabled: !QuoteService.loading`, which gives `RippleButton`'s
`opacity: 0.4` disabled state, alongside the label that already read "Fetching…". Nothing
else in this family animates; the pages' own enter/exit belong to `ConfigSubPageHost`.

If the cohesion pass wants a spinner back, the answer is `MaterialLoadingIndicator` or
`StyledIndeterminateProgressBar` from `cw-progress`, not a rotation re-hung on an icon.

## Found outside the fence — not fixed

1. **Card backgrounds never reach these rows.** `ContentGroup.qml:26-34` builds its cards
   from `column.visibleChildren` and needs `wantsCard === true` on each. Every page in this
   directory — all 70, not just my 11 — nests its rows inside one
   `ColumnLayout { visible: Config.isWidgetActive(...) }`, and that wrapper has no
   `wantsCard`, so `ConfigSwitch`/`ConfigSlider`/`ConfigSpinBox`/`ConfigSelectionArray`
   (which all declare it) render with no card at all. DESIGN.md 5.6 assumes they do.
   `ContentGroup` already reaches through one container level for `ConfigRow`
   (`ContentGroup.qml:45`, the `tiles` property) but not for a gating wrapper.
   Out of fence twice over — `modules/common/**` and a shape all eight rows share. The
   in-fence workaround (hoist every row and give each its own `visible:`) would add ~25
   bindings per page and break the family shape, so it was not done.
   `DesktopWidgetVisualOptions` swallows `wantsCard` for its own two switches the same way.

2. **The global shadow toggles have no global home.** `Config.options.background.widgets.
   enableShadows` / `.enableInnerShadow` are read by widgets across `modules/ii/background/
   widgets/` but are only *settable* from per-widget config pages under
   `modules/settings/widgets/`. A user running only At a Glance or the Notification List
   cannot reach them at all. That is a settings-page finding
   (`modules/settings/*.qml`, its own queue row), not a config-schema one.

3. **`DesktopPhotoWidgetConfig:105` `visible: root.configEntryName !== "photo"`** on the
   "Show Info Overlay/Badge" switch. The brief wants a non-applicable control disabled at
   0.4, not hidden — but this one is *permanently* absent for the base `photo` variant
   (`Config.qml` has no `showOverlay` under `background.widgets.photo`), so a permanently
   dead switch would be worse than no switch. Left as `visible:`, with the subsection label
   above it now carrying the same guard so the page does not show an empty "Overlay"
   heading. Flagging the rule tension, not the code.

4. **`DesktopQuoteConfig`'s `fetchRandom` branch is five rows each carrying their own
   `visible:`** rather than two groups with one `visible:` apiece, which is what the brief's
   edge-state rule describes. Grouping them would nest another two `ColumnLayout`s and, per
   finding 1, push the rows one level further from any card they might one day get. Left.

## Gates

- `tools/check-design.py --diff` — 0 findings, 0 errors (all eight rows' added lines).
- qmllint against a fresh `mkshadow.sh` tree — no `Error:`, and no `Info: unused import`
  after dropping the unused bare `import Quickshell` from both photo pages (they use
  `Quickshell.Io` for `Process`). Every remaining warning is the standing blind spot on a
  singleton's dynamic sub-objects: `Member "widgets" not found on type
  "qs::io::JsonObject"`, `Member "textField" not found on type "ConfigTextField"`,
  `Member "colX" not found on type "QObject"`. Not findings.
- No process was started; the runtime gate is the parent's.
