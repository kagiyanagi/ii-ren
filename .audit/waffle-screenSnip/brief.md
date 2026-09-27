# waffle-screenSnip — brief

**Purpose.** The screen capture and region snipping tool for the Waffle panel family (Windows 11 Fluent style). Provides desktop freeze capture, rectangular region selection, window selection, video recording, text recognition (OCR), QR scanning, visual search, and color picking.

**Primary action.** Freezing the display via `ScreencopyView`, dragging or selecting a region or window, and executing the configured snipping or recording action (`ScreenshotAction`).

**Hierarchy.**
1. **Host Scope (`WScreenSnip.qml`)**:
   - Manages IPC (`target: "region"`) and `GlobalShortcut` bindings (`regionScreenshot`, `regionSearch`, `regionOcr`, `regionQrScan`, `regionRecord`, `regionRecordWithSound`).
   - Dispatches mode properties (`mediaType`, `imageAction`, `videoAction`, `selectionMode`) declaratively.
   - Instantiates `Variants` across `Quickshell.screens` with monitor filtering (`Config.options.regionSelector.showOnlyOnFocusedMonitor`).
   - Latching loader: separates `wanted` from `rendered` to allow exit animations to complete before unmapping surfaces.
2. **Overlay Panel (`WRegionSelectionPanel.qml`)**:
   - Fullscreen `PanelWindow` on `WlrLayer.Overlay`.
   - `ScreencopyView` freezing the display state while active.
   - `DragManager` handling pointer drags, window hover hit-testing, and coordinate normalization.
   - `WRectangularSelection`: Darkening scrim overlay (`Appearance.colors.colScrim`) and accent border (`Looks.colors.accent`).
   - `RegionSelectionOptionsToolbar` (`WToolbar`):
     - Media type selector (`WToolbarTabBar` for Camera vs Video).
     - Snipping area selector (`WToolbarButton` with `WMenu` dropdown for Rectangle vs Window).
     - Quick markup toggle button (Ctrl+E).
     - Utilities: Image search (`search-visual`), Color picker (`eyedropper`), Text extractor (`scan-text`), Close button (`dismiss`).

**Reference.** Windows 11 Snipping Tool adapted to Quickshell layer shell and ii-ren Fluent design tokens (`.github/DESIGN.md`).

**What was wrong, measured.**
- **Null dereference crash on cold trigger.** `ocr()`, `qrScan()`, `record()`, `recordWithSound()`, and `search()` set `GlobalStates.regionSelectorOpen = true` and immediately attempted to assign properties on `regionSelectorLoader.item`. When the loader was previously inactive, `regionSelectorLoader.item` was `null`, throwing `TypeError: Cannot set property 'mediaType' of null`.
- **Undeclared `videoAction` property.** `WScreenSnip.qml` assigned `videoAction` on the loader item, but `WRegionSelectionPanel.qml` never declared `property var videoAction`. `getScreenshotAction()` read `undefined`, breaking video recording snips.
- **Premature unmapped window on exit.** `regionSelectorLoader.active` was tied directly to `GlobalStates.regionSelectorOpen`. Dismissing the selector unmapped the window immediately, skipping exit fade transitions.
- **Single-monitor limitation.** Only instantiated a single unassigned `Loader`, failing on multi-monitor setups and ignoring `Config.options.regionSelector.showOnlyOnFocusedMonitor`.
- **`DashedBorder` Canvas texture churn (FINDINGS.md:167).** `WRectangularSelection.qml` used `DashedBorder`, a `Canvas` item that cleared, stroked, and re-uploaded textures on every pointer move during live drag.
- **Raw hex literals and literal durations.** `WRectangularSelection.qml` used `#ffffff` and `#000000` literals, plus literal `duration: 150; easing.type: Easing.InOutQuad`.
- **Window selection multi-monitor coordinate mismatch.** Window hit testing and coordinates compared global Hyprland coordinates `w.at` against screen-local pointer coordinates without subtracting `root.monitorOffsetX` / `root.monitorOffsetY`.
- **Unclamped selection bounds.** Selection bounds were not clamped against screen dimensions, allowing negative or out-of-bounds crops.
- **Active recording not stoppable.** Triggering record actions while `Persistent.states.screenRecord.active` was true did not stop `wf-recorder`.
- **Off-grid metrics.** `selectionTypeBtn` used off-grid padding (11dp). `WMenu` did not set `downDirection: true` under the top toolbar. Window icon was `"calendar-add"`.
- **Idle `Process snipProc`.** Retained an idle `Process` component solely for `startDetached()`.
- **Missing pragma declaration.** `WRectangularSelection.qml` omitted `pragma ComponentBehavior: Bound`. Unused imports in `WScreenSnip.qml` and `WRegionSelectionPanel.qml`.

**Interaction.**
- Opens with a smooth fade (`Appearance.animation.elementMoveFast`) and slides the options toolbar down from the top.
- Left-drag selects a rectangular region; releasing executes the configured snip action and dismisses the selector.
- In Window mode, hovering highlights individual application windows on the active workspace; clicking executes the snip for that window.
- Right-clicking or pressing Escape dismisses the selector.
- Pressing Ctrl+E toggles Quick markup mode.
- Dismissing triggers `open = false`, shifts into passive mode (`mask: passthroughRegion`, `keyboardFocus: None`), and fades out via `Appearance.animation.elementMoveExit`. When opacity reaches 0, `fadedOut()` is emitted and the loader unmaps the window.

**Edge states.**
- Canceled during screen capture: Dismisses cleanly once capture completes without lingering.
- Zero-sized / accidental click: Guards against 0x0 crops on drag release without executing commands.
- Active recording: Calling record stops the recording via `record.sh --stop` instead of opening a conflicting selector.
- Multi-monitor: Respects `showOnlyOnFocusedMonitor` or spans across available screens.

**Cost.**
- Eliminates per-pointer-move `Canvas` redraws and texture re-uploads, replacing them with a zero-allocation `Rectangle` border.
- Replaces idle `Process` component with `Quickshell.execDetached()`.
