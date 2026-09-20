# cw-inputs — notes

## The family had three states everywhere and four nowhere

Finding 1 was not "some widgets miss focus" here — **not one of the seven value
controls read `visualFocus` or rendered `activeFocus`**. Sliders, switch, radio,
both combo boxes and the spin box all shipped hover + press and stopped. The
settings app is the keyboard-navigable half of the shell and it is built almost
entirely out of these, so a Tab through a settings page moved a focus ring that
did not exist.

Two mechanisms, split by what the control *is*, and the split is deliberate:

- **`visualFocus` for anything you click** — switch, radio, sliders, combo
  boxes. It is the keyboard-only half of `activeFocus`, so clicking a switch
  does not leave a film sitting on it.
- **`activeFocus` for anything you type into** — the spin box's number field,
  `AddressBar`'s path entry, `MaterialTextArea`'s indicator. A text field that
  was clicked into *is* focused and has to say so; that is the one §3.7 calls
  out by name.

Where a container colour already carried hover and press (`colSecondaryContainer`
+ its Hover/Active siblings on the combo boxes, `colLayer2Hover/Active` on the
spin box), only the missing state was added — a `StateOverlay` bound to
`focused:` alone, or the layer's Active sibling, which *is* the 0.10 mix.
Stacking a full four-state overlay on top of a working colour ternary would have
doubled hover to ~0.16, which is the drag token.

Where there was no container colour at all — switch handle, radio ring, slider
handle — the whole `StateOverlay` went in, sized to the AOSP state-layer token
for that component (`SwitchTokens.StateLayerSize` 40dp, `RadioButtonTokens`
40dp). They overhang their 24dp/20dp paint, which is what M3 draws and what the
radio's old hand-rolled hover circle was already doing by growing 20 → 40.

## The sliders

`StyledSlider`/`StyledVerticalSlider` had the M3 Expressive squeeze already and
correctly — `handlePressedWidth: 1.5` against `handleDefaultWidth: 3` is
Material3 `Thumb`'s `thumbSize.width / 2`, transcribed. What was wrong is that
it ran on `elementMoveFast`: a **size**, on an effects spec. Both sliders'
handle and margin Behaviors are now `elementMoveSmall` (fast spatial), which is
§9's "thumb on fast spatial" exactly. Track colour had *no* Behavior at all; it
now has `elementMoveFast` (default effects), which matters most on the vertical
one, where the fill swings to `colErrorContainer` above `to`.

Three things died:

- **`valueAnimationDuration`** — an exported duration knob with
  `Easing.OutCubic` hard-coded, the brief's finding-3 shape. It defaulted to 0,
  its Behavior was `enabled: valueAnimationDuration > 0`, and **no caller in
  the shell set it**, so the whole thing was dead code that only existed to
  invite a literal. Deleted rather than tokenised: turning it on would newly
  animate `value` on six OSD/quick-toggle callers driven by live audio, which
  is a feel change nobody asked for. If the vertical slider should smooth like
  the horizontal one does, copy the horizontal `SmoothedAnimation` — do not
  bring the knob back.
- **`Behavior on y` on the vertical slider's value label.** The handle's own `y`
  is not animated, so a 200ms effects spec on the label left the number trailing
  the handle it belongs to. Deleting it welds them.
- **`layer.enabled` + `layer.samples: 4` on the vertical handle.** A `Rectangle`
  antialiases its own rounded corners, so the framebuffer bought nothing — and
  it clipped everything drawn outside the 4dp bar, which is why the state layer
  could not have been a child of that handle until it went (§8).

The value label also stopped using `font.bold` (§7 wants the variable axis, and
`StyledText` clears the axes for a digit-only string, which makes `font.weight`
the working mechanism there).

## The combo boxes

Both had the same hand-rolled fade — one `PropertyAnimation` on opacity, the
same duration in each direction. That is not §9's popup motion and not an
enter/exit pair. Both now carry the `arrowPopup*` transcription verbatim from
`HermesApprovalModeMenu`, plus `transformOrigin: Item.Top` (the list drops out
of the field), `verylarge` radius and a 10px gap.

