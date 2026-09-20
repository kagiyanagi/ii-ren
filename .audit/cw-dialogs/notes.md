# cw-dialogs — notes

## The three things the diff will not tell you

**`ToolTip.delay` works with a bound `visible`, and that is not obvious.** The
library drives `visible: internalVisibleCondition` rather than going through
`ToolTip.show()`, so the question was whether QQuickToolTip's `delay` survives a
binding on the property it defers. It does, measured on a throwaway
`FloatingWindow` harness before any of this was written: condition → visible was
475ms of a 500ms delay, the hide was immediate (correct — the wait is hover
intent, not a dismissal), and the binding still fired on the next toggle. A
delay implemented with our own `Timer` would have been strictly more code for
the same behaviour. `PopupToolTip` is not a QQC2 popup, so that one does get the
Timer.

**The QQC2 style, not this repo, was animating every tooltip.** `StyledToolTip`
has `background: null` and a custom `contentItem`, which makes it look like the
widget owns its motion — it does not. `Basic/ToolTip.qml` ships
`enter`/`exit` transitions of 300ms `OutQuad`/`InQuad`, symmetric, and they ran
on all 139 callers under whatever the content was doing on top. Overriding both
is what puts the fade on `expressiveEffects` at 200 in / 130 out. Measured on
the harness against the real widget: in 477→634ms to 0.999, out 1188→1284ms to
0.002, and the popup stays mapped for the whole exit.

**`Appearance.rounding.*` is not a padding.** `DialogListItem` padded itself by
`rounding.large` and `WindowDialog` by its own `radius`. `rounding.scale` is 0
in sharp mode, so both lost *all* of their padding the moment sharp mode was on
— text flush against the dialog edge. Neither is visible to `check-design.py`,
because a token is exactly what it wants to see. `check-dialog-surfaces.py`
asserts no family file pads from a rounding token; the same shape is worth
grepping for library-wide (`grep -rn 'adding:\s*Appearance\.rounding'`).

## What changed that a caller might notice

- **Every tooltip now waits ~500ms.** That is DESIGN.md 9 and it is a large
  perceptual change across 139 callers. `ScrollHint` already implements its own
  500ms wait, so it now waits 1000 — see below, it needs a one-liner.
- **Dialog padding 23 → 16** (and 30 in sharp mode → 16). `WindowDialogButtonRow`
  lost its `Layout.margins: -8`, so the buttons land at 16 from the edge where
  they used to be at 15. Net movement is a pixel; the dialogs are ~14px tighter
  vertically, and the three with a hardcoded `backgroundHeight` (600/640/670)
  only gain slack from that.
- **`WindowDialogButtonRow` fills its width.** Every caller already puts an
  `Item { Layout.fillWidth: true }` beside its buttons and none of those fillers
  had any width to take, so the whole group sat at the dialog's *left*. Now
  `[Details]…[Done]` spreads and `[filler][Cancel][OK]` right-aligns — which is
  what the call sites were written to produce.
- **Three NoticeBoxes turn red**: `ServicesConfig.qml:593`,
  `widgets/FingerprintConfig.qml:398`, `widgets/ScreenRecordingConfig.qml:409`.
  They pass `materialIcon: "error"`, and `NoticeBox.error` defaults off that.
  The `"warning"` ones deliberately stay tertiary: this palette has no warning
  role, and tertiary container *is* the notice tone.

## Rejected

- **Rebuilding `SelectionDialog` on `WindowDialog`.** It is the reuse answer —
  it would inherit the scrim fade, the enter/exit, elevation, Escape and
  dismiss-on-outside-click, and delete ~40 lines. It also changes the surface's
  width model (WindowDialog centres a `backgroundWidth`; SelectionDialog fills
  its parent minus a margin) and its only caller is the translator's language
  picker, which no test and no script can exercise. Not worth it blind. It got
  the divider removal, the card, `verylarge`, the grid, and `WindowDialogTitle`
  instead. **It still has no enter or exit animation** (anti-pattern 10): the
  caller controls it with `Loader.active`, so an exit needs the caller to hold
  the loader open. That is `Translator.qml`'s row, not this one.
- **An opt-in `error: false` on `NoticeBox`.** Honest, and completely inert:
  rule 1 of this parallel run forbids touching the 38 call sites, so the shell's
  failure surface would have stayed tertiary and the audit would have claimed a
  fix it did not make. Deriving from the icon the callers already pass changes
  the three real error boxes today and stays overridable.
