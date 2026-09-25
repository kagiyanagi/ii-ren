# ii-settings — brief

The six files under `modules/ii/settings/` are not a surface of their own: they are the
two lists on Settings → Extensions — the installed extensions, and the ones found on
GitHub. The page around them (`ExtensionsConfig.qml`: toolbar, URL field, beta notice) is
the `settings-ExtensionsConfig` row and is out of scope here.

**Purpose.** Turn installed extensions on and off, set their options, and install new ones.

**Primary action.** The installed row's switch. In the browse list, *Install*. Everything
else on a row is secondary and looks it.

**Hierarchy.** Each list is one grouped run, in `ContentGroup`'s shape (DESIGN.md 5.6):
`colSurfaceContainerHigh` cards 4 apart, `rounding.large` at the ends of the run and
`rounding.verysmall` on the seams, so the cards read as the same material as every other
settings row. They used to be `colLayer1` cards 5–6 apart, a different colour from their
neighbours.

A row is an M3 two-line list item. The eye lands on the extension's `MaterialShape`
first (48, `colPrimaryContainer` when it is on and `colSurfaceContainerHighest` when off),
then the name with its badges, then one supporting line, then the switch at the far right.
- **Installed:** the supporting line reads `1.2.0 · author`, with `· Update available`
  in `colPrimary` when there is one. That status is the only one that asks for action, so
  "Up to date" and "Checking update…" go. The whole row is one `RippleButton` that
  expands the options, with a chevron that turns 180°. The expanded panel shows the
  description (wrapped, not elided to one line), then the option rows, then one row of
  actions: *Update* (primary tonal) or *Check for updates*, *Reload* (local only),
  *Reset to defaults* (only with a schema), *Repository* (only with a URL), and *Remove* in error
  tonal on the right, which asks twice.
- **Browse:** the supporting text is the description over two lines, then
  `★ stars · version`, or "No extension.json" in `colError`. A trailing *Install*, which
  is disabled for a repo without an `extension.json` because installing one only leaves a
  clone behind. The row itself opens the repo page, as a store list item opens its
  details, so the stacked *Info* button goes.

The option rows are the settings app's own: `ConfigSwitch`, `ConfigSpinBox`,
`ConfigSlider`, `ConfigTextField`, and a `ContentSubsection` around a
`ConfigSelectionArray`. They are chosen with a `DelegateChooser` rather than with a
`Loader` that has its bindings wired in `onLoaded`. They share one inset, so their icons
line up in a column.

**Reference.** Android 16 Settings → Apps: a grouped list of app rows with a trailing
switch. The browse rows follow Play's list item: tap the row for details, the trailing
button installs.

**Interaction.**
- Row: `RippleButton` states (hover 0.08, focus 0.10, pressed 0.10). It takes the card's
  radii so the film fills the card. Enter and Space expand it. The switch and the action
  buttons keep their own input on top.
- Expand: height on `elementMove`, collapse on `elementMoveExit`, in `NotificationGroup`'s
  shape. The chevron turns on `elementMoveSmall`, which reverses mid-flight. The panel
  clips and grows downward from the header, the thing that opened it.
- Disabled (extensions off): the switch, *Install* and the actions are at 0.4 through
  their own `enabled`. The row itself stays live, because reading an extension's options
  and opening its repo do not need the system running.

**Edge states.**
- *Empty, extensions off:* the browse list says nothing. The notice above already holds the
  switch, and "Click refresh" pointed at a button that was disabled.
- *Empty, on:* "No extensions match your search" or "No extensions found", as now.
- *Loading:* "Searching GitHub…" in `colSubtext`, where there used to be nothing.
- *One item:* both ends of the card are `rounding.large`.
- *No author:* the ` · author` part is left out (it rendered `v0.0.1 by `).
- *No schema:* the panel shows the description and the actions only.

**Cost.** The pack reports no effects and no fast timers, and nothing is added. The
`MaterialShape` is a vector shape, not an offscreen pass.

**Delete.** The icon's hover-to-"info" swap and its raw `MouseArea`, the browse card's
*Info* button, the "Up to date" and "Checking update…" labels, the `-8` anchor hack on
the config switch, the `onLoaded` binding plumbing, and the hand-built string row
(`MaterialTextField` at a literal 200 wide).

**Bugs this fixes on the way.** The slider option wrote `plugins.json` on every frame of
its settle animation (`onValueChanged`; `ConfigSlider` documents `moved` for this). Every
option wrote its value back on load, because the bindings were wired after creation.
`ExtensionBadge` had a binding loop on `implicitWidth` through `childrenRect`.

**Out of scope.** `ExtensionsConfig.qml` and the services. The duplicate-signal warning
in `GroupButtonWithTextField` is a common widget, and goes in `FINDINGS.md`.
