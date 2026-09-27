# ii-verticalBar — notes

The vertical bar was forked from the horizontal one before the `ii-bar-*` rows
fixed it, so most of this row is carrying those fixes across. `brief.md` lists
them; this is what the diff will not show.

## How it was looked at without touching the desktop

This machine runs `bar.vertical: false`, and flipping it writes the user's
config. Instead: a throwaway `qs -p` config in the shell dir that loads only the
vertical bar, shot with `grim`, then killed and deleted —

```sh
cd dots/.config/quickshell/ii
printf 'import Quickshell\nimport qs.modules.ii.verticalBar\n\nShellRoot {\n    VerticalBar {}\n}\n' > probe-vbar.qml
qs -p $PWD/probe-vbar.qml --no-color > /tmp/vbprobe.log 2>&1 &   # wait for quickshell:verticalBar in `hyprctl layers`
timeout 5 grim -g "0,0 120x1080" shot.png; kill %1; rm probe-vbar.qml
```

It runs beside the real shell (second process, own IPC), so nothing is
restarted, but its exclusive zone reflows tiled windows for the seconds it is
up. `shot-before.png` is HEAD's files through the same probe.

## Motion to verify at 60fps (cohesion pass)

- Auto-hide on, both `bar.bottom` values: the strip slides in on
  `elementMoveEnter` and out on `elementMoveExit`, and hidden it is fully off
  screen — before, the right-hand bar parked at `-barHeight` (40) and a 46px
  bar left 6px showing. `check-bar-reveal.py` now sweeps both files.
- Timer pill: start a stopwatch, then a pomodoro, then reset one. Each chip
  grows/collapses on `Revealer`, the gap on `elementMove`, no second Behavior
  chasing the pill height.

## Left alone, with reasons

- **Binding loop on the right list's `Repeater.model`** — present at HEAD too
  (three warnings per start). `BarComponent.toggleVisible` writes
  `layouts.right[i].visible`, which is the Repeater's model, while delegates are
  still being built. `BarComponent` is frozen for this row; it belongs to a
  `ii-bar-widgets` revisit, and the horizontal bar reads the same arrays.
- **Resource rings toggled in Settings appear and vanish with `visible:`.** The
  horizontal `Resource` slides out; this one does not. A settings toggle, not a
  runtime appearance, so it was not worth a second animation path here.
- **Timer chips are 22px wide and mouse-only**, same as the horizontal
  `TimerWidget` — under the 32px hit area and with no focus state. Fix both bars
  together or neither.
- **`active_window` and `weather` overflow the strip** in `shot-after.png`
  (the class name runs vertically, `26°C` is wider than the bar). Both are shared
  `BarComponent` widgets that take `vertical:`; not this row's files.
- **`deadPixelWorkaround`** is applied by `Bar.qml` and never was here. Nobody on
  a vertical bar has asked; add it by mirroring `Bar.qml`'s `margins` block onto
  the right anchor if they do.
- **`showNetwork`** is still not honoured: it needs `NetworkUsage.activeInstances`
  counting, which `bar/Resources.qml` does and this file would have to duplicate.
