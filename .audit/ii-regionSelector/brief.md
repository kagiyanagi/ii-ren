# ii-regionSelector — brief

Nine files, two surfaces. The selector (`RegionSelector` → one `RegionSelection` window
per screen) freezes the screen, dims it, and turns a drag, a click on a target or a drawn
circle into one action: copy (or annotate, right button), Lens (or ask AI), read text, scan
a QR code, record. `ScreenshotPreviewPopup` is the card that follows a copy in
clipboard-only mode, offering Save / Edit / Delete.

**Purpose.** Pick part of the screen and do the one thing the keybind asked for.

**Primary action.** The selection itself: a drag, or a click on a highlighted window or
content region. It is not a button, so it has nothing to compete with. The toolbar, the
close FAB and the cursor guide are secondary and must stay that way.

**Hierarchy.** The frozen screen under a scrim, with the selection cut out of it, comes
first. Then the target under the pointer (thicker border and a film). Then the cursor
guide, the action's icon in `colPrimary`, pointed at the cursor. Last, the floating toolbar
(Rect | Circle) with its paired close FAB, low and centred.

**Reference.** Circle to Search, still Android 16's freeze-and-select surface: the frozen
screen dims, a tap selects the thing under it, a drawn stroke selects its bounds, and a
floating bar sits low and clear of the navigation area. The rectangle is SystemUI's
`CropView`: a scrim outside the crop and a solid frame, no marching ants. The preview card
is the screenshot shelf's thumbnail: it slides in from its corner and swipes away.

**Interaction.**

- **The selector gets an enter and an exit (2.5, anti-pattern 10).** Today it has neither.
  The window is bound straight to `Loader.active`, so it appears undimmed and is destroyed
  on the frame it is dismissed. The whole window fades in on `elementMoveFast` (the scrim
  spec, 6.2) and out on `elementMoveExit`, with the spec assigned inside the binding that
  drives the fade (2.9). The per-screen `Loader` is latched (`rendered`, set on the edge)
  and released by the window once the fade reaches 0, as in the cheatsheet. Each request
  gets a new instance, never the old one reopened: `retrigger` closes and reopens in one
  turn to stop a recording, and the new instance's `pidof` check is what stops it.
- **Leaving is passive.** From the moment the request clears, the window takes neither
  pointer nor keyboard: the empty mask and `WlrKeyboardFocus.None` it already uses for a
  recording's border. A click during the fade must not start a second snip.
- **Click versus drag uses Qt's drag threshold** (`Qt.styleHints.startDragDistance`),
  latched per press. Today it is exact equality, so a tap that wobbles one pixel is a 1px
  drag: the window under it is not taken and a 1×1 crop is. Until the threshold is crossed
  the target under the pointer stays highlighted, and the outline and size label do not
  draw. Nobody needs "0 × 0".
- **A click can only take what is drawn.** `updateTargetedRegion` searches layers and
  windows whatever the config says. Invisible targets catch clicks in circle mode and with
  `targetRegions.layers` off (the default). Hidden layers still remove every window they
  overlap from the list: here a 1×1 helper surface in the corner makes a fullscreen window
  unclickable. Layers that are off are not computed at all, and windows are looked up only
  when they are drawn.
- **Nothing selected means nothing happens, and the selector stays.** `snip()` warned,
  dismissed, and then *carried on*: there is no `return`. It handed magick a zero size,
  which magick reads as "from here to the corner". Proven with a probe: the rest of
  `snip()` keeps running after the `Loader` destroys the window, and its `execDetached`
  fires. A right-click on bare desktop opens the annotator on that corner crop. In OCR
  and QR mode the empty click reads the corner crop, and in Search mode it uploads that
  crop to a public host. It is an early return now, before any region property is
  written. The frozen frame cannot be taken again, so a stray click must not throw it away.
- **The screen clamp intersects rather than slides.** A padded window target at a screen
  edge hangs off it, and sliding it back in captured a strip of whatever was beside it.
