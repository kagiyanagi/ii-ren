# sw-fingerprint — notes

Lane 2. Three files: `FingerprintConfig.qml`, `FingerprintEnrollOverlay.qml`,
`FingerprintHandPicker.qml`. The only live pages in the tranche with real state.

## The header, by hand

`FingerprintConfig` is one of the three `Item`-rooted pages, so the shared transform from
`sw-clock-configs` was not run on it. Adopted by hand: `title`, `showBackButton:
subPageRoot.showBackButton` and `onGoBack: subPageRoot.goBack()` on the **nested**
`ContentPage`, hand-rolled 31-line header deleted. `showBackButton` and `signal goBack`
stay on the `Item` root because that is what `ConfigSubPageHost` binds to — the page only
forwards them.

Behaviour change worth knowing: the old header hid button *and* title together when
`showBackButton` was false. `ContentPage` shows the title whenever it is non-empty and
gates only the button. That is the shared design, not an accident.

No `implicitHeight: 250` and no `PagePlaceholder` in these three files — nothing to
retoken there.

Four dead imports went with it (`QtQuick.Controls`, `Quickshell`, `Quickshell.Io`,
`Quickshell.Widgets`); qmllint flagged them and nothing in the file resolves through them.

## The ring is `CircularProgress`, and `ringRadius: 70` is gone rather than retokened

The hand-rolled ring was a `Repeater` of one capsule per enrollment stage, each placed by
`Math.cos`/`Math.sin` around a literal `ringRadius: 70` inside a literal 168×168 `Item`,
each with its own `Behavior on color` and `Behavior on scale`. On a match-on-chip reader
that is 16 rectangles and 32 `Behavior`s. It is now one `CircularProgress`, which is what
the brief asked for and what AOSP's own fingerprint enrolment draws.

**The brief said `ringRadius: 70` should come from `Appearance.sizes.*`. It does not — it
does not exist any more.** `CircularProgress` is sized by `implicitSize`, and I sized it
from the thing it encircles:

    implicitSize: scanSymbol.iconSize * 2

The ring's only job is to frame that 76px glyph, so the glyph is the honest source. That is
not a token and not arithmetic hiding one; it is a derived relationship. **No
`Appearance.sizes` entry is needed** — if a later session disagrees and wants one, the
value it would hold is 152 and the single caller is this line. `iconSize` stays a literal
76: a hero glyph is not a shared dimension and `check-design.py` does not flag icon sizes.

`lineWidth: 8` is likewise a literal the checker does not flag; it is on the 4dp grid and
2 (the widget default) is invisible on a 152px ring. The old capsules were `width: 4`.

Deleted with the `Repeater`: the per-tick `scale: filled ? 1.15 : 1` overshoot on
`elementMoveSmall`. `CircularProgress` animates its own sweep on `elementMoveFast`, which
`cw-progress` established is deliberately critically damped — a determinate indicator that
overshoots is reporting a number that never happened.

## The four edge states, and the one the service could not name

The brief's four had collapsed into two. `succeeded` and `failed` already read
differently; the other two did not exist on screen at all.

- **Sensor not found** — was a greyed-out "Start" button and nothing else. Now a
  `NoticeBox` at the pick step on `Fingerprint.probed && !Fingerprint.deviceAvailable`,
  icon `sensors_off`. `NoticeBox` derives severity from the icon, so a non-`error` icon
  renders tertiary-container: a missing reader is an absence of hardware, not a failed
  enrolment, and must not be red.
- **Enrolment failed** — `colError` on glyph, message and ring; the ring's *track* also
  goes `colErrorContainer` so the progress that was made stops looking like it counts.
- **Finger moved too fast** — `colTertiary` on glyph and message. Tertiary is the
  "adjust and go again" role and deliberately not the failure one.
- **Enrolment complete** — `check_circle` + `colPrimary`, and the message now goes
  `colPrimary` too (it was `colOnLayer1`, i.e. identical to mid-scan).

### Deriving "finger moved too fast" without touching the service

`services/Fingerprint.qml` is outside the fence and has no field for a retry, so it is
derived in the overlay. This is the non-obvious part of the diff and it is easy to
"simplify" back into a bug:

