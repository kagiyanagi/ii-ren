<div align="center">
     <h1> ii-ren </h1>
     <h3> <b> My Hyprland shell — a fork of <a href="https://github.com/vaguesyntax/ii-vynx">ii-vynx</a> </b> </h3>
</div>

<!-- <div align="center">

<img src="./assets/screenshots/1.png">

<div style="display:flex; gap:10px; justify-content:center;">
  <img src="./assets/screenshots/3.png" width="48%" />
  <img src="./assets/screenshots/2.png" width="48%" />
</div>
<div style="display:flex; gap:10px; justify-content:center;">
  <img src="./assets/screenshots/5.png" width="48%" />
  <img src="./assets/screenshots/4.png" width="48%" />
</div> -->

</div>

<div align="center">
    <h2> what this is </h2>
</div>

**ii-ren is a fork of [ii-vynx](https://github.com/vaguesyntax/ii-vynx) by [vaguesyntax](https://github.com/vaguesyntax)**, which is itself a fork of
[illogical-impulse](https://github.com/end-4/dots-hyprland) by [end-4](https://github.com/end-4). Nearly all of the shell
you see here is their work. This repo is my personal daily driver on top of it: my
settings, my keybinds, and the handful of features below.

If you are looking for the upstream project — the one with the docs, the wiki, the
extension ecosystem and the Discord channel — **go to [ii-vynx](https://github.com/vaguesyntax/ii-vynx) and star it there.**

> **Warning:** this is a personal fork of a personal fork. I break things on purpose and
> fix them later. Expect bugs. Use at your own risk.

<div align="center">
    <h2> what this fork adds </h2>
</div>

- **Conduit** — an agent CLI (Claude Code or Antigravity) as a first-class sidebar
  page and as a floating overlay you can pin over every window (`Super+Shift+G`),
  with chat history and voice memo. It ships an MCP server that hands the agent real
  desktop control: it reads the focused app's widget tree over AT-SPI and presses
  controls through their own accessible action, so no screenshot round-trip and no
  aiming a cursor.
- **Continuity panel** — a left-sidebar tab with your phone over KDE Connect (battery,
  notifications with inline reply, ring / send file / messages / push clipboard),
  Bluetooth device battery, and your Tailscale peers with copy-IP, SSH, Taildrop and
  exit-node routing. Phone notifications stay in the panel instead of doubling up on
  the desktop, with swipe-to-dismiss, clear-all, and a toggle to mirror them anyway.
- **Fast Pair** — Android's one-tap pairing card for nearby earbuds and speakers,
  ranked by signal strength read straight from BlueZ, since Quickshell exposes no RSSI.
  One press pairs, trusts and connects, retrying while the buds settle into pairing
  mode. Snooze, never-show-this-one and mute-all sit on the card. Off by default: it
  keeps the adapter discovering whenever nothing is connected.
- **Privacy indicators** — bar indicators naming what is using the microphone and what
  is using location, plus a quick toggle that actually masks GeoClue.
- **Alt+Tab switcher** — a macOS-style row of app icons in MRU order, focusing on Alt
  release, with an optional current-workspace-only filter.
- **Wallpaper effects** — the effect set every custom ROM ships, reimplemented as GPU
  shaders: grayscale, sepia, negative, posterize, pixelation, sharpen, chromatic
  aberration and radial blur, with saturation, dim, vignette and grain on top, the
  ROMs' Glass and Frosted blur styles, and a desktop / lock / both target. Plus
  fluted glass, which no ROM has — real refraction through Snell's law with
  dispersion and a highlight down each rib. Every filter previews live in Settings.
- **Desktop widgets** — the [ii-p3drovfx](https://github.com/P3DROVFX/ii-p3drovfx) widget library vendored onto the
  background canvas, with a widget manager and colour-scheme picker in Settings.
- **Drop shelf and right-click menu** — drop anything that is not a wallpaper on the
  desktop and it parks on a shelf at the drop point, to pile up and drag back out
  one at a time; right-click for wallpaper actions, the shelf and settings.
- **Wallpaper drop** — drop an image anywhere on the desktop to set it.
- **Android quick toggles** — rebuilt as a real editable grid: drag to move, corner
  handles to resize, tiles in four sizes with rich wifi and bluetooth cards, sliders
  as grid tiles, and toggles spilling onto pages you swipe between.
- **Dock** — a blurred cover-art media card with a cava wave, media controls that open
  where the widget actually is, app names on hover, a rebuilt window-preview card,
  click bounce, an accented app-menu button, and a pinned dock that gets out of the
  way of fullscreen windows.
- **Bar** — CPU / RAM / CPU-temp in the resources widget, the ii-p3drovfx hover popups,
  and a keyboard-backlight button.
- **Screen snip preview** — an Android-style card after `Super+Shift+S`, with save,
  annotate and discard, in whichever corner and for however long you set.
- **Screen translator** — OCR and translation with tesseract and translate-shell
  instead of a billed Google Cloud key.
- **LocalSend** — the protocol spoken directly in stdlib Python, so it works without
  the abandoned `localsend-cli` package.
- **Calendar** — Google Calendar events through iCal feeds, with event days dotted in
  the sidebar and a click on any day opening GCal there.
- **Automatic dark mode** — follows the night light schedule, which is now editable in
  Settings.
- **Countdown timer** — replaces the pomodoro; click the time and type minutes or MM:SS.
- **To-do list in Markdown** — backed by a checklist file, so the same list opens as a
  note in any editor or vault and edits flow both ways.
- **Multi-device audio** — pick two or more outputs or inputs and they become one
  virtual device, kept across reloads.
- **Autostart** — launch apps at login from Settings, each on its own workspace, with a
  delay between them.
- **Hyprland settings page** — displays, tiling, appearance, input and animations edited
  from the GUI, read live from the compositor, with a drag-to-arrange display canvas.
- **Launcher depth** — the wallpaper pushes back and everything behind the launcher dims.
- **Uptime pill** — a single-line badge in the sidebar wearing your user avatar, or any
  image you point it at.
- **Android 16 motion** — Hyprland and the shell both run on Material 3 Expressive's
  motion physics, with the spring constants lifted from AOSP's own token files instead of
  eyeballed: six springs, spatial ones for anything that moves or resizes and critically
  damped effects ones for colour and opacity, converted from Android's damping *ratio*
  into the damping *coefficient* Hyprland's solver wants. The compositor runs them
  natively, so duration falls out of the physics instead of a hardcoded speed, and a
  self-check in `tools/` fails if any constant drifts off its token. Lists and flickables
  stretch at the edges like Android's, done with a transform rather than an offscreen
  layer, so it costs nothing until something overscrolls.
- **Faster on integrated graphics** — the wallpaper effect chain bakes once and stops
  re-rendering per frame, the lock blur bakes the same way, and desktop parallax moved
  off the anchor solver: about 22 points of main thread back on a battery-clocked
  TigerLake.
- **~7.7k lines lighter** — a repo-wide over-engineering audit, applied.

<div align="center">
    <h2> on the list </h2>
</div>

Not built yet. No dates.

- **VPN management** — on rightbar
- **Icon and cursor themes** — pick them from Settings, like everything else.
- **Lock screen customization** — layout, clock and widgets (also notificaions history like andorid).
- **Floating window management** — tiling for the windows that aren't tiled.
- **Lyrics** — word-by-word synced, in the media surfaces.
- **Depth wallpaper** — the one ROM effect the shader set left out; it needs ML
  subject segmentation.
- **More desktop widgets.**

<div align="center">
    <h2> installation </h2>
</div>

One command, on a fresh machine, no prompts:

```bash
git clone https://github.com/kagiyanagi/ii-ren.git --recurse-submodules && cd ii-ren && ./setup-ii-ren.sh --fresh
```

`--fresh` installs the base illogical-impulse dependencies and dots first, then this
shell over the top, and answers every prompt for you. It is the only thing you need on a
clean install.

If you already run illogical-impulse or ii-vynx and just want this shell over the top:

```bash
./setup-ii-ren.sh
```

All flags:

```bash
./setup-ii-ren.sh --help
```

<div align="center">
    <h2> updating </h2>
</div>

- **CLI:** `iiren update`
- **Script:** run `./setup-ii-ren.sh` again
- **UI:** the update button in the dashboard panel

To push the settings you have changed in the GUI back into this repo, run `iiren save` —
it copies your live `config.json` and Hyprland overrides into `dots/`, ready to commit.

<div align="center">
    <h2> extensions </h2>
</div>

The extension system is upstream's and is shared with ii-vynx — extensions published for
ii-vynx install here unchanged. See **Settings > Extensions**, and
[EXTENSIONS.md](https://github.com/kagiyanagi/ii-ren/blob/main/.github/EXTENSIONS.md) to build your own.

<div align="center">
    <h2> credits </h2>
</div>

**[vaguesyntax](https://github.com/vaguesyntax):** author of [ii-vynx](https://github.com/vaguesyntax/ii-vynx), the shell this fork is built on. Everything here starts from their work.

**[end-4](https://github.com/end-4):** the absolute madman behind [illogical-impulse](https://github.com/end-4/dots-hyprland), which ii-vynx forked in turn.

**[P3DROVFX](https://github.com/P3DROVFX/ii-p3drovfx):** the desktop widget library this fork vendors.

**[Quickshell](https://quickshell.org/):** the flexible, Qt-Quick based widget system making this shell possible.

**[Hyprland](https://hypr.land/):** loves-to-crash wayland compositor.

```text
[ii-ren]: fork of ii-vynx. star the original. ⭐
```
