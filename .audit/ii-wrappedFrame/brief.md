# ii-wrappedFrame — brief

**Purpose.** When `Config.options.appearance.fakeScreenRounding === 3` ("Wrapped"), render a frame
of `Appearance.colors.colLayer0` with thickness `Config.options.appearance.wrappedFrameThickness`
(5–25px) around the display edges, paired with concave corner fillets (`Appearance.rounding.screenRounding`)
to give tiled application windows the appearance of resting inside a unified shell frame.

**Primary action.** None. This is desktop framing / visual chrome, not interactive UI. It must never
block pointer interaction or intercept mouse clicks.

**Hierarchy.** Background framing layer (`colLayer0`, matching the Bar and Dock background). Corner
fillets match `rounding.screenRounding`. Everything is click-through.

**Reference.** Material 3 Expressive and Android 16 window container framing. Chrome wraps around
application windows while letting input pass through unimpeded.

**Interaction.**
- Entirely click-through: `mask: Region {}` on both `EdgeFrame` and `ScreenCorner` ensures pointer clicks
  fall through to wallpaper, desktop icons, or underlying windows.
- Layer & Exclusion: `EdgeFrame` reserves exclusive zones along the 3 edges not occupied by the Bar so
  Hyprland tiles windows cleanly inside the frame. `ScreenCorner` sets `exclusionMode: ExclusionMode.Ignore`
  so the corner fillets do not reserve desktop space or distort tiling bounds.
- Bar coordination: The Bar occupies one edge (Top, Bottom, Left, or Right). The edge containing the bar
  and its two touching corners are inactive in `WrappedFrame` (the Bar handles its own background and
  corner decorators). `WrappedFrame` renders the 3 remaining edges and 2 opposite corners.
- Adaptive styling: When `Config.options.bar.barBackgroundStyle === 2` ("Adaptive"), the frame fades
  between `colLayer0` and `"transparent"` based on whether non-floating windows exist on the monitor's
  active workspace, perfectly synchronized with the Bar background.
- Motion: Color transitions use `Appearance.animation.elementMoveFast.colorAnimation` (expressive effects token).
- Namespaces: `WlrLayershell.namespace: "quickshell:wrappedFrame"` applies Hyprland compositor layer rules.

**Edge states.**
- *Mode off (0, 1, 2)*: Gated in `IllogicalImpulseFamily.qml` via `extraCondition: usingWrappedFrame` and
  in `WrappedFrame.qml` via `model: wrappedFrame.active ? Quickshell.screens : []`. Zero surfaces created.
- *Bar position changes*: The four orientations (Top, Bottom, Left, Right) activate exactly the 3 opposite
  edges and 2 non-touching corners.
- *Multi-monitor*: Hyprland monitors are resolved by display output connector name (`m.name === monitorScope.modelData.name`)
  rather than screen array index.
- *Adaptive mode switching*: Initial state immediately reflects active workspace windows upon load without
  requiring an external window event.
- *Dead pixel workaround*: Preserves -1 margin shift on right and bottom edges if enabled in interactions config.

**Cost.** Exactly 3 edge frames and 2 corner fillets per monitor when `fakeScreenRounding === 3`. Zero
surfaces when inactive.

**Delete.**
- Unused imports (`QtQuick.Controls`, `QtQuick.Layouts`, etc.).
- Out-of-scope `monitorScope.modelData` access inside component definitions.
- Redundant `property ShellScreen screen` declarations shadowing `PanelWindow.screen`.
- Broken asymmetric corner condition formulas from commit `82eca385e`.
- Unqualified `showBarBackground` references across Loader instances.
