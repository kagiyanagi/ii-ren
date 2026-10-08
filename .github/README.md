<div align="center">

# ii-ren

**Hyprland that moves like butter**

A Quickshell desktop tuned to Material 3 Expressive, with genuine AOSP motion curves. 
Fast, pretty, and lightweight enough that your fans won't spool up just looking at it.

</div>

## what's in it (besides vynx & p3)

<!-- hero.gif: live weather on the wallpaper, then a window opening on the springs -->

**✦ motion** · Hyprland windows on Android 16's motion springs · compose state layers and ripples · stretch overscroll on every list · AOSP icons

**✦ subject depth** · the clock sits behind whoever's in your photo · bring your own mask · works on video wallpapers too

**✦ desktop** · GPU wallpaper effects: AOSP's live weather, the custom-ROM set, fluted glass with real refraction

**✦ lock screen** · charging and unlock ripples · workspace rises as you unlock

**✦ dock** · app folders · curves into the screen edge

**✦ together** · **Hermes** in the left sidebar, with an MCP server that drives apps through accessibility · Continuity: phone, earbuds and Tailscale peers in one panel · Fast Pair · several speakers at once, each at its own volume

**✦ windows** · floating mode with title bars, minimize and rails · shake the cursor to find it

**✦ settings** · redesigned · autostart apps · Evolution X and Iconify battery styles · three taps on my shell's icon. You'll see.

**✦ little things** · AOSP volume dialog · notification cooldown · Android copy card · snip preview · QR scan from search · offline screen translator with Mokuro · searchable cheatsheet with your own binds · Google Calendar via iCal · Markdown to-do · keep-awake duration dial · SDDM theme

> I borrowed a lot of features and design ideas from [p3drovfx](https://github.com/P3DROVFX/ii-p3drovfx), like the Material panel and the desktop widgets. I also added plenty of my own: a better periodic table, weather in the cheatsheet, a redesigned countdown timer and recording chips, the policies and right sidebars, and more.

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

## credits

Forked from [ii-vynx](https://github.com/vaguesyntax/ii-vynx) by [vaguesyntax](https://github.com/vaguesyntax), which forks [illogical-impulse](https://github.com/end-4/dots-hyprland) by [end-4](https://github.com/end-4), the absolute madman. Desktop widgets, and lots of design stuff mugged from [P3DROVFX](https://github.com/P3DROVFX/ii-p3drovfx). Runs on [Quickshell](https://quickshell.org/) and [Hyprland](https://hypr.land/).
