<div align="center">
     <h1> ii-ren </h1>
     <h3> <b> My Hyprland shell — a fork of <a href="https://github.com/vaguesyntax/ii-vynx">ii-vynx</a> </b> </h3>
</div>

<div align="center">

<img src="./assets/screenshots/1.png">

<div style="display:flex; gap:10px; justify-content:center;">
  <img src="./assets/screenshots/3.png" width="48%" />
  <img src="./assets/screenshots/2.png" width="48%" />
</div>
<div style="display:flex; gap:10px; justify-content:center;">
  <img src="./assets/screenshots/5.png" width="48%" />
  <img src="./assets/screenshots/4.png" width="48%" />
</div>

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

- **Continuity panel** — a left-sidebar tab with your phone over KDE Connect (battery,
  mirrored notifications with inline reply, ring / send file / messages / push clipboard),
  Bluetooth device battery, and your Tailscale peers with copy-IP, SSH, Taildrop and
  exit-node routing.
- **Desktop widgets** — the [ii-p3drovfx](https://github.com/P3DROVFX/ii-p3drovfx) widget library vendored onto the
  background canvas, with a widget manager and colour-scheme picker in Settings.
- **Fast Pair** — an Android-style popup for nearby Bluetooth devices.
- **Screen snip preview** — an Android-style card after `Super+Shift+S`, with save,
  annotate and discard.
- **Launcher depth** — the wallpaper pushes back and everything behind the launcher dims.
- **Dock hover** — app names on hover and a rebuilt window-preview card.
- **Bar** — CPU / RAM / CPU-temp in the resources widget, and the ii-p3drovfx hover popups.
- **Wallpaper drop** — drop an image anywhere on the desktop to set it.

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