**Padding went 8 → 12 for a geometric reason, not a style one.** At
`rounding.verylarge` (30) the card's left edge at y=8 sits at x≈9.6, so an 8px
inset row pokes ~1.6px outside the corner arc — the `ConfigListViewEntry` bug
the brief describes, in miniature. At 12 the arc is at x≈6 and the row clears
it. §5.2 wants 12–16 for a popup anyway.

`highlighted` is read off `ListView.view.currentIndex`, **not**
`root.highlightedIndex`: the search variant's arrow keys call
`listView.incrementCurrentIndex()`, which breaks the
`currentIndex: root.highlightedIndex` binding, so `highlightedIndex` stops
moving after the first keypress. The view is the one that is right in both
files. Before this, arrowing through either popup highlighted nothing at all.

**Known and not fixed:** in `StyledComboBoxSearch`, filtered-out rows are hidden
with `visible: false` but still occupy indices, so the arrow keys step through
invisible entries. A proper fix is a filtered model, which changes the widget's
model contract and every caller's expectations — out of scope for a states-and-
motion pass.

## The I-beam, fixed once

`TextInput`/`TextArea` set no cursor, so `AddressBar` and `MaterialTextField`
each laid a `hoverEnabled` no-button `MouseArea` over the text to get one. That
is the root-cause shape: the handler now lives in `StyledTextInput`,
`StyledTextArea`, `MaterialTextArea` and `MaterialTextField`, and `AddressBar`'s
copy is gone. `HoverHandler`, not `MouseArea`, on purpose — a hover-enabled
`MouseArea` takes hover off whatever is under it, and several of these sit
inside rows that need their own hover.

## What a script cannot see, and now does

`tools/check-input-states.py`. One concern: the seven shared value controls
render focus, press and disabled. Focus has to be a *binding* whose value reads
the flag — a bare mention fails, which is the §3.7 failure mode exactly. For the
sliders the press assertion is the squeeze (`handlePressed* < handleDefault*`),
because that is how a slider renders a press. It also fails if an eighth value
control appears, for the same reason `check-button-states.py` does.

All assertions mutation-tested: focus unbound, dim removed, squeeze flattened,
pressed size deleted.

## Rejected

- **`AddressBreadcrumb` → `StyledListView`.** The pack suggests it and it is
  wrong: `StyledListView` is vertical throughout — `ScrollBar.vertical`, a
  `Behavior on contentY`, `y` transitions, and a `remove` transition that slides
  `x` to `root.width`. On a horizontal breadcrumb the remove animation would
  throw rows sideways across their own strip. The overscroll stretch is `yScale`
  only, so there is nothing to inherit either.
- **Crossfading `AddressBar`'s breadcrumb ↔ path-field swap** with `FadeLoader`.
  They overlap `anchors.fill`, so mid-fade both are visible *and* both accept
  input; the field is focused while invisible. Not worth it for a swap the user
  triggers deliberately.
- **A shared `ArrowPopupEnter`/`ArrowPopupExit` `Transition`.** The recipe is
  now duplicated in four files (the two Hermes surfaces and these two). A
  `Transition`-rooted .qml would collapse them and is legal QML — but the brief
  says a family records a gap rather than adding a widget. **Recorded: this is
  the library's most-copied 40 lines.**
- **`spacing: 2` → 4 on `AddressBreadcrumb`.** `ButtonGroup` uses 4 for the same
  `SelectionGroupButton`, but 2 is on the grid `check-design.py` enforces and
  the seam is deliberate. No rule behind the change, so no change.
- **Renaming `StyledSwitch.scale`** — see below.
- **Deleting `WindowDialogSlider`.** It has **zero callers** and qmllint agrees
  it is inert. `cw-dialogs` is deleting `WindowDialogSeparator` for exactly that
  reason this session, so the type belongs to that judgement, not this one — and
  deleting a type a sibling might be wiring up mid-run would be hostile. Fixed
  in place (`spacing: -2` → 4) and flagged here.

## Needs a change outside this family

**1. Required — `modules/ii/bar/SysTrayMenuEntry.qml:74`.** `StyledRadioButton`
now dims at `opacity: 0.4` when disabled (§3.1), and this caller uses
`enabled: false` to mean "display only", not "disabled". Without this the tray
menu's radio indicators render at 40%. The file already uses this exact pattern
on its own root (`enabled: !menuEntry.isSeparator; opacity: 1`):

