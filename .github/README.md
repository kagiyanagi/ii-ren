<div align="center">

# ii-ren

**Hyprland that moves like a Pixel.**

A Quickshell desktop built to Android 16 and Material 3 Expressive.<br>
Window springs lifted from AOSP's motion tokens. Nothing eyeballed.

</div>

## what's in it

- **Hermes** agent in the sidebar, local or over ssh, with an MCP server that drives apps through accessibility instead of screenshots
- **Wallpaper effects** as GPU shaders, including AOSP's live weather and fluted glass with real refraction
- **Subject depth**: the clock sits behind whatever is in your photo
- **Floating mode** with title bars, for when tiling isn't the mood
- **Continuity**: your phone, earbuds and Tailscale peers in one panel
- **Lock screen** with fingerprint unlock and AOSP's charging and unlock ripples
- Quick toggle grid you drag and resize, Fast Pair, privacy chips, shake to find the cursor, synced lyrics, Alt+Tab, LocalSend

## install

Needs Hyprland 0.56 or later (the config is Lua). The setup installs it, with every other dependency, on:

- **Arch** and Arch-based distros (CachyOS, EndeavourOS)
- **Fedora 44+**, from the `sdegler/hyprland` COPR
- **Gentoo**, from GURU and hyproverlay, on a `desktop` or `desktop/systemd` profile
- **anything else** (Debian, openSUSE…) through Nix and Home Manager. There the lock
  screen hands off to your distro's hyprlock or swaylock, because a Quickshell
  installed through Nix can't check passwords against the host's PAM

```bash
git clone https://github.com/kagiyanagi/ii-ren.git && cd ii-ren && ./setup-ii-ren.sh --fresh
```

Already on illogical-impulse or ii-vynx? Run `./setup-ii-ren.sh` without the flag.
After that, `iiren update` keeps you current.

## keys

`Super` search · `Super+A` / `Super+N` sidebars · `Super+Tab` overview · `Super+I` settings · `Super+/` everything else

## credits

Forked from [ii-vynx](https://github.com/vaguesyntax/ii-vynx) by [vaguesyntax](https://github.com/vaguesyntax) (go star it), which forks [illogical-impulse](https://github.com/end-4/dots-hyprland) by [end-4](https://github.com/end-4), the absolute madman. Desktop widgets from [P3DROVFX](https://github.com/P3DROVFX/ii-p3drovfx). Runs on [Quickshell](https://quickshell.org/) and [Hyprland](https://hypr.land/).
