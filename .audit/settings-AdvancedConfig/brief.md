# settings-AdvancedConfig — brief

**Purpose.** Decide what wallpaper colours reach, pick icon and cursor themes, and set
custom font families.

**Primary action.** Shell & utilities, since `switchwall.sh` returns before generating
anything when it is off.

**Hierarchy.**
1. **Color generation** — Shell & utilities, then Qt apps and Terminal, both disabled while
   the first is off. Under them, a **Terminal colours** subsection (Force dark mode,
   Harmony, Harmonize threshold, Foreground boost), disabled unless both are on. The labels
   drop the repeated "Terminal:" prefix now that the subsection title says it.
2. **Icons & cursor** — two `ConfigNavRow`s. They used to sit in the middle of the colour
   switches.
3. **Fonts** — Use custom fonts, then the seven families as one carded run of
   `ConfigTextField` rows (icon, role, family), placeholders showing the shipped default.

**Reference.** Android 16 Settings → Display → Colours and Wallpaper & style: master switch
first, dependants greyed out under it.

**Interaction.** Font fields commit on `editingFinished`. They used to write
`Config.options.appearance.fonts.*` on every keystroke, and each write re-laid out every
text item in the shell on a half-typed name. They also wrote once when the page loaded.
The custom-fonts switch returns early when the stored value already matches, so opening
the page does not rewrite seven font names.

**Edge states.** An empty field is not committed, so a cleared field keeps the last family.
With custom fonts off, the fields are disabled at 0.4 and show the stored custom names.

**Cost.** None.

**Delete.** The "Toggle Hyprland window rounding" switch: nothing reads
`appearance.toggleWindowRounding` (anti-pattern 16). Seven one-row subsections of
`MaterialTextArea` go too, and so does a `ConfigRow` holding a single switch. The file's
second half sat one indent level outside the page it belonged to. It still parsed, but it
read as if the sections were outside `ContentPage`.

**Out of scope.** `ThemedIconsConfig`, `CustomCursorConfig` (`sw-advanced-pages`).
