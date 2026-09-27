# settings-EasterEggWindow — brief

**Purpose.** The Android version easter egg: a starfield that warps while the logo is
held, then opens the Landroid web game after three seconds.

**Primary action.** Press and hold the logo.

**Hierarchy.** The logo, centred, over a full-window starfield.

**Reference.** AOSP `PlatLogoActivity.java` (Android 16). The header comment cites every
phase. The literal durations are those transcribed numbers, and they stay. This is the
one surface where an AOSP citation beats `Appearance` tokens, because the point is to
reproduce that activity.

**Interaction.** Pop-in on open. Pressing bounces the logo; holding past ~500ms wobbles
and shakes it and warps the stars; releasing cancels. Escape closes. The window has no
exit animation of its own, because Hyprland animates the close.

**Edge states.** Reopening resets every phase (`onVisibleChanged`).

**Cost.** One `Canvas`, repainted every frame while the window is open, and nothing while
it is closed. It was ticked by a 16ms `Timer`. It is a `FrameAnimation` now, so the tick
follows vsync and `frameTime` rather than beating against it.

**Delete.** The `#3DDC84` hex goes to `m3primaryFixedDim`, which is tone 80 in both themes
and stays legible on black. `lastTick` goes too, since `frameTime` replaces it.

**Out of scope.** How About opens it (three presses on the egg, `settings-About`).