`fprintd_bridge.py` sends a retry through the *same* event as real progress —
`phase: "scanning"`, the stage held where it was, only `message` different
(`ENROLL_RETRY`). Text matching is out: `enroll-remove-and-retry` maps to *"Lift your
finger and touch again"*, which is the exact sentence a **passed** stage emits.

Two traps, both hit while writing this:

1. `handleEvent()` writes phase, then stage, then message. A naive "remember the stage in
   `onEnrollStageChanged`, compare in `onEnrollMessageChanged`" flags every successful
   stage pass as a retry, because the stage handler has already updated the remembered
   value by the time the message handler runs.
2. Comparing against a remembered stage instead fails the other way: two passed stages in
   a row carry an **identical** message, so `enrollMessageChanged` never fires and the
   remembered stage goes stale — the next real retry is then missed.

So it is a latch, not a comparison: `onEnrollStageChanged` raises `stageAdvanced` and
queues `Qt.callLater(clearStageAdvanced)`, which runs after the whole event has been
applied. The latch is therefore up for its own event's message and down for the next
one's. `sawScanning` excludes the run's opening "Touch the reader", which also arrives at
an unchanged stage. `resetRetryState()` is called from both `open()` and `beginScan()`.

If `Fingerprint` ever gains a real `enrollRetry` flag (it should — the bridge already
knows, it just does not emit it), delete all of this and bind to it. That is a
FINDINGS-level change, not a fence one; see below.

### Loading

`FingerprintConfig`'s "Your fingerprints" section rendered *nothing* until
`enrolledLoaded` — "still asking fprintd" and "asked, there are none" looked the same.
One `visible`/`text` flip: "Checking for enrolled fingerprints…" then "No fingerprints
enrolled yet."

## The hand picker: state lives in the fill and the state layer

`Digit` used `border.width: selected ? 0 : 1` and `border.color: enrolled ? colPrimary :
colOutlineVariant` — two pieces of state encoded as a border — and hand-swapped
`colLayer2Hover` / `colPrimaryContainerHover` for hover. **The selected digit had no hover
and no pressed state at all**, since its colour was a flat `colPrimary` ternary, and
nothing anywhere had a focus state.

Now: the fill carries selected (`colPrimary`) / enrolled (`colPrimaryContainer`) /
resting (`colLayer2`); a `StateOverlay` over each digit carries hover, focus and pressed
at the M3 opacities, composited, with hover and press excluding each other so they cannot
stack to the 0.16 drag token.

**The border stays, at constant width and constant `colOutlineVariant`** — it is linework,
not state. It has to: `colLayer2` (`m3surfaceContainer`) against the card's
`colLayer1Base` (`m3surfaceContainerLow`) is a four-unit difference in dark mode, so
without the outline the hand nearly vanishes. The palm already drew itself this way; the
digits now match it instead of contradicting it. This is not the 5.5 divider rule — that
is about separator bars between sections, not the outline of a drawn shape.

Keyboard: `activeFocusOnTab` plus Return/Enter/Space on the digit's `MouseArea`, so the
picker is reachable without a pointer and the focus layer has something to render.

**Accepted deviation:** the digit hit area is 24px wide (20px capsule + 2px margins each
side), under DESIGN.md 3.4's 32px floor. The digits sit on 24px centres in an anatomical
layout; a 32px target would overlap its neighbour and pick the wrong finger. The visual
*is* the target here and the targets are 62–96px tall. Left as is, deliberately.

## Motion — every timing that changed, for the 60fps cohesion pass

1. **Overlay scrim/content fade-out.** Was `elementMoveFast` (200ms) both ways. Now enter
   `elementMoveFast` 200ms, exit `elementMoveExit` 130ms, via the `fadeSpec`-assigned-
   inside-the-binding shape from DESIGN.md 2.9 (`WindowDialog` is the worked example).
   **Watch: the dialog must leave faster than it arrives.**
2. **Card scale.** Was 0.94 → 1 on `elementMoveFast`'s bezier both ways. Now enter 200ms
   `emphasizedDecel`, exit 100ms `emphasizedAccel`, assigned from `onShownChanged` for the
   same 2.9 reason. `transformOrigin: Item.Center` is now explicit — a modal belongs to no
   control on the page, so it grows from its own centre.
