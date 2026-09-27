# settings-BackgroundConfig — brief

**Purpose.** Everything drawn on the wallpaper plane: parallax, wallpaper behaviour and
transitions, shape mask, subject depth, wallpaper effects, weather effects, fluted glass,
each targetable at the desktop or the lock screen.

**Primary action.** Pick a wallpaper effect from its live preview cards.

**Hierarchy.** **Parallax** (vertical, the two dependencies, zoom). Then **Wallpaper**:
Animate wallpaper changes and its Transition subsection, then the drop and right-click
switches. "Animate wallpaper changes" and the transition style used to sit under Parallax,
which they have nothing to do with. The targeted sections follow unchanged: shape, depth,
effects, weather, glass.

**Reference.** Android 16 Wallpaper & style: the picture first, then what moves it, then
effects.

**Interaction.**
- The Vertical switch rewrites a Hyprland animation and reloads the compositor. It did so
  from a change handler that also fires on build, and it is gated on a real change now.
- The shape mask's recommended colours are `RippleButton` circles with all four states, a
  tooltip naming the token, and a check on the one in use. They were bare `Rectangle`s over
  a `MouseArea`, with a literal radius and no selected state.
- Disabled is 0.4, once. The transition combo and spin box, the weather intensity slider
  and the whole Subject depth section each added their own `opacity: enabled ? 1 : 0.4`
  over widgets that already dim, which came out at 0.16.

**Edge states.** A video wallpaper greys the transition controls and says why (unchanged).
A lock screen that mirrors the desktop collapses its targeted controls (unchanged).

**Cost.** The 18 effect preview cards are the page's cost; see
`settings-WallpaperEffectPreview`.

**Delete.** The four extra opacity layers, and the off-grid `spacing: 3` in `EffectCard`.

**Out of scope.** The search index does not see the targeted sections: they are custom
components, and the static parser only reads `ContentSection` blocks.