- **Deleting `WindowDialogSectionHeader` too.** It has zero callers, same as the
  separator, and 5.5 names `ContentSubsection` as the way a dialog groups
  content — so it is arguably redundant. The brief named one deletion and
  DESIGN.md 9's recipe names the other parts, so it stayed and took the
  whitespace treatment (`colSubtext`, `pixelSize.normal`, `Layout.topMargin: 8`
  on top of the column's 16) rather than being a second title at 22/550. If a
  later session wants it gone, nothing references it.
- **Touching `NoticeBox`'s run-detection.** ~100 lines of sibling-scanning that
  decides first/last/pressed by walking `parent.children` and sniffing
  `typeof topLeftRadius`. It works, the single-item case is correct
  (`isFirst && isLast` → all four corners `large`), and rewriting it would be a
  large blind diff in the widget with the most callers in this family.
  One real wart left alone: `rFull` is `min(height/2, rounding.large)`, and
  every notice is taller than 46px, so the press morph is a no-op on the run's
  outer corners and only the seams move.
- **`StyledToolTipContent` keeping `shown`/`isVisible`.** Both call sites now
  fade from outside it, so the property, the `isVisible` probe, three Behaviors
  and the `clip` all went. It is a box again. qmllint lost two
  `Could not find property "shown"` warnings with them.

## Needs a change outside this family

Apply serially, in any order. Each is one line.

1. **`.github/DESIGN.md:703-704`** — the Dialog recipe still lists the deleted
   part. Replace:
   ```
   **Dialog** — `WindowDialog` and its `WindowDialogTitle`/`Paragraph`/
   `ButtonRow`/`Separator` parts. Scrim behind, elevation 5, radius `verylarge`,
   ```
   with:
   ```
   **Dialog** — `WindowDialog` and its `WindowDialogTitle`/`Paragraph`/
   `SectionHeader`/`ButtonRow` parts. Scrim behind, elevation 5, radius `verylarge`,
   ```
2. **`.github/DESIGN.md:524-525`** and **`AGENTS.md:193`** both name
   `WindowDialogSeparator` as a thing not to insert. The type no longer exists,
   so the sentences should name the shape instead — "hairline divider lines or
   separator bars". Cosmetic; the rule itself is unchanged.
3. **`tools/check-design.py:205`** — the `no-separator-bars` rule matches the
   type by name and can now only fire on prose (it fired on a code comment in
   this session, which is why `WindowDialogSectionHeader.qml` says "a hairline
   divider" instead). Worth keeping as a resurrection tripwire;
   `check-dialog-surfaces.py` also asserts the file does not come back.
4. **`modules/ii/bar/ScrollHint.qml:32`** — add `delay: 0` to its
   `PopupToolTip`. It gates `extraVisibleCondition` on its own 500ms
   `showHintTimedOut` timer, and PopupToolTip now waits 500 of its own, so the
   hint would take a second. Deleting that Timer and the `showHintTimedOut`
   property instead is the root-cause version — the widget does the job now.
5. **`modules/ii/polkit/PolkitContent.qml:89`** — `Layout.bottomMargin: 10
   // I honestly don't know why this is necessary` can go. It was compensating
   for `WindowDialogButtonRow`'s `Layout.margins: -8`, which is deleted.
6. Optional, cleanup only: `modules/settings/HermesConfig.qml:641` hand-writes
   `visible: page.billingNotice.length > 0` next to `text: page.billingNotice`;
   `NoticeBox` now does that itself. And
   `modules/settings/QuickConfig.qml:631` pulls a NoticeBox up with
   `Layout.topMargin: -20`, which is the negative-margin hack design law 11
   forbids.

## Still needs a running shell

Nothing here was verified against the live shell — the harness covered the
tooltip timing and that `WindowDialog` builds, lays out and collapses, but not
how any of it looks.

- The **dialog shadow** over a full-screen `colScrim`. It is the elevation 5 the
  recipe asks for, and it may be nearly invisible against a 50%-black scrim.
  Cheap (`cached: true`, one instance) either way.
- **`SelectionDialog`'s card**: it paints `colSurfaceContainerHigh` inside a
  dialog that paints `m3surfaceContainerHigh`, i.e. the same tone, so the "card"
  reads as a clip region rather than a card. That is exactly what `WifiDialog`
  does and 5.5 calls that the worked example, so it is consistent — but if the
  two dialogs are meant to show a visible card, both change together.
- **The 500ms tooltip delay in the bar**, which is where it will be felt most.
- The three NoticeBoxes that are now `colErrorContainer`.

## Harness

`qs -p <file>` resolves the `qs.*` imports relative to the file's own directory,
so a harness that imports the widget tree has to sit in
`dots/.config/quickshell/ii/` — lowercase, so `mkshadow.sh` ignores it and it is
not a QML type. Delete it before finishing. Two gotchas that cost time:

- `StyledToolTip` on a parent that is not a `Control` is **always visible**:
  `parent.hovered === undefined` is truthy in its own condition. Hang the
  harness tooltip on a `Button`, not an `Item`, or it opens at startup and every
  measurement is of the wrong thing.
- `qs -p` reloads when the file changes, and the reloaded instance logs
  alongside the old one. Write the harness, then run it — editing between runs
  interleaves two timelines into one log.
