# waffle-screenSnip — notes

**Opening it.**
- Active under `Config.options.panelFamily: "waffle"`.
- Triggered via IPC: `quickshell ipc call region screenshot` (or `ocr`, `qrScan`, `record`, `recordWithSound`, `search`).
- Triggered via GlobalShortcuts: `regionScreenshot`, `regionSearch`, `regionOcr`, `regionQrScan`, `regionRecord`, `regionRecordWithSound`.

**Measured and fixed.**
- **Null-dereference fix & declarative state:** Declared `mediaType`, `imageAction`, `videoAction`, and `selectionMode` directly on the root `WScreenSnip.qml` Scope. Root functions mutate these properties before opening `GlobalStates.regionSelectorOpen = true`, eliminating crashes when invoking actions on a cold loader.
- **Multi-monitor support & exit latching:** Converted `WScreenSnip.qml` to use `Variants` across `Quickshell.screens` with `Hyprland.monitorFor` and `Config.options.regionSelector.showOnlyOnFocusedMonitor` filtering. Separated `wanted` from `rendered` so the `PanelWindow` stays mapped while the exit fade transition runs, clearing `rendered` only after `onFadedOut`.
- **Active recording stop toggle:** Added checks on `Persistent.states.screenRecord.active` in `record()` and `recordWithSound()`. If a recording is currently running, invoking record immediately executes `${Directories.recordScriptPath} --stop` and exits.
- **Declared `videoAction` & handler:** Declared missing `property var videoAction: WRegionSelectionPanel.VideoAction.Record` in `WRegionSelectionPanel.qml` and completed `getScreenshotAction()` switch cases for `Record` and `RecordWithSound`.
- **Smooth entrance/exit transitions & passive mode:** Added `open`, `signal fadedOut()`, and `signal dismiss()` to `WRegionSelectionPanel.qml`. Root content fades in via `Appearance.animation.elementMoveFast` and fades out via `Appearance.animation.elementMoveExit`. During exit fade, `passive: true` routes clicks to the desktop via `passthroughRegion` mask and clears keyboard focus. The options toolbar slides into place from the top.
- **Window hit-testing & screen bounding:** Adjusted Hyprland window coordinates by `- root.monitorOffsetX` and `- root.monitorOffsetY` for multi-monitor accuracy, filtering by `activeWorkspaceId`. Clamped selection rectangles to `[0, 0, root.screen.width, root.screen.height]` and added early return on zero/negative sized selections.
- **Elimination of Canvas `DashedBorder`:** Replaced `DashedBorder` with a hardware-accelerated `Rectangle` border, eliminating GPU texture allocations and clearing/stroking on every pointer move during drag (resolving FINDINGS.md:167).
- **Design tokens & 4dp grid alignment:**
  - Replaced `#ffffff` and `#000000` with `Looks.colors.accent` and `Appearance.colors.colScrim`.
  - Replaced `duration: 150` with tokenized animation specs.
  - Aligned toolbar button paddings to 12dp (was 11dp).
  - Configured `downDirection: true` on `selectionTypeMenu`.
  - Updated window selection icon to `"desktop"`.
- **Process cleanup & imports:** Removed idle `Process snipProc` in favor of `Quickshell.execDetached()`. Cleaned unused imports (`Qt5Compat.GraphicalEffects`, `QtQuick.Layouts`, `Qt.labs.synchronizer`, etc.) and ensured `pragma ComponentBehavior: Bound` across all files.

**Automated verification.**
- Created `tools/check-waffle-screenSnip.py` testing pragmas, null safety, multi-monitor variants, exit latching, recording stop toggle, videoAction declaration, passive masking, coordinate normalization, DashedBorder elimination, and 4dp grid alignment.
- Ran `python3 tools/check-waffle-screenSnip.py` (passes 10/10 check groups).
- Ran `python3 tools/check-design.py --diff` (0 findings, 0 errors).
