# ii-topLayer — brief

Delete and relocation row, no independent surface to design.

**Purpose.** Clean up abandoned prototype scaffolding from the pre-AOSP volume dialog rebuild.

**What it was.** `modules/ii/topLayer` was introduced in commit `08eae40d3` during early experimentation with an alternative drop-style on-screen display (`OsdDrop.qml`, an island/drop overlay anchoring to the bar). The commit duplicated 10 files under `modules/ii/topLayer/` and again under `modules/ii/topLayer/osd/` (20 files, 1,859 lines total).

**Live vs dead analysis.**
- `IllogicalImpulseFamily.qml` and `shell.qml` do not load `topLayer` anywhere.
- 19 of the 20 files (`OsdDrop.qml`, `OsdDropPositioner.qml`, `OsdDropState.qml`, `OsdConnectValueIndicator.qml`, and the 5 indicators in both directories) have zero callers anywhere in the shell.
- Only 1 file — `OsdProgramSlider.qml` — was live, imported solely by `modules/ii/onScreenDisplay/components/OsdSlidersRow.qml` for per-application Pipewire audio stream volume sliders.

**Resolution.**
- Relocate `OsdProgramSlider.qml` to `modules/ii/onScreenDisplay/components/OsdProgramSlider.qml`, where its only caller (`OsdSlidersRow.qml`) lives.
- In `OsdSlidersRow.qml`, drop the orphan `import qs.modules.ii.topLayer.osd`.
- In `OsdProgramSlider.qml`, clean up mechanical design debt: replace hex literal `#80000000` with `Appearance.colors.colScrim`, literal radius `4` with `Appearance.rounding.small`, literal color `white` with `Appearance.colors.colOnError`, and drop unused `import QtQuick.Layouts`.
- Delete the entire `modules/ii/topLayer/` directory (20 files, 1,859 lines gone).