```qml
                sourceComponent: StyledRadioButton {
                    enabled: false
                    opacity: 1 // `enabled` is "not interactive" here, not "disabled"
                    padding: 0
                    checked: root.menuEntry.checkState === Qt.Checked
                }
```

**2. Optional — `StyledSwitch.scale` shadows `QQuickItem.scale`** (qmllint
`property-override`, anti-pattern 9's shape). It works today because the QML
property shadows the C++ one for name resolution and nothing animates the real
`scale`, but any future press-scale on a switch would drive the wrong property.
The rename is one line here plus three callers:

- `modules/common/widgets/StyledSwitch.qml:11` — `property real scale: 0.75` → `property real sizeScale: 0.75`, and `root.scale` → `root.sizeScale` throughout the file (10 occurrences)
- `welcome.qml:100` — `scale: 0.6` → `sizeScale: 0.6`
- `modules/ii/bar/cards/AlarmsCard.qml:563` — `scale: 0.75` → `sizeScale: 0.75`
- `modules/ii/sidebarPolicies/Anime.qml:524` — `scale: 0.6` → `sizeScale: 0.6`

Not done here because it breaks three callers the instant it lands, and it buys
no user-visible behaviour.

## Needs a running shell to verify

None of this could be looked at — the orchestrator's smoke pass is the first
time any of it renders.

1. **The switch halo across ~129 `ConfigSwitch` rows.** The 40dp state layer
   overhangs the 32dp track by ~3px at `scale: 0.75`. That is M3, but
   `ConfigSwitch` is itself a `RippleButton` that lights its own film on hover,
   so hovering a settings row now shows the row film *and* a blob on the switch.
   Compose does the same thing (separate interaction sources), but it is the one
   change here with real blast radius.
2. **The slider handle halo on the media surfaces.** `hovered` is true for the
   whole slider, not just the handle — correct per Compose, which hands the
   slider's interaction source to the Thumb — so hovering a media progress bar
   pops a circle at the seek handle. Six media/OSD callers.
3. **Combo popups**: the ArrowPopup scale, the `verylarge` corner against the
   first row, and the 10px gap. `HermesModelPicker` is the only
   `StyledComboBoxSearch` caller; `BackgroundConfig`/`GeneralConfig`/
   `HyprlandConfig` are the plain ones.
4. **`StyledRadioButton` in the system tray.** The ring was `width: 20` on an
   item a `RowLayout` manages — qmllint's "undefined behavior", and the layout
   had every right to zero it. It is `implicitWidth: 20` now, which is
   well-defined and may land differently from whatever it happened to do before.
5. **The vertical slider handle without its framebuffer** — corner AA on a 4dp
   (2dp pressed) pill.
6. **`MaterialTextArea`'s indicator** thickening 1 → 2 on focus.

## Coupling the next session should not trip over

**`SearchHandler.qml` is not self-contained, and that is now explicit.** Its 24
lines referenced `page`, `root` and `highlightOverlay`, none of which it
declares. They resolve off the *creation-context chain* of whatever instantiated
it — which is why they work at all: `ConfigSwitch` supplies `root` and
`highlightOverlay` one level up and the settings page supplies `page` two levels
above that. Where the chain is missing one, a bare reference **throws a
ReferenceError** rather than evaluating to undefined, and here the throw
happened inside a `Qt.callLater`, so it never reached the caller — the row just
silently failed to scroll. Same trap `cw-scaffolding` measured in
`ContentSection.Component.onCompleted` this session; same `typeof` guard applied,
so it fails soft and the file says out loud what it needs. qmllint is silent
about it because the references sit inside a closure it does not walk.

Giving it real properties is the actual fix and it is an eight-call-site change
(`ContentSection`, `ContentSubsection`, `ConfigSwitch`, `ConfigSlider`,
`ConfigSpinBox`, `AdvancedConfig` ×2, `LockConfig`), five of them other
families' files. For whoever does it: `root` is `searchHandler.parent` at every
call site, and `highlightOverlay` is a sibling of the handler with a
`startAnimation()` — both are findable without an API change. Only `page` needs
passing.
