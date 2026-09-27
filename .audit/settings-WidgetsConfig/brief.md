# settings-WidgetsConfig — brief

**Purpose.** Place desktop widgets: global placement options, the categorised catalog
with live previews, and widget extensions.

**Primary action.** Add a widget to the desktop from the catalog.

**Hierarchy.** Unchanged: Desktop Widgets (grid, snap, scale, lock, one-monitor, colour
scheme), then Widget Catalog (nine category cards), then Widget Extensions.

**Reference.** Android 16 launcher → Widgets picker: grouped by app, expand to see
previews, one action per preview.

**Interaction.**
- A category opens through `Revealer`: grown on the spatial spec, collapsed on the exit
  spec. Its `Loader` stays up until the collapse finishes. It used to snap between 0 and
  full height. The chevron turns on `elementMove`; it was on the fast effects spec.
- The extension-settings overlay is a second copy of `ConfigSubPageHost`, and it left
  on its enter curve. It picks `elementMoveExit` for the exit now, the way the host does.
  It also takes the pointer: an opaque `Rectangle` let hover and clicks through to the
  gallery under it.

**Edge states.** A category with active widgets shows its count badge (unchanged). An
unloaded preview shows the widget's icon watermark (unchanged).

**Cost.** Previews load staggered, near the viewport, and unload far from it (unchanged).
The colour-scheme swatches are one `Canvas` each, painted once. They now repaint when
the rounding style changes, where before they kept the old shape.

**Delete.** Eighteen "backward compatibility" properties nothing read.

**Out of scope.** The widget previews themselves (vendored, `modules/ii/background/widgets/`).
