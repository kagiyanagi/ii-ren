# ii-topLayer — notes

Delete and relocation row. Ran 2026-09-26.

## Findings & Inventory

`modules/ii/topLayer` was committed in `08eae40d3 feat(osd): rebuild the volume OSD to the AOSP volume dialog` as prototype scaffolding. The commit accidentally created two duplicate trees:
1. `modules/ii/topLayer/` (10 files, 930 lines)
2. `modules/ii/topLayer/osd/` (10 files, 929 lines)

Eight of the ten files were bit-for-bit identical between the root and `osd/` subdirectories.

Across both directories:
- `OsdDrop.qml` (333 lines × 2): dead prototype drop overlay; not loaded in `IllogicalImpulseFamily.qml` or anywhere else.
- `OsdConnectValueIndicator.qml` (278 lines × 2): dead indicator base.
- `OsdDropPositioner.qml` (53 lines × 2): dead positioner used only by `OsdDrop.qml`.
- `OsdDropState.qml` (24 lines × 2): dead state tracker used only by `OsdDrop.qml`.
- `indicators/` (5 files × 2): `BrightnessIndicator`, `GammaIndicator`, `KeyboardBrightnessIndicator`, `PlayerVolumeIndicator`, `VolumeIndicator` (125 lines total × 2). All dead; the active indicators are in `modules/ii/onScreenDisplay/indicators/`.
- `OsdProgramSlider.qml` (116 lines): the single live component across all 20 files, imported only by `modules/ii/onScreenDisplay/components/OsdSlidersRow.qml:3`.

## Actions Taken

1. Moved `OsdProgramSlider.qml` into `modules/ii/onScreenDisplay/components/OsdProgramSlider.qml` alongside `OsdSlidersRow.qml`.
2. Cleaned design tokens in `OsdProgramSlider.qml`:
   - `#80000000` → `Appearance.colors.colScrim`
   - `radius: 4` → `Appearance.rounding.small`
   - `color: "white"` → `Appearance.colors.colOnError`
   - Dropped unused `import QtQuick.Layouts`.
3. Removed `import qs.modules.ii.topLayer.osd` from `OsdSlidersRow.qml` (directory siblings resolve automatically).
4. Deleted `modules/ii/topLayer/` (all 20 files, 1,859 lines).

## Gates

- `python3 tools/check-design.py --diff`: ok (0 findings, 0 errors).
- `python3 tools/check-osd.py`: ok (OSD card fits, button group reads both positions, minimalist pill leaves).
- `python3 tools/check-effect-budget.py`: ok (no new effects in delegates).
- `python3 tools/check-m3-tokens.py`: ok (springs, state layers, opacities valid).
- `qmllint` (/usr/lib/qt6/bin/qmllint against shadow tree): ok, unused-imports cleared on OsdProgramSlider and OsdSlidersRow.
- `python3 tools/audit/reachable.py modules/ii/onScreenDisplay`: 0 dead files.
