# Cohesion pass — notes

Run 2026-09-27 from the stills. The motion half is **declined**: the owner does not want
animation changes, so the 60fps watch list in DECISIONS.md stays as a record, not a to-do.

## The contact sheet

`contact-sheet.jpg` is every `shot-after.png` in `.audit/`, 62 of them, eight to a row with
the row id under each. Rebuild it with:

```sh
args=(); for f in .audit/*/shot-after.png; do args+=(-label "$(basename $(dirname $f))" "$f"); done
magick montage "${args[@]}" -font "$(fc-match -f '%{file}' Rubik)" -tile 8x -geometry '440x440>+10+10' \
  -background '#1b1b1f' -fill '#e4e1e6' -pointsize 16 -quality 82 .audit/cohesion/contact-sheet.jpg
```

`montage` needs `-font` here. Without one it fails on the labels with "unable to read font".
At sheet scale the full-screen shots show the owner's windows more than the surface, so the
review read one sheet per cluster at 620px tiles, and crops at full size for the calls below.

What the sheet cannot show:

- **47 rows have no after-shot.** All seven bar rows (they ran in parallel and none could
  drive the shell), `ii-overlay`, `ii-topLayer`, `ii-wrappedFrame`, all fourteen waffle rows,
  and the widget tranches (all but five `cw-*`, every `sw-*`), which change widgets rather
  than surfaces.
- **Hue is not comparable across it.** The shots span 2026-09-20 to 09-27 and at least three
  wallpapers: the `cw-*` shots are teal, most later ones green, `ii-keypressDisplay` red. A
  fill that looks off beside its neighbour is usually another palette, not another token.
  Shape, type, spacing and which component was used are comparable.

## Outliers, and what happened to them

1. **Settings had two text-field styles. Fixed** (`cohesion-text-fields`,
   `shot-after-text-fields.png`). `MaterialTextField` is M3's outlined field.
   `MaterialTextArea` was the filled one: a hand-built `m3surface` box with an indicator
   line. Outlined: Bar 2, General 3, Hermes 3, Hyprland 1, Interface 1, Quick 2. Filled:
   Services 18, Hermes 1, Interface 3. Hermes's Behaviour section had both at once: Persona
   outlined, the System prompt under it filled, and Reasoning effort outlined again. M3 lets a
   product use either style, but not both mixed in one region. The fix deletes
   `MaterialTextArea`'s background, so Qt's Material `TextArea` draws its own outlined
   container, the one `MaterialTextField` already gets. It also turns on `clip`, as
   `MaterialTextField` does, since that is what gives the floating label its top inset. No
   call site changed. What the diff does not show:
   - Every `MaterialTextArea` is now 10px taller, which is the inset the label needs. The
     box is still 56px. On Services the fields were 60px apart and are now 70px (measured
     down one pixel column of the shots), so with 18 of them that page is about 180px
     longer.
   - The focus indicator no longer thickens on an animation. Qt's container draws the
     focused outline the way it always has for `MaterialTextField`, so the two now match.
   - The fourth caller is the overlay notes widget's tab rename fields
     (`overlay/notes/NotesContent.qml`, `EditInput`), and they turn outlined too. They were
     read, not looked at: they set their own `topInset`, which `clip` does not override.
2. **Quick settings had the one hand-rolled empty state. Fixed**
   (`cohesion-empty-favourites`, `shot-after-empty-favourites.png`). `QuickConfig.qml` drew
   a bare 30px star and two lines of text. Everywhere else an empty state is
   `PagePlaceholder`: notifications, Hermes, the translator, the Hermes sheets, and the
   wallpaper selector's own favourites. The selector's is the same list, with a heart where
   Quick had a star. Quick now uses that same placeholder, with the 200ms hold before it
   shows kept.
3. **The divider lines in the shots are the owner's config, not a regression.** Every dock
   shot has four vertical rules and the bar two pipes. `Config.qml` ships
   `dock.separatorStyle: "Empty"` and new bar spacers as `empty` (DECISIONS 10), but the live
   config sets `"Line"` and two spacers to `"style": "pipe"`. DECISIONS keeps a style a config
   explicitly picked, and whether the spacers should exist is already listed there as the
   owner's call. The thing to know is that `iiren save` would copy `"Line"` into the shipped
   defaults.

Looked at and not outliers:

- Every dialog — the five sidebar dialogs, polkit, the keybind editor — is `WindowDialog` with
  `WindowDialogTitle`, `WindowDialogButtonRow` and `DialogButton`. The title that looked
  smaller in the Bluetooth shot is a smaller crop.
- The cyan edge around both sidebars in several shots is wallpaper inside the crop margin.
- Tabs come in two styles for two jobs: pills to switch pages (the left sidebar, the
  cheatsheet) and underlines inside a card (Timer/Stopwatch, Unfinished/Done, Live/History).
  Each is used the same way everywhere.

## Driving the screen

Taking the screen needs asking first. The first recording attempt switched workspaces out
from under a fullscreen video. The shots of the two fixes were one short settings window per
page, with six wheel notches of `ydotool` to reach Behaviour and thirty to reach Save paths.
The pointer was put back afterwards. A shot of the top of Services shows the owner's private
iCal URL. It was looked at in `/tmp` and not kept.
