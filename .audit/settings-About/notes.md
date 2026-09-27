# settings-About — notes

- Opens with `II_SETTINGS_PAGE=about qs -p ~/.config/quickshell/ii/settings.qml`.
  `settings.qml` reads that env var for its start page. There is no IPC.
- The System card sits below the fold at the default 1100x750. `hyprctl dispatch
  resizewindowpixel` is a Lua syntax error in this config. The after-shot of that card
  came from moving the section to the top in a throwaway copy, then restoring the file.
- The egg (three presses opens `EasterEggWindow`) was not driven with a real click. The
  handler is the old one, moved from the `MouseArea` to a `RippleButton`'s `onClicked`.
- `WARN: Could not load icon "linux-symbolic"` is in the log before and after. It comes from
  `SystemInfo.distroIcon`'s default, not from this page.
- Not changed, `SystemInfo` is out of scope: its os-release regexes only match *quoted*
  values (`/^HOME_URL="(.+?)"/m`). The spec allows unquoted ones, so on a distro that
  writes them bare every URL comes back empty and this page shows no chips at all. That
  is correct behaviour, because an empty chip is now dropped, but the chips are still
  missing.
