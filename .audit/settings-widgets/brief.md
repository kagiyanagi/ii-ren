# settings-widgets — brief

One brief for the nine live rows in `families.md`, because they are nine instances of one
surface: **a settings sub-page**. Written per cluster so they come out coherent; a row that
needs to depart from this says so in its own `notes.md`.

`sw-dead` has no design content and is not covered here. Its whole brief is: delete the
122 files listed in `families.md`, drop `modules/settings/widgets/qmldir` and the four
`import qs.modules.settings.configs.widgets` lines that only it makes resolvable, then
prove the settings app still opens every live sub-page. See `notes.md` before starting it.

---

## The shared brief — every live row

**Purpose.** Change one thing about one widget, and see it change on the desktop behind
the settings window.

**Primary action.** The first control under the first section header. Everything else on
the page is secondary and must look it: one column, no competing accents, no control
styled larger than the rest to draw the eye.

**Hierarchy.** Back arrow and page title first — they are the only thing at the top and
they say where you are. The first `ContentSection` second: its icon and title, then its
rows. Everything after that reads in document order and needs no emphasis at all. When the
widget the page configures is switched off, the `PagePlaceholder` outranks all of it and
is the only thing in the section.

**Reference.** Android 16 Settings, a second-level screen (Settings → Display → Lock
screen). Large title under a plain back arrow, options grouped into container cards with a
leading icon per group, a switch row as the atom. That one because these pages *are* that
screen: a list of independent options with no ordering, no wizard, no confirmation.

**Interaction.**

- The page's own enter and exit are `ConfigSubPageHost`'s and are already correct —
  `Appearance.animation.elementMove` in, the fast effects spec out at a quarter the
  duration, monotone. Do not re-animate the page root. A row that finds itself writing a
  `Behavior` on `x` or `opacity` at the page root has misread this brief.
- The header's back button is a `RippleButton` and inherits all four states from
  `cw-buttons`' root. It must not re-declare a hover or pressed colour; the secondary
  container tokens are its colours.
- Every option row is a `ConfigSwitch` / `ConfigSlider` / `ConfigSpinBox` /
  `ConfigSelectionArray` / `ConfigTextField` from `modules/common/widgets` — all five were
  audited in `cw-config-rows` and `cw-inputs` and carry their own focus, hover, pressed and
  disabled states. A row that draws its own control has a reuse miss to justify in writing.
- A control whose option does not apply right now is `opacity: 0.4` and disabled, not
  hidden — except where the whole group does not apply, which is a `visible: false` on the
  group.
- Transform origin: the sub-page grows from the right edge, because that is where
  `ConfigSubPageHost` slides it in from. Nothing inside the page has its own origin.

**Edge states.**

- **Widget off.** `PagePlaceholder` with the widget's own icon, its name, and one sentence
  naming where to switch it on. Most pages have this; the row makes the wording and the
  icon consistent across its family rather than inventing new copy.
- **Empty.** A section with no rows does not render — not an empty card.
- **Loading.** Only `sw-fingerprint` and `sw-extensions` have one; both are covered below.
- **One item.** A `ConfigSelectionArray` of one option still renders as a chip row, not as
  a label. Do not special-case it.

**Cost.** Zero, and it stays zero. The live half of this tranche contains no
`layer.enabled`, no `MultiEffect`, no `OpacityMask`, no shadow, no `Canvas` and no
sub-100ms `Timer` — every effect in the whole directory sits in a file `sw-dead` removes.
No row here may add the first one. A preview that seems to need a mask is a preview that
should be a `MaterialShape`.

**Delete.**

- **The 61 hand-rolled headers.** 61 of the 70 live files open with the same ~28 lines: a
  `RowLayout`, a 40dp circular `RippleButton` with four radius properties spelled out, an
  `arrow_back` `MaterialSymbol`, a title `StyledText`, plus
  `property bool showBackButton: false` and `signal goBack()`. `ConfigSubPageHost`'s
  docstring already asserts this lives in `ContentPage`. It does not. **`sw-clock-configs`
  puts it there** — `title`, `showBackButton` and `goBack()` on `ContentPage`, the header
  rendered as the first child of its column and `visible: root.title !== ""` so a
  `ColumnLayout` skips it entirely for the 174 existing callers that set no title — and
  then every later row deletes its family's copies. Additive only: no existing property
  changes meaning, which is what rule 9 asks for. `check-scaffold-containers.py` gains the
  assertion that the header renders its states and that a titleless page reports the same
  implicit width as before (decision 21 is why that second half is not optional).
