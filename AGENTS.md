# AGENTS.md - ii-ren

Fork of [ii-vynx](https://github.com/vaguesyntax/ii-vynx) by vaguesyntax, which forks
illogical-impulse by end-4. Upstream remotes: `upstream` -> vaguesyntax/ii-vynx.

Hyprland dotfiles based on illogical-impulse, built with Quickshell (QtQuick/QML).

## Commands

- **Run the shell with logs:** `pkill qs; qs -c ii` — QML edits under
  `dots/.config/quickshell/ii/` reload live, no restart needed. Two exceptions: a
  `.pragma library` `.js` stays cached until the shell restarts, and nothing reloads while
  the screen is locked (`LockScreen.qml` turns file watching off under the lock)
- **Restart shell + reload Hyprland:** `iiren run` (alias `iiren restart`)
- **Run settings app:** `qs -p ~/.config/quickshell/ii/settings.qml` (separate QApplication;
  `-c ii settings.qml` is rejected — `qs` takes one config, and `-p` excludes `-c`)
- **Setup/update:** `./setup-ii-ren.sh` or `iiren update` (CLI)
- **Fresh machine:** `./setup-ii-ren.sh --fresh` (deps + base dots + shell + the repo's
  settings, no prompts)
- **Snapshot live settings into the repo:** `iiren save`
- **Legacy setup router:** `./setup <subcommand>` (install, uninstall, exp-merge, etc.)
- **Override a Hyprland option without editing the repo:** `iiren hyprset key|anim|reset|merge`
- **LSP setup:** `touch ~/.config/quickshell/ii/.qmlls.ini` — gitignored, create manually

### Checks (no test framework)

Each `tools/check-*.py` is a standalone assert script; with the JS self-checks below, the
only automated gate. Its docstring says what it guards and why; read that, not a summary
here. Some run the shell's JS under `node`; `check-floating-mode.py` also needs `lua`.

- **Always:** `python3 tools/check-design.py --diff` — design law on added lines
- **What you touched:** `grep -l <FileName> tools/check-*.py`, then run each hit
- **JS logic:** a `<name>.test.js` or `test_<name>.js` beside the file; its first line is
  the `node` command, run from `dots/.config/quickshell/ii`
- **Boots at all:** `bash tools/smoke.sh` (`pkill`s every quickshell, the desktop included);
  `bash tools/smoke-settings.sh` for the settings app;
  `bash tools/probe-settings-pages.sh` after touching `modules/settings/widgets/`
- **Reaching surfaces by hand:** `tools/preview-lock.sh` (lock screen),
  `tools/mock-mpris.py` (fake media players)

Non-trivial logic only verifiable by watching the shell gets a new `tools/check-*.py` in
the same shape: pure asserts, no framework, one concern, the why in its docstring.

## Repo vs live system

`dots/` is the source; `setup-ii-ren.sh` / `iiren update` **copies** it into `~/.config`.
A dev machine usually symlinks `~/.config/quickshell/ii` -> `dots/.config/quickshell/ii`
instead, so QML edits in the repo are live — check with `readlink` before assuming.
`iiren update` does not know about the link: it moves it aside as a backup and copies a
real directory in its place, so run `ln -s` again after one.

What is *not* symlinked flows the other way: `iiren save` pulls
`~/.config/illogical-impulse/config.json` and `~/.config/hypr/custom/*.lua` back into
`dots/`, de-personalising them (`$HOME` -> `~`, wallpaper cleared). Edit settings through
the GUI, then `iiren save`, rather than hand-editing the JSON defaults.

## Hyprland side (Lua, not hyprlang)

`dots/.config/hypr/hyprland.lua` sources `hyprland/*.lua` (env, execs, general, rules,
colors, keybinds) and then any matching `custom/*.lua`, which is where user overrides go
and what `iiren save` preserves. Config is built with the `hl.*` API in `hyprland/lib/`.
Then `workspaces.lua`/`monitors.lua` (Settings > Hyprland > Displays), and last
`hyprland/shellOverrides/main.lua`, which `iiren hyprset` writes — as does every Hyprland
option the shell sets, through its `services/HyprlandSettings.qml` — seeded from
`repo-defaults.lua` on install/update. Loaded last, it beats both: an edit to
`hyprland/general.lua` that seems ignored is usually pinned there.

Two pieces of the shell run inside Hyprland (paths here under
`dots/.config/quickshell/ii/`): `services/floatingMode.lua`, and `services/cursorShake.lua`,
the shake-to-find detector behind `modules/ii/cursorRadar`. Hyprland emits no pointer- or
window-moved event, so each polls on an `hl.timer` and reports through `hl.dsp.event`
(a raw `custom` event in the shell) only when something changed. Their QML side
(`FloatingMode.qml`, `CursorRadar.qml`) `dofile`s them into the compositor's Lua and
installs them again after every reload, since a reload starts a fresh Lua state. Floating
mode's title bars are the hyprbars plugin, built per Hyprland commit by
`scripts/hyprland/hyprbars.sh`; if that fails, the shell draws its own.

`hyprland/general.lua` holds the window-manager animation springs — the same Android 16
motion tokens as the QML side, as mass/stiffness/dampening. Change one and
`tools/check-m3-tokens.py` is what tells you the damping ratio still matches AOSP.

## QML Architecture

### Entry Points

| File | Role |
|---|---|
| `dots/.config/quickshell/ii/shell.qml` | Main shell entry (`qs -c ii`). Uses `ShellRoot` |
| `dots/.config/quickshell/ii/settings.qml` | Settings app. Uses `ApplicationWindow` (separate process) |

### Panel Families (`panelFamilies/`)

Two mutually exclusive UI styles loaded via `LazyLoader`. Switch with `Super+Ctrl+P` or `qs -c ii ipc call panelFamily cycle`.
But focus on the ii (Illogical-Impulse) panel family when making any changes unless otherwise stated.

- **`IllogicalImpulseFamily.qml`** — original ii style (bar, sidebars, dock, etc.)
- **`WaffleFamily.qml`** — Windows 11-like (action center, start menu, task view)
- Shared components (alt-tab, cheatsheet, drop shelf, OSK, overlay, screen translator, wallpaper selector) are imported in both

### Core Singletons (`modules/common/`)

- **`Config.qml`** — All shell options. Backed by `FileView` + `JsonAdapter` at `~/.config/illogical-impulse/config.json`. Has `readWriteDelay` (default 75ms) to batch writes. Check `Config.ready` before accessing options.
- **`GlobalStates.qml`** (shell root, `import qs` — not this directory) — Centralized UI state booleans (`policiesPanelOpen`, `dashboardPanelOpen`, `overlayOpen`, `overviewOpen`, etc.). The two sidebars are `modules/ii/sidebarPolicies/` (left by default) and `modules/ii/sidebarDashboard/` (right); `sidebarLeftOpen`/`sidebarRightOpen` are legacy aliases for them. Also has `effectiveLeftOpen`/`effectiveRightOpen` computed properties that respect `Config.options.sidebar.position`.
- **`Persistent.qml`** — Runtime state that outlives a restart but is not a setting (`Persistent.states.*`, e.g. whether floating mode is on), in `~/.local/state/quickshell/states.json`. Check `Persistent.ready`.
- **`Directories.qml`** — XDG paths and internal config paths. All paths use `file://` protocol except noted "without file://" ones. Use `FileUtils.trimFileProtocol()` to strip.
- **`Appearance.qml`** — Colors, fonts, rounding, animation curves
- **`Icons.qml`**, **`Images.qml`** — Icon/image resources

### Module Layout

```
modules/
  common/       # Shared utilities, Config, Appearance, widgets
    widgets/    # Common widgets used accross the repo to maintain Material 3 style
    models/     # Non-visual models, including the quick toggles' (models/quickToggles/)
    panels/     # Panels both families mount (the lock screen)
  ii/           # Illogical-impulse panel components
  waffle/       # Waffle panel components
  settings/     # Settings app pages (QuickConfig, BarConfig, etc.)
services/       # Backend services (Audio, Battery, Network, MprisController, HermesService, etc.)
user_widgets/   # Installed extensions (see Extension System)
defaults/       # Shipped default assets/config the shell falls back to
scripts/        # Shell-invoked helper scripts
```

### Loader Pattern

`PanelLoader.qml` wraps `LazyLoader`. Always check `Config.ready`:
```qml
PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
```

**Important:** When using `Loader`/`LazyLoader`, declare `anchors` and positioning on the Loader itself, not the `sourceComponent`. For fade animations, use `FadeLoader` with `shown` prop.

### Import Conventions

- `qs.modules.common` → `modules/common/`
- `qs.modules.common.widgets` → `modules/common/widgets`
- `qs.modules.ii.*` → `modules/ii/*/`
- `qs.modules.waffle.*` → `modules/waffle/*/`
- `qs.services` → `services/`
- `qs.modules.common.functions as CF` → utility functions

## Config Schema

Config lives in `Config.qml` as nested `JsonObject` properties. Key top-level groups:
- `panelFamily` — "ii" or "waffle"
- `appearance` — theme, fonts, transparency, wallpaper theming, `fakeScreenRounding` (0-3)
- `bar` — layout, workspaces, layouts (left/center/right component arrays), vertical mode
- `sidebar` — position ("default"/"inverted"/"left"/"right"), quickToggles, quickSliders
- `background` — wallpaper, widgets (clock/media/weather), parallax
- `lock` — lock screen, blur, `useHyprlock`
- `waffles` — Waffle-specific tweaks (bar, actionCenter toggles)
- `hermes` — the left sidebar's chat with a hermes-agent install (local or over ssh): tool calls, notifications, dictation
- `policies` — feature flags (weeb, wallpapers, translator, continuity, hermes)

Access via `Config.options.bar.vertical`, `Config.options.appearance.sharpMode`, etc.

## QML Style

- **Indent:** 4 spaces, no tabs (`.qmlformat.ini`)
- **Spacing:** Space between text and operators: `if (condition) { ... }`
- **Blank lines:** Group related properties/children, no 2+ consecutive blanks
- **Components:** Use `component` keyword for in-file reusable components
- **Early return:** Prefer `if (!condition) return; doStuff()` over deep nesting
- **Conditional loading:** Use `Loader`/`LazyLoader` for anything guarded by config options

## Extension System

Writing one: `.github/EXTENSIONS.md`. How the system works: `.github/EXTENSIONSARCHITECTURE.md`.
Installed extensions live in `user_widgets/` and load without a shell restart.

## Vendored code

`modules/common/widgets/shapes` is end-4/rounded-polygon-qmljs, vendored (was a
submodule). Update it by copying upstream over it.

What came from ii-p3drovfx (the background widgets, the bar popups and cards, the quick
toggles) arrives only through the port scripts in `tools/p3-*`. Nothing new is imported
from it (`TASTE.md` 9).

## Design law — applies to every change, unasked

This shell imitates Android 16 / Material 3 Expressive. That is not a feature
request that was fulfilled once; it is the standing spec for everything in it.

**Before writing or changing any QML that draws, moves, or responds to input,
read `.github/DESIGN.md`.** It has the motion tokens, interaction specs, shape
and spacing scales, effect budget and per-component recipes, with every number
traced to its AOSP source. Do not ask whether Android-style motion is wanted —
it is the default. New widgets get it on the first pass.

**Before designing a feature, restructuring a surface or auditing a UI — anything
asked for as "make it better" — read `.github/TASTE.md` as well.** `DESIGN.md` says
how things move and which numbers to use. `TASTE.md` says what a surface should be,
what does not belong on it, how it behaves when it is empty or wrong, and which
calls the owner has already made. It ends with the questions that every brief and
every UI audit answers.

The condensed version, so nothing is missed even without opening that file:

1. **Reuse first.** ~155 widgets live in `modules/common/widgets/`. A button is
   `RippleButton`, a list is `StyledListView`, a popup follows `DockFolderPopup`.
2. **Never invent a number.** Durations and curves come from
   `Appearance.animation.*` / `Appearance.animationCurves.*`, radii from
   `Appearance.rounding.*`, colours from `Appearance.colors.*`, shared sizes
   from `Appearance.sizes.*`. No literal `duration:`, no hex, no literal radius.
3. **Spatial vs effects.** Position/size/shape animate on a spatial spec and may
   overshoot. Opacity/colour animate on an effects spec and must never overshoot.
4. **Enter and exit are asymmetric.** Enter decelerating on default spatial,
   exit accelerating on fast effects at about half the duration. Both required.
5. **Transform origin is deliberate.** A surface grows out of whatever opened it.
6. **Four states, always.** Hover 0.08, focus 0.10, pressed 0.10, dragged 0.16 —
   via `colLayerNHover`/`colLayerNActive` or `StateOverlay`. Disabled is
   `opacity: 0.4`.
7. **Spacing on the 4dp grid**; child radius smaller than parent radius.
8. **Effects are a budget** — integrated graphics is the target. One
   layer/effect per widget, never inside a repeated delegate.
9. **Do not apply a spec globally to a shared base widget** without checking
   every caller. That is how a pressed-shape default squared 58 pill buttons.
10. **Measure motion at 60fps.** Never eyeball a timing change.
11. **No separator bars / dividers.** Separate sections with whitespace on the
    4dp grid (12–16dp) and container layer cards (`colLayer1`/`colLayer2`), not
    horizontal separator lines of any kind. Never use negative
    margins to pull controls closer to a divider.

Before calling a UI change done, run the design-check review — `/design-check`
in Claude Code, the `design-check` skill in agy, both driven by
`.agents/skills/design-check/SKILL.md`. It runs `tools/check-design.py` for the
mechanically checkable rules, then reads the diff for the ones a script cannot
see — transform origin, spatial-vs-effects, enter/exit pairing, layer nesting,
effects in delegates, missed reuse.
`tools/check-m3-tokens.py` asserts the tokens still match AOSP; run it after
touching motion tokens or state layer values.