- **Toolbar.** Rises from below the screen edge on `elementMove`, bound to the window
  showing rather than pushed from a `Connections`. It sits 8 above the shell's reserved
  band (Hyprland's `reserved` bottom, i.e. a pinned dock or a bottom bar), not 8 above the
  screen edge. On this machine it sits on the frozen dock and reads as part of it. The mode
  tabs stop writing through a pair of `Synchronizer`s, which log a `modeIndex` binding loop
  on every open. The toolbar gets the mode as a plain binding and asks for a change with a
  signal. The FAB gap is 8, on the grid.
- **Cursor guide.** Hides its hint on the first press. Until then the hint stays up for a
  Toast's `SHORT_DELAY` (2000ms, `NotificationManagerService`), not 1000ms, which is too
  short to read a seven-word line. Sized as an icon button (40, icon 24, 8 before the icon
  and 16 after the label). Radii from `Appearance.rounding` (pointed corner `unsharpenmore`,
  the rest `full`). The dead `Behavior on topLeftRadius` goes. `snip()` stops rewriting
  `root.action` (Copy→Edit, Search→AskAI) and uses a local instead: that write re-opened
  the guide's hint during the exit.
- **Targets fade in.** Content regions arrive once detection finishes, well after the
  window has faded in, and a `Behavior` never animates a delegate's first value, so they
  pop. Each target fades in on `elementMoveFast` when created.
- **Preview card.** Enter stays `elementMoveEnter`; exit moves to `elementMoveExit` (it ran
  both directions on the enter spec), assigned in the `x` binding as the Fast Pair card
  does. The dodge on `y` goes to `elementMove`, interruptible, the same as the notification
  stack's. It gains `SwipeToDismiss` (3.6), like the clipboard toast and the Fast Pair
  card it stacks with. A swipe is a discard, the same as letting it time out: the shot is
  already on the clipboard.

**Edge states.**

- *Preparing* (grim running, ~100ms): nothing is mapped. A dismiss here closes at once.
  There is nothing to fade.
- *No targets* (empty workspace, detection off or still running): only the scrim, the aim
  lines and the guide. A click does nothing, and a drag works as normal.
- *Content regions late*: they fade in when detection lands.
- *Selection at an edge*: the size label goes below the region's corner if there is room,
  above it if not, and inside the screen either way.
- *Recording* (Post phase): the frozen frame, scrim, toolbar, guide and targets cut out
  together. The frame has to go on the first frame so the recording sees the live screen,
  and the chrome goes with it. The outline stays, just outside the region so it is never
  recorded, and it now stays still: the bar's `RecordIndicator` says a recording is
  running. When the recording ends, the outline fades out on the exit.
- *Several screens*: one selector per screen as today, each with its own latch.
  `showOnlyOnFocusedMonitor` is unchanged.
- *Preview never ready* (the crop fails): no card, as today.

**Cost.** Two things go. `CircleSelectionDetails` put `layer.enabled` on a full-screen
`Shape`, an offscreen framebuffer the size of the screen that buys nothing because
`CurveRenderer` antialiases in its own shader. The selection outline was `DashedBorder`, a
`Canvas`, which clears, strokes and re-uploads a texture the size of the selection on every
pointer move of a drag. It is a `Rectangle` border now. The breathing pulse also goes: it
was an infinite animation (literal 1200ms `InOutQuad`) that repainted a full-screen overlay
at 60fps for the length of every recording. The preview keeps its one `OpacityMask` and
its two cached shadows, and nothing repeats.

**Delete.** `selectionFillColor` and `onBorderColor` (read by nothing). The idle `snipProc`.
The three `bright*` colours (darkmode ternaries and a `Qt.lighter`), replaced by the M3
*fixed* roles, which are the same tones in both themes: `m3secondaryFixed` for the
selection, `m3secondaryFixedDim` for windows and `m3tertiaryFixedDim` for content. Dark mode
comes out identical for the targets. The scrim becomes `colScrim` instead of hex black. The
label chip becomes `colTooltip` / `colOnTooltip` instead of two hexes and an outline. Both
`Synchronizer`s, and the toolbar's unused `action` and `dismiss`. `CursorGuide.selectionMode`
is read by nothing. `setRegionToTargeted`, `dragDiffX` and `dragDiffY` are folded into the
press and release handlers.

**Also fixed on the way.** `contentRegionOpacity` was declared `bool`, so the config's 0.8
has been read as `true`, i.e. fully opaque. `dragging` was never cleared on release, which
went unnoticed only because every release closed the window. Now that an empty click keeps
it open, a stuck `dragging` would turn the next hover into a drag, and circle points would
carry over into the next stroke. Both reset on press and release.

**Out of scope.** `DashedBorder` itself: four other callers, and a rule-9 call for its own
row. The waffle family's `WScreenSnip`, which shares only `GlobalStates.regionSelectorOpen`.
The screen translator, which copies this toolbar's placement and its `Connections` hack and
should follow it in its own row. `ScreenshotAction`'s commands. Picking a different action
from inside the selector, instead of pressing another keybind while it is open (which
already works: `action` is a live binding). Flipping the cursor guide at the right and
bottom edges: its hint can run off-screen there for its two seconds.