3. **Enrollment ring.** Per-tick colour (`elementMoveFast`) and per-tick scale-to-1.15
   (`elementMoveSmall`, overshooting) are **gone**. The sweep animates on
   `CircularProgress`'s own `elementMoveFast`, 200ms, no overshoot. **Watch: a stage pass
   is now one arc step, not 16 capsules popping.**
4. **Fingerprint glyph breath.** Was 750ms each way (1500ms cycle). Now
   `Appearance.animation.elementMove.duration` = 500ms each way (1000ms cycle), still
   `Easing.InOutSine`. **Watch: it must settle at full opacity, not half-faded, when the
   scan ends** — `alwaysRunToEnd` on an infinite loop completes the current *iteration*,
   which is why the success `check_circle` lands at 1. At 1000ms the worst-case trailing
   iteration is well inside the 1600ms auto-close (it was 1500ms of 1600ms before).
   `InOutSine` is kept on purpose: this is a symmetric oscillation, and every curve in the
   token table is one-directional and would make it lurch.
5. **Digit colour, hand picker.** Was a bare `ColorAnimation` borrowing only
   `elementMoveFast.duration` — no curve at all. Now the spec's own `colorAnimation`, so
   it carries `expressiveEffects` as well as the 200ms.
6. **Digit state layers (new).** Hover/focus/press fade on `StateOverlay`'s `FadeLoader`.
   Nothing to retime, but it is new motion on screen.

Nothing else in these three files animates.

## Effect budget — one FBO enters the tranche, deliberately

The brief's Cost line is "zero, and it stays zero", and the live half of this directory had
no `layer.enabled` anywhere. `CircularProgress` has one internally (`Shape { layer.enabled:
true }`). The brief also names `CircularProgress` as the widget to use, so the two
instructions meet here and reuse wins: **one** offscreen surface, one instance, at the
centre of a modal, not inside a delegate — in exchange for deleting a `Repeater` of up to
16 animated rectangles. No `layer.enabled`, `MultiEffect`, `OpacityMask`, shadow, `Canvas`
or sub-100ms `Timer` was *written* in any of the three files.

## Other

- Overlay now closes on Escape (DESIGN.md 3.7). Deliberately asymmetric with the scrim: a
  scrim click is refused mid-scan because it is easy to do by accident, Escape is not, and
  `close()` cancels the enrolment cleanly either way.
- Card radius `windowRounding` (18, the Hyprland decoration radius) → `verylarge` (30).
  4.2 puts a dialog at `large`/`verylarge`; the children at `large`/`full` stay smaller.
- "Stop" on the cancel button is now `root.scanning ? "Stop" : "Cancel"`. It read "Stop"
  on a *failed* enrolment, where nothing was running to stop.

## Gates

`check-design.py --diff` 0 findings 0 errors (all eight rows' added lines) ·
`check-design.py -v` has no remaining hit on any of the three files — the two literal
`750`s and `ringRadius: 70` are gone · `check-scaffold-containers.py`,
`check-button-states.py`, `check-text-primitives.py`, `check-m3-tokens.py` all pass ·
qmllint clean on all three, except one pre-existing `Member "security" not found on type
"qs::io::JsonObject"` at `FingerprintConfig.qml:24` — verified identical on the HEAD copy
of the file, it is qmllint's blind spot on a nested `JsonObject`, same class as the
`colX not found on type "QObject"` noise.

**Not run, per the row's fence:** no `qs`, no `iiren`, no probe, no smoke. The parent's
runtime gate is what proves this page still opens.

## Needs a change outside this fence

- `services/Fingerprint.qml` has no retry signal, and `scripts/fingerprint/fprintd_bridge.py`
  throws the information away. `fprintd_bridge.py:299-302` already tests
  `result in ENROLL_RETRY`; it emits the same `type="enroll", phase="scanning"` event as a
  real stage pass and only the message differs. One extra field there
  (`retry=True`) plus one `property bool enrollRetry` in the service would delete the whole
  latch described above. Both files are outside this row — **not changed, reported.**
- Nothing else. No caller of these three needs an edit: `FingerprintConfig` is loaded by
  `modules/settings/LockConfig.qml` through `ConfigSubPageHost`, which binds
  `showBackButton` and `goBack` on the `Item` root, and both are untouched.
