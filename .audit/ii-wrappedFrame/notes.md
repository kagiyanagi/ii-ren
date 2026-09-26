# ii-wrappedFrame — notes

Audited and refactored `WrappedFrame.qml` under `modules/ii/wrappedFrame/`.

## Findings

1. **Broken Corner Symmetry (Regression from `82eca385e`):**
   In commit `82eca385e`, the condition formulas for the four corner loaders were mangled:
   - Corner 2 (TopLeft): `active: barBottom` (only active when horizontal bar was at bottom; failed when bar was vertical on right).
   - Corner 4 (BottomRight): `active: !barBottom` (only active when horizontal bar was at top; failed when bar was vertical on left).
   The active conditions have been replaced with four mutually exclusive bar position tokens:
   - `barAtTop = !barVertical && !barBottom`
   - `barAtBottom = !barVertical && barBottom`
   - `barAtLeft = barVertical && !barBottom`
   - `barAtRight = barVertical && barBottom`
   Corner fillets are active when not touching the bar edge:
   - TopLeft: `!(barAtTop || barAtLeft)`
   - TopRight: `!(barAtTop || barAtRight)`
   - BottomLeft: `!(barAtBottom || barAtLeft)`
   - BottomRight: `!(barAtBottom || barAtRight)`
   This guarantees that across all 4 bar positions (Top, Bottom, Left, Right), exactly 2 corner fillets and 3 edge frames are active.

2. **Unqualified Scope Accesses & Component Boundaries:**
   - In `ScreenCorner`, the component accessed `monitorScope.modelData` directly from inside the component template at the root level where `monitorScope` did not exist.
   - Five loader instantiations passed `showBackground: showBarBackground` instead of `monitorScope.showBarBackground`, triggering unqualified scope lookup warnings under `ComponentBehavior: Bound`.
   - All component properties and bindings have been fully qualified with `pragma ComponentBehavior: Bound`.

3. **Window Property Shadowing & Input Traps:**
   - Both `EdgeFrame` and `ScreenCorner` lacked `mask: Region {}`. While transparent, they could intercept mouse clicks intended for the desktop or wallpaper. Both now specify `mask: Region {}` to ensure click-through input transparency.
   - `ScreenCorner` lacked `exclusionMode: ExclusionMode.Ignore`, causing it to risk creating phantom exclusive zones in screen corners. It now explicitly sets `exclusionMode: ExclusionMode.Ignore`.
   - Both components set `WlrLayershell.namespace: "quickshell:wrappedFrame"`, aligning with Hyprland layer rules.
   - Removed redundant `property ShellScreen screen` declarations that shadowed `PanelWindow.screen`.

4. **Multi-Monitor Display Connector Matching:**
   - Previously `HyprlandData.monitors.find(m => m.id === monitorScope.index)` relied on `Quickshell.screens.indexOf(screen)`, which can drift from Hyprland monitor IDs when outputs are arranged or dynamically plugged.
   - Now matches by connector name: `HyprlandData.monitors.find(m => m.name === monitorScope.modelData.name)`.
   - Added initial state synchronization on load and on `barBackgroundStyle` change so adaptive mode doesn't wait for a later window event.

5. **Panel Loader Gating:**
   - Added `extraCondition: usingWrappedFrame` to `IllogicalImpulseFamily.qml` so `WrappedFrame` is not loaded into memory when `fakeScreenRounding !== 3`.
   - Inside `WrappedFrame.qml`, `Variants { model: wrappedFrame.active ? Quickshell.screens : [] }` also guarantees zero surfaces are spawned if loaded standalone.

## Verification

- **Automated Gate (`tools/check-wrapped-frame.py`):**
  Asserts all 4 bar orientations (Top, Bottom, Left, Right) activate exactly 3 edge frames and 2 corners, verifies namespace, click-through mask regions, corner exclusion mode, display connector matching, and IllogicalImpulseFamily gating.
- **Design Check (`tools/check-design.py --diff`):**
  0 findings, 0 errors.
- **Effect Budget (`tools/check-effect-budget.py`):**
  Passed cleanly.
- **Mask Regions (`tools/check-mask-regions.py`):**
  Passed cleanly.
