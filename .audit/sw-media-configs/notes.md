# sw-media-configs — notes

Lane 2, 7 files. Built directly on `sw-clock-configs`' `ContentPage` header.

## Header adoption

All seven ran through `adopt_header.py` unchanged — no file's shape defeated it. 34 lines
out, 1 `title:` in, per page; `implicitHeight: 250` → `Appearance.sizes.pagePlaceholderHeight`
on all seven placeholder wrappers.

## The three dead switches, and how they were found

The brief's flag for this row was "controls that duplicate what the media widget itself
offers". There are **no transport controls, no volume control and no player picker** on any
of the seven pages — every control was a show/hide or a colour toggle, which is appearance.
What the flag actually turned up is the adjacent defect: controls bound to keys nothing
reads (anti-pattern 16). Every key in the pack was grepped against
`modules/ii/background/widgets/**` before anything was touched. Five were orphans:

| key | what the page claimed | reality |
|---|---|---|
| `circular_media.showPrevButton` | hide the ⏮ button | `CircularMediaWidget.qml:314` hardwires it |
| `circular_media.showNextButton` | hide the ⏭ button | `:431` hardwires it |
| `circular_media.showDevicePill` | hide the audio-device pill | `:466` hardwires it |
| `circular_media.enableShadows` | this widget's shadow | widget reads the **global** `widgets.enableShadows` (`:137`) |
| `compact_media.enableInnerShadow` | this widget's inner shadow | `CompactMediaWidget.qml` has no inner shadow at all |

All five switches are gone. The four on `DesktopCircularMediaWidgetConfig` took the whole
"Buttons" subsection with them.

The shadow one is not just a deletion: the circular widget's shadow **is** switchable, via
the global key, so the dead per-widget switch was replaced by `DesktopWidgetVisualOptions`
— the shared block that writes the key the widget actually reads. That is the same
copy-paste-with-a-wrong-key that `DesktopWidgetVisualOptions` was extracted to kill, caught
one page later.

`compact_media.enableShadows` and both `media_cd` shadow keys **are** read, so those pages
keep their own per-widget switches and do *not* get the shared block. The brief says
"`DesktopWidgetVisualOptions` last where present" — it is not added where a real per-widget
control already covers the same ground.

## Family agreement

Section icon `music_note` and placeholder icon `music_off` on all six media pages (two
already had them; `album`, `queue_music` and `graphic_eq` were the strays). Placeholder
`shape: MaterialShape.Shape.Circle` everywhere, which was already true.

**`DesktopVolumeMuteConfig` deliberately keeps `volume_off` for both.** It is a System-category
mute pill that landed in this row as a leftover, not a media widget; a `music_off`
placeholder would name the wrong thing. The comment on its `icon:` line says so, so the
cohesion pass does not "fix" it back.

Names now come from `WidgetsRegistry.qml`, minus the grid-size suffix that is picker
metadata (`1x1`, `(2x1)`, `1x0.5`):

| file | widgetId | name used |
|---|---|---|
| `DesktopMediaWidgetConfig` | `media_circular` | Circular Media |
| `DesktopCircularMediaWidgetConfig` | `circular_media` | Circular Media (Watch) |
| `DesktopExpressiveMediaConfig` | `media_expressive` | Expressive Media |
| `DesktopCompactMediaConfig` | `compact_media` | Compact Media |
| `DesktopCdMediaConfig` | `media_cd` | CD Media |
| `DesktopNothingRingMediaConfig` | `nothing_ring_media` | Nothing Ring Media |
| `DesktopVolumeMuteConfig` | `volume_mute_pill` | Volume Mute Pill |

Page title `"<name> Options"`, section title `"<name> Settings"`, placeholder
`"<name> disabled"` / `"Enable the <name> in Desktop Widgets settings to use this page."` —
lane 1's exact wording, including the absence of the word "widget" in the sentence.

