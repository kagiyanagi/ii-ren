# ii-settings — notes

Ran lane 1, not 2. These six files are the two lists on Settings → Extensions. The page
around them is `settings-ExtensionsConfig`. Most of the row was write paths into
`plugins.json`, and a screenshot shows none of them.

## The old panel wrote to the real `plugins.json` from one render

The before-shot probe (old code, no clicks) left `extensionConfigs.vynx-visualizer.gain:
57.300000000000004` in `~/.config/illogical-impulse/extensions/plugins.json`. That is an
extension that is not installed, and a value from mid-way through the slider's settle
animation. The file was restored by hand to its original bytes (29,649) and the block to
`{}`. **Any probe that loads the Extensions page writes to whatever `XDG_CONFIG_HOME`
points at.** Point it at a sandbox.

## How to reach the surface

- Extensions are **off** on this machine and nothing is installed, so the live page shows
  only the notice. Nothing here was screenshotted from the real app.
- The shots come from a throwaway `qs -p` probe in the shell dir. It loads
  `modules/settings/ExtensionsConfig.qml`, then assigns mock entries to
  `ExtensionManager.installedExtensions` and to the page's `filteredExtensions`. The probe root
  must `import qs.modules.ii.settings` itself. Without that, the page's own import fails
  with "module is not installed", because quickshell only registers directories it reaches
  from the root. The real app does not hit this: checked with `II_SETTINGS_PAGE=extensions`.
- `II_SETTINGS_PAGE=<id> qs -p settings.qml` opens the real app on a page.
- The **behavioural** test ran with `XDG_CONFIG_HOME` and `XDG_STATE_HOME` pointed at a
  sandbox holding a copied `config.json` with `extensions.enable: true` and a `plugins.json`
  seeded with one local extension. Seed the file. Do not assign in memory, because the
  `FileView` load races the assignment and wins. The run measured:
  - no row writes on load or on expand (the seeded values came back byte for byte);
  - the switch writes on click;
  - the slider does not write on a `value` change, only on `moved`;
  - the spinbox shows a stored 150 under a `to` whose default is 99, and writes the user's change;
  - text writes on `editingFinished` and not per keystroke;
  - the enum writes on select;
  - a reset resyncs all four row kinds to the defaults;
  - the first Remove click only arms, and the second removes.
  `tools/check-extension-options.py` pins the structure behind each of these. Mutation-tested
  six ways, and it caught all six.

## Decided while building

- **The options got their own `ContentGroup` run** (`colSurfaceContainerHighest`,
  `rounding.normal` outer). The first build put them bare on the extension card, and
  `ConfigTextField` then read as static text. It has no outline, and in the settings app
  its card is the only thing that makes it look like a field. A `ContentSubsection` around
  the enum chips would open a second group and card them in the wrong tone, so the enum row
  is a carded `ColumnLayout` with the label above, as `ConfigSlider` has it.
- **Name rows keep their text at natural width, followed by a filling spacer.** Text with
  `fillWidth` plus `maximumWidth: implicitWidth` beside a filling spacer elided "my-local"
  with half the row free. With no spacer at all, the row's maximum is its content (Qt
  propagates max size up), so the column beside the shape could not take the free width.
- **Remove asks twice** (arms for 4s) and sits alone at the far right. It deletes the clone
  and the extension's settings. For a local extension it only unregisters (checked in
  `ExtensionManager.uninstallExtension`).
- agy's vision pass (`gemini-3.1-pro-high`, `--mode plan`; put `-p` *after* `--model` or
  it eats the flag) found the Remove placement, which is right and was fixed. Rejected after
  checking against the pixels: "cards not a grouped run" (the gap measures 4px and the seams
  are 8px corners), "Update available is grey" (it samples as saturated blue), "rows without
  icons don't align" (they align on the icon column, which is empty), and "the text field
  is plain text". That last one is `ConfigTextField`'s look, and the option card is the fix
  for it.

## For the cohesion pass

- The options panel expands on `elementMove` and collapses on `elementMoveExit`, as
  `NotificationGroup` does. The chevron turns on `elementMoveSmall`. Not measured at 60fps.