- The literal `implicitHeight: 250` on each placeholder wrapper, and the back button's
  40dp, written four different ways across the copies — one of them as
  `Appearance.sizes.elevationMargin * 4`, which is arithmetic hiding a literal. The shared
  header declares it once; if it wants a name, `Appearance.sizes` is where the name goes.
- Duplicated `Translation.tr()` strings that differ only in the widget's name.

**Out of scope.** The widgets these pages configure — `modules/ii/background/widgets` is
permanently out (`AUDIT.md`, re-port hazard), and a page here may not be "fixed" by
changing the widget it configures. `Config.qml`'s schema: a missing option is a finding for
`FINDINGS.md`, not a config change made in passing. The settings *pages* themselves
(`modules/settings/*.qml`) are their own queue rows.

---

## Per row

**`sw-clock-configs`** (6 files, lane 1). Owns the `ContentPage` header extraction above,
and is first for that reason. Its own six pages are the elaborate ones — `Concentric` at
637 lines and `ClockWidget` at 438 carry real option sets (hands, ticks, faces, ranges), so
they are also the honest test that a shared header survives contact with a page that has
more than two sections. Hierarchy per page: back + title, then the face's own geometry,
then colour, then the global visual options last, because they are not about this widget.

**`sw-clock-styles`** (12 files, lane 2). Twelve near-clones of one page. The whole row is:
adopt the shared header, and make the twelve agree with each other — same section order,
same placeholder wording, same icon vocabulary. If two pages disagree after this row, the
row is not done. `DateDesktopWidgetConfig` joins them because it is the same page for the
date widget; it also carries a stray
`import qs.modules.settings.configs.widgets` that resolves only through the doomed
`qmldir` — drop it, the type it wants is its own directory sibling.

**`sw-weather-calendar`** (15 files, lane 2). Nine weather pages and six calendar pages,
all short. Same treatment as `sw-clock-styles`. The one design call: weather pages that
expose a units option must place it first — it is the option people came for — and calendar
pages that expose a "which calendar" option must place that first, for the same reason.

**`sw-media-configs`** (7 files, lane 2). Seven media widget pages. Watch for controls that
duplicate what the media widget itself offers; a page here configures appearance, not
playback.

**`sw-system-pills`** (11 files, lane 2). CPU / RAM / disk / battery / bluetooth pills, all
of them a threshold plus a format. `DesktopResourceFillCardsConfig` is the largest and sets
the pattern the other ten follow. `BatteryConfig.qml` is *not* here: it looked reached until
the url pattern was anchored at a path separator, and its only apparent caller was the
string `"widgets/DesktopBluetoothBatteryConfig.qml"`. It is in `dead.txt`.

**`sw-desktop-misc`** (11 files, lane 2). The odd ones out: notification list, quote,
at-a-glance, water reminder, photo, notes. `DesktopWidgetVisualOptions` lives here — it is
the one existing piece of shared vocabulary in this directory, the block that was
copy-pasted into 50 pages before someone extracted it, and it is the model for what the
header extraction above does next. The three 9-line photo variants are aliases of one page;
if they are still 9 lines each after the row, that is correct.

**`sw-fingerprint`** (3 files, lane 2). The only live pages with real state: enrolling.
`FingerprintEnrollOverlay` is a progress surface, not a config page — the brief for it is
M3's determinate circular progress: the ring is `CircularProgress` from
`modules/common/widgets` (`cw-progress`), its literal `750ms` durations come from
`Appearance.animation.*`, and its `ringRadius: 70` from `Appearance.sizes.*`. Edge states
that must each read differently: sensor not found, enrolment failed, finger moved too fast,
enrolment complete. `FingerprintHandPicker` is a selection surface — the selected finger
carries the state layer, not a border.

**`sw-extensions`** (3 files, lane 2). `WidgetExtensionsContent` (486) and
`WidgetCommunityContent` (227) are browse-and-install lists, the only pages in the tranche
with a network edge state. Each needs: loading, empty, offline, and install-in-progress,
and none of them may be a spinner over a greyed page — the list keeps its shape and the
rows fill in. Their seven literal `100ms` / `150ms` durations are the only
`check-design.py` hits in the live half besides fingerprint's; they go.
`ExtensionWidgetSettingsRenderer` renders third-party option schemas: its job is to make an
extension's options look exactly like a first-party page, which means it emits the same
`Config*` row widgets and no others.

**`sw-advanced-pages`** (2 files, lane 2). Themed icons and custom cursor, both reached
from Advanced. Both are pickers with a preview; the preview is the primary element and
belongs above the options, not beside them.
