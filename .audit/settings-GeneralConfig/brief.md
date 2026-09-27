# settings-GeneralConfig — brief

**Purpose.** System-wide behaviour that does not belong to one surface: audio limits,
battery warnings, language, feature policies, sounds, clock formats, work safety,
autostart.

**Primary action.** None dominant; a list of independent settings.

**Hierarchy.** Audio, Battery, **Language** (interface language, then the screen
translator engine), **Policies** (two rows: Weeb + Translator, Continuity + Hermes), Sounds,
**Time & date** (second precision, time format, date format), Work safety, Autostart.

It used to have ten sections. Language and Screen Translator were one combo each, and
Time and Date were one "Format" subsection each. Policies used three rows for four
choices.

**Reference.** Android 16 Settings → System: grouped, short sections.

**Interaction.** Widget defaults. Autostart's Add app and Run now are
`RippleButtonWithIcon`s now, Add on `colSecondaryContainer` since it is the section's
action. They were fill-less `RippleButton`s that read as labels.

**Edge states.** No autostart entries: only the switch and Add app, with Run now disabled
(unchanged). A custom format shows a live preview (unchanged).

**Cost.** None.

**Delete.** Two sections, one Policies row, the untranslated translator-engine tooltip
(it is `Translation.tr` now), and trailing whitespace on nearly every line.

**Out of scope.** The hyprlock `sed` on a time-format change. It still runs, and it still
decides 12h by `includes("a")`.
