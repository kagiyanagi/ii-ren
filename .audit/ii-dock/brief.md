# ii-dock — brief

**Purpose.** Launch and switch between apps without leaving the pointer, and
keep the few things you always want one click away — pinned apps, folders,
pinned files, what is playing.

**Primary action.** Click an icon to raise or launch that app. Everything else
on the strip — the pin toggle, the folders, the files, the media card, the apps
button — is secondary and must look it. The icons are the only things in the
dock at full weight.

**Hierarchy.** The icon row leads and owns the middle. The running-window dots
sit under it, quiet until one is focused. The two action buttons cap the ends
and are the only filled shapes. The media card is a single tinted tile at the
tail — it reads as one object, not as a row of controls.

**Reference.** Launcher3's `Taskbar`: a solid pill of `colLayer0`, icons at
`dockButtonSize` with `FastBitmapDrawable`'s `HOVERED_SCALE` 1.1 over
`HOVER_FEEDBACK_DURATION` 300ms on `PathInterpolator(0.05, 0.7, 0.1, 1.0)` —
`emphasizedDecel` — and a press squish multiplied in on top so both read on a
pointer. Taskbar icons carry **no** elevation of their own: they sit on the
taskbar's surface, and the scale is the whole feedback. Folder card and context
menus are `ArrowPopup`, growing out of the icon that opened them.

**Interaction.**
- Icon hover/press: `Appearance.animation.iconHover` and `iconPressSquish`,
  composed as `scale: hoverScale * pressScale` (2.9 — a `Behavior on scale`
  would kill the binding). Ripple off (3.2).
- Dock reveal/hide: the anchor margin on `elementMoveFast`, never `x`/`y`.
- Folder card and both context menus: the `ArrowPopup` composite —
  `arrowPopupScale` → `arrowPopupOvershoot` over `arrowPopupScaleDuration` on
  `emphasizedDecel`, settling on `arrowPopupSettle`, with alpha riding
  underneath over `arrowPopupFadeDuration`; out on `emphasizedAccel` over
  `arrowPopupCloseDuration` with the fade held back `arrowPopupFadeHold`.
  Enter and exit are different specs, which today's context menu does not have
  at all. **Assembled once, in one shared widget** — decision 14 — not
  transcribed per file.
- Transform origin is the dock edge: a bottom dock's popups grow out of
  `Item.Bottom`, a left dock's out of `Item.Left`. `DockTooltip` and
  `DockFolderPopup` already do this; the context menus do not.
- Dots, colour and opacity: effects specs only, never `elementResize`.

**Edge states.**
- *Empty* — nothing pinned, nothing running: the two action buttons and the gap
  between them. The section spacers collapse to nothing, which they already do.
- *One item* — a single icon between the two buttons; the dock shrinks to it.
- *Loading* — icons resolve from the theme asynchronously; the slot is held at
  `buttonSlotSize` from the first frame so the strip does not jump.
- *No media* — the card collapses its width to 0 over `elementMoveFast` and the
  spacer either side goes with it.
- *Dragging* — the dragged icon goes to `opacity: 0` and the ghost carries it;
  neighbours translate by one slot; the two end buttons morph to the drop shape.

**Cost.** This is where the surface actually fails. Every app icon is a
delegate, and today each one pays **three** offscreen passes: `Desaturate` +
`ColorOverlay` in `DockIcon` (monochrome is on by default) and a
`StyledDropShadow` in `DockAppButton`. Thirteen pinned apps plus running ones is
forty-odd framebuffers for a strip of 39px icons, on integrated graphics.
`check-effect-budget.py` cannot see any of it, because its delegates are
*files* and the gate only reads a `Repeater`/`delegate:` block in one file.

- **Keeps:** one `MultiEffect` per icon, as `layer.effect` on the `IconImage`
  and only while monochrome or dim-inactive is on — the same collapse
  `Workspaces` made under decision 26. The card shadow on the dock, the folder
  card, the tooltip, the context menu and the preview popup: one each, analytic,
  not in a delegate.
- **Drops:** the per-icon `StyledDropShadow`. The reference has no icon
  elevation, the icons sit on a solid surface, and the hover scale — measured
  live, it works — is the feedback DESIGN.md 3.3 asks for.
- **Left, with the argument in `notes.md`:** `DockMediaWidget`'s four-effect
  stack and `DockPreviewPopup`'s per-delegate `OpacityMask` (already `KNOWN`).

**Delete.**
- The four divider `Rectangle`s at `colLayer0Border` in `DockContextMenuBase`,
  `DockContextMenu` (×2) and `DockFileContextMenu`. Law 11 forbids them
  outright; whitespace on the 4dp grid separates the groups instead.
- The per-icon drop shadow (above).
- `DockMediaButton.qml` — reached by nothing at all.
- The hand-typed `ArrowPopup` numbers in `DockFolderPopup`, replaced by the
  shared widget.

**Fix.**
- The media card leads with the **artist** and dims the **title** to
  `opacity: 0.7`. That is upside down: the track title is what the card is for.
  Title first at full strength, artist under it in `colSubtext`.
- `DockFileButton`'s `Connections` on a `Loader`-owned target with no `?? null`
  — anti-pattern 5, a segfault, not a warning.
- Escape does not close a dock context menu. The focus grab handles an outside
  click and nothing handles the keyboard.
- `DockButton`'s two literal durations, the inline bezier and the six literal
  durations in `DockFolderPopup`, the two hex literals in `DockPreviewPopup`,
  the two off-grid margins.

**Out of scope.**
- `DockSeparator`'s `Line`/`Dot` styles. Decision 10 already ruled: the default
  is `Empty`, and the styles stay for a config that explicitly chose one. This
  machine's config did.
- The media card's effect stack and the `ClippingWrapperRectangle` rewrite it
  needs — its own row.
- The unqualified `root` that `DockListView`, `SectionSeparator` and
  `DockAppIcon` read out of the caller's scope. It works, it is fragile, and
  unpicking it touches every delegate — recorded, not done here.
- Teaching `check-effect-budget.py` about delegates that live in their own file.
  `tools/check-dock.py` covers this surface's instance of it.
