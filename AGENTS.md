# AGENTS.md - ii-ren

Fork of [ii-vynx](https://github.com/vaguesyntax/ii-vynx) by vaguesyntax, which forks
illogical-impulse by end-4. Upstream remotes: `upstream` -> vaguesyntax/ii-vynx.

Hyprland dotfiles based on illogical-impulse, built with Quickshell (QtQuick/QML).

## Commands

- **Run settings app:** `qs -c ii settings.qml` (separate QApplication)
- **Setup/update:** `./setup-ii-ren.sh` or `iiren update` (CLI)
- **Fresh machine:** `./setup-ii-ren.sh --fresh` (deps + base dots + shell, no prompts)
- **Snapshot live settings into the repo:** `iiren save`
- **Legacy setup router:** `./setup <subcommand>` (install, uninstall, exp-merge, etc.)
- **LSP setup:** `touch ~/.config/quickshell/ii/.qmlls.ini` — gitignored, create manually

## QML Architecture

### Entry Points

| File | Role |
|---|---|
| `dots/.config/quickshell/ii/shell.qml` | Main shell entry (`qs -c ii`). Uses `ShellRoot` |
| `dots/.config/quickshell/ii/settings.qml` | Settings app. Uses `ApplicationWindow` (separate process) |

### Panel Families (`panelFamilies/`)

Two mutually exclusive UI styles loaded via `LazyLoader`. Switch with `Super+Ctrl+R` or IPC call `panelFamily cycle`.
But focus on the ii (Illogical-Impulse) panel family when making any changes unless otherwise stated.

- **`IllogicalImpulseFamily.qml`** — original ii style (bar, sidebars, dock, etc.)
- **`WaffleFamily.qml`** — Windows 11-like (action center, start menu, task view)
- Shared components (cheatsheet, OSK, overlay, screen translator, wallpaper selector) are imported in both

### Core Singletons (`modules/common/`)

- **`Config.qml`** — All shell options. Backed by `FileView` + `JsonAdapter` at `~/.config/illogical-impulse/config.json`. Has `readWriteDelay` (default 75ms) to batch writes. Check `Config.ready` before accessing options.
- **`GlobalStates.qml`** — Centralized UI state booleans (`sidebarLeftOpen`, `sidebarRightOpen`, `overlayOpen`, `overviewOpen`, etc.). Also has `effectiveLeftOpen`/`effectiveRightOpen` computed properties that respect `Config.options.sidebar.position`.
- **`Directories.qml`** — XDG paths and internal config paths. All paths use `file://` protocol except noted "without file://" ones. Use `FileUtils.trimFileProtocol()` to strip.
- **`Appearance.qml`** — Colors, fonts, rounding, animation curves
- **`Icons.qml`**, **`Images.qml`** — Icon/image resources

### Module Layout

```
modules/
  common/       # Shared utilities, Config, Appearance, widgets
    widgets/    # Common widgets used accross the repo to maintain Material 3 style
  ii/           # Illogical-impulse panel components
  waffle/       # Waffle panel components
  settings/     # Settings app pages (QuickConfig, BarConfig, etc.)
services/       # Backend services (Ai, Audio, Battery, Network, MprisController, etc.)
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
- `ai` — system prompt, models, tools
- `policies` — feature flags (ai, weeb, wallpapers, translator)

Access via `Config.options.bar.vertical`, `Config.options.appearance.sharpMode`, etc.

## QML Style

- **Indent:** 4 spaces, no tabs (`.qmlformat.ini`)
- **Spacing:** Space between text and operators: `if (condition) { ... }`
- **Blank lines:** Group related properties/children, no 2+ consecutive blanks
- **Components:** Use `component` keyword for in-file reusable components
- **Early return:** Prefer `if (!condition) return; doStuff()` over deep nesting
- **Conditional loading:** Use `Loader`/`LazyLoader` for anything guarded by config options

## Extension System

The details of creating a new extension is in the file `EXTENSIONS.md` located at `.github/EXTENSIONS.md`.

The details of the implementation of the extension system is in the file `EXTENSIONARCHITECTURE.md` located at `.github/EXTENSIONSARCHITECTURE`.

## Git Setup

- **Must clone with `--recurse-submodules`** — submodule at `modules/common/widgets/shapes` (rounded-polygon-qmljs)
- `.qmlls.ini` is gitignored — agents must create it manually for LSP

## Design law — applies to every change, unasked

This shell imitates Android 16 / Material 3 Expressive. That is not a feature
request that was fulfilled once; it is the standing spec for everything in it.

**Before writing or changing any QML that draws, moves, or responds to input,
read `.github/DESIGN.md`.** It has the motion tokens, interaction specs, shape
and spacing scales, effect budget and per-component recipes, with every number
traced to its AOSP source. Do not ask whether Android-style motion is wanted —
it is the default. New widgets get it on the first pass.

The condensed version, so nothing is missed even without opening that file:

1. **Reuse first.** ~140 widgets live in `modules/common/widgets/`. A button is
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
    horizontal separator lines or `WindowDialogSeparator`. Never use negative
    margins to pull controls closer to a divider.

Before calling a UI change done, run the design-check review — `/design-check`
in Claude Code, the `design-check` skill in agy, both driven by
`.agents/skills/design-check/SKILL.md`. It runs `tools/check-design.py` for the
mechanically checkable rules, then reads the diff for the ones a script cannot
see — transform origin, spatial-vs-effects, enter/exit pairing, layer nesting,
effects in delegates, missed reuse.
`tools/check-m3-tokens.py` asserts the tokens still match AOSP; run it after
touching motion tokens or state layer values.