**The two names collide on purpose.** `media_circular` is "Circular Media" and
`circular_media` is "Circular Media (Watch)" — two different widgets whose ids are anagrams
of each other. The pages were titled "Media Widget Options" and "Circular Media Options",
which meant the page you reached from "Circular Media" was not the one titled that. Matching
the registry name exactly is the only way a user can tell which page they are on; the
awkward "Circular Media (Watch) Options" is the price. Renaming the ids is a `Config.qml`
change and therefore a finding, not this row's diff.

Section order, geometry → colour → the rest → shared visual options last:

- Circular Media: shape · colours · controls · glow · visualizer · visual options
- Circular Media (Watch): size · colours · style · visual options
- Expressive Media: display · colours · visual options
- Compact / CD Media: size · colours · visual options
- Nothing Ring Media / Volume Mute Pill: visual options only

Every page already had a widget-off `PagePlaceholder`, so the clock family's "no edge state
at all" defect does not repeat here.

## Spacing, and the arithmetic behind the one number

Group separators are `Item { Layout.preferredHeight: 4 }` on all seven. The pages were mixed
4 / 8 / 16 and lane 1 is mixed too (Concentric and Dial use 4, the cookie clock 16).

4 is the right one, not a coin toss: the enclosing `ColumnLayout` has `spacing: 4`, so a
4px spacer renders a **12dp** gap (4 + 4 + 4), which is the bottom of §5.3's 12–16 band for
sections in a panel. The 16px spacer renders 24dp, which is above it.

The per-group `ColumnLayout` wrappers are gone. They held a label and some rows at the same
`spacing: 4` as their parent, so they rendered identically and only added a nesting level.

## Found outside the fence

1. **`ContentGroup` only cards its direct children, so no row on any of these 61 pages gets
   a card.** `modules/common/widgets/ContentGroup.qml:27` models `column.visibleChildren`
   and `:34` asks `row?.wantsCard === true`. Every widget config page — this family, the
   clock family, all of them — wraps its rows in one `ColumnLayout` to carry the
   `visible: Config.isWidgetActive(...)` gate, and that wrapper has no `wantsCard`, so the
   card `Repeater` sees exactly one uncarded child and draws nothing. DESIGN.md §5.6 says
   "propagation must reach through containers"; it does not, one level up from where that
   sentence was written. Fixing it means teaching `ContentGroup` to recurse into a plain
   layout child, which is `modules/common/**` and out of every `sw-*` row's fence. Nothing
   here can be judged against §5.6 until it lands.

2. **Five orphaned config keys**, now that their switches are gone —
   `Config.qml:513` `circular_media.enableShadows`, `:514`–`:516` `showPrevButton` /
   `showNextButton` / `showDevicePill`, `:1085` `compact_media.enableInnerShadow`.
   Two more were already orphans with no UI at all: `:517` `circular_media.progressShape`
   and `:1083` `compact_media.backgroundShape` — neither is read anywhere and neither was
   ever exposed.

3. **`circular_media` vs `media_circular`** (`WidgetsRegistry.qml:212` and `:221`) are two
   distinct widgets whose ids differ only by word order. Any future `Config.isWidgetActive`
   call in this area is one transposition away from silently gating on the wrong widget.

## Motion

**None.** Not one `Behavior`, `NumberAnimation` or duration was added, removed or retimed in
this row — the seven pages contain no motion of their own and must not, per the brief: the
page's enter/exit is `ConfigSubPageHost`'s. Nothing for the cohesion pass to reconcile here.

## Gates

`check-design.py --diff` — 0 findings, 0 errors (whole tree, all eight rows, at the time it
ran). qmllint on all seven against a fresh shadow tree: clean apart from the two documented
blind spots — `Member "pagePlaceholderHeight" not found on type "QObject"` (singleton
sub-object, same as lane 1) and `Member "widgets" not found on type "qs::io::JsonObject"`
(pre-existing on every `Config.options.background.widgets.*` read in the repo).

No runtime gate was run: eight rows were editing at once, and a probe started mid-edit
reports someone else's breakage as yours. The parent runs
`tools/audit/probe-settings-pages.sh` once after all eight finish.
