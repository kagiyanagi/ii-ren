# settings-InterfaceConfig — brief

**Purpose.** Options for every shell surface that is not the bar or the desktop: cheat
sheet, Alt+Tab, dock, clipboard, notifications, the overlay widgets, the fullscreen
player, region selector, sidebars, OSD, language switcher, overview, wallpaper selector.

**Primary action.** None dominant; one section per surface.

**Hierarchy.** Unchanged section order. Notification history is the shared
`ConfigNavRow` now, carded with the rows around it. It used to be a hand-copied row that
sat bare.

**Reference.** Android 16 Settings → System → Gestures / Display: one heading per surface.

**Interaction.** The notification monitor name, the crosshair code, the floating-image
source and the uptime icon commit on `editingFinished` rather than on every keystroke.
The overview order selectors lose a hand-set `leftMargin: 50`, and the row's own spacing
separates them.

**Edge states.** Unchanged.

**Cost.** None.

**Delete.** The copied history row. `OsdPositionPicker` read
`Appearance.font.variableAxes.titleRounded`, which does not exist, and logged
"Unable to assign [undefined] to QVariantMap" twice on every visit to this page. It reads
`variableAxes.title` now, and `check-appearance-refs.py` checks that level.

**Out of scope.** The five "Overlay: …" sections stay separate. Merging them into one
section would nest their own subsections.
