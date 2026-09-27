# waffle-looks — brief

**Purpose.** The central styling, theming, and UI primitive library for the Waffle panel family (Windows 11 Fluent style). Provides color palettes, typography scales, animation specifications, iconography resolvers, and reusable controls (buttons, menus, sliders, switches, toolbars, tabs, progress bars).

**Primary action.** Exporting consistent, type-safe, and high-performance design system primitives across all Waffle surfaces.

**Hierarchy.**
1. **Design System Engine**:
   - `Looks.qml`: Core design singleton defining dark/light color schemes, transparency compositing (`contentTransparency`, `backgroundTransparency`), corner radii, typography hierarchy, and motion curves.
   - `WIcons.qml`: Iconography resolver mapping network, battery, audio, bluetooth, and app states to Fluent vector glyphs.
2. **Structural Primitives & Layout**:
   - `WPane.qml`: Windows 11 acrylic container card with border and ambient shadow.
   - `WBarAttachedPanelContent.qml`: Panel container managing flyout reveal and exit animations anchored to taskbar edges.
   - `WStackView.qml`: Slide and fade view navigator for multi-page panels.
   - `WToolbar.qml`, `WToolbarTabBar.qml`: Horizontal action and tab navigation strips.
3. **Interactive Controls**:
   - Buttons: `WButton`, `WBorderedButton`, `WBorderlessButton`, `WChoiceButton`, `WTextButton`, `WPanelIconButton`, `CloseButton`, `AcrylicButton`.
   - Menus: `WMenu`, `WMenuItem`.
   - Inputs & Values: `WSlider`, `WSwitch`, `WProgressBar`, `WIndeterminateProgressBar`, `WTextField`, `WTextInput`.
   - Tooltips & Overlays: `WToolTip`, `WPopupToolTip`, `WToolTipContent`, `WAmbientShadow`, `WRectangularShadow`.

**Reference.** Windows 11 Fluent Design System specifications and token architecture adapted to Quickshell and ii-ren design standards (`.github/DESIGN.md`).

**What is wrong, measured.**
- **Fatal ReferenceError in Escape dismissal.** `WBarAttachedPanelContent.qml` called `content.close()` instead of `root.close()`. Hitting Escape inside any Waffle flyout threw an unhandled ReferenceError and failed to dismiss the panel.
- **Read-only property crash on user avatar.** `WUserAvatar.qml` had root `StyledImage` (`Image`). In QtQuick, `Image` defines `implicitWidth` and `implicitHeight` as read-only. When `WaffleLock.qml` assigned `implicitHeight: 144`, QML threw `Invalid property assignment: "implicitHeight" is a read-only property`, causing a fatal configuration load failure that crashed the shell on startup. Wrapped in `Item` with mutable `implicitWidth: 32` and `implicitHeight: 32`.
- **NaN dimension evaluation.** `VerticalPageIndicator.qml` referenced `upArea.containsPress` on a `MouseArea`. `containsPress` only exists on Qt Quick Controls `AbstractButton`, so on a `MouseArea` it evaluated to `undefined`, causing `implicitWidth: 12 - (2 * undefined)` to evaluate to `NaN`.
- **Input hijacking on TabBar.** `WToolbarTabBar.qml` placed a full-surface `MouseArea` at `z: 9999` with `acceptedButtons: Qt.LeftButton`, intercepting and consuming all left-clicks and preventing user interaction with TabButtons.
- **Fatal TypeError on empty menus.** `WMenu.qml` performed `[].reduce((a, b) => ...)` without an initial value on the menu item list, throwing `TypeError: Reduce of empty array with no initial value` when `count === 0`.
- **Content transparency wash-out.** `Looks.qml` did not gate `contentTransparency` or `panelLayerTransparency` on `Config.options.appearance.transparency.enable`. When transparency was disabled by the user, content fills were solved at 13% opacity instead of fully opaque.
- **Redundant GPU effect overhead.** `WIndeterminateProgressBar.qml` enabled an offscreen `layer.enabled` pass and `OpacityMask` solely to clip corners on an already-rounded capsule widget (`StyledIndeterminateProgressBar`).
- **Unbound QML component declarations.** 37 of the 48 QML files were missing `pragma ComponentBehavior: Bound`, leaving components vulnerable to loose scoping, property shadowing, and runtime lookup overhead.
- **Off-grid metrics and hardcoded literals.**
  - Menu padding `3` -> `4`.
  - Tooltip padding `3` -> `4`, visual margin `11` -> `12`.
  - Switch pressed indicator `17` -> `16`.
  - Choice button padding `11` -> `12`, indicator `3` -> `4`.
  - Close button `30x30` -> `32x32`.
  - Toolbar padding `9` -> `8`, height `50` -> `48`.
  - Durations hardcoded as numbers (`80`, `120`, `150`, `200`, `250`) rather than `Appearance.animation` tokens.
  - ScrollBar radius hardcoded as literal `9999`.

**Interaction.**
- Controls dynamically react across hover, active, pressed, and toggled states using Fluent color shifts and standard `Appearance.animation` tokens.
- Flyouts smoothly enter on `elementMoveFast` (decelerating) and leave on `elementMoveExit` (accelerating).
- Escape reliably triggers clean exit animations across attached flyouts.

**Edge states.**
- Empty menu (`count === 0`): Computes width safely with zero initial accumulator without throwing TypeErrors.
- Desktop without battery: `WIcons.qml` guards against `undefined` battery percentage, preventing `"battery-NaN"` icons.
- Power profile unavailable: `powerProfileIcon` falls back safely to `"flash-on"`.

**Cost.**
- Eliminates offscreen `layer.enabled` and `OpacityMask` passes in `WIndeterminateProgressBar`.
- Eliminates redundant event listener overhead in `WToolbarTabBar`.
- Enables static V4 property binding and compilation via `pragma ComponentBehavior: Bound` across all 48 files.

**Delete.**
- Redundant click-stealing `pressDetector` MouseArea in `WToolbarTabBar`.
- Offscreen `OpacityMask` and `layer.enabled` in `WIndeterminateProgressBar`.
- Invalid and broken `import QtQuick.Controls.FluentWinUI3` in `WTextField`.
- Circular import `import qs.modules.waffle.bar` in `CloseButton`.

**Out of scope.**
- Modifying non-Waffle shared widgets in `modules/common/widgets/`.
