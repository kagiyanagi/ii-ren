-- Performance tuning (2026-08-13)
-- Render-path only. Deliberately does NOT touch decoration, animations, blur,
-- shadow, dim, rounding or opacity -- those are left exactly as the theme
-- (and quickshell's shellOverrides) define them.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1
})
hl.config({
    input = {touchpad = {disable_while_typing = false}},
    decoration = {
        blur = {enabled = false},
        shadow = {range = 40}
    },
    render = {
        -- Time the render to the actual vblank deadline instead of drawing as
        -- early as possible. Main anti-stutter / lower-latency lever on this
        -- fixed-refresh 60Hz panel. Changes nothing about how anything looks.
        new_render_scheduling = true,

        -- Let a fullscreen opaque surface go straight to the display
        -- controller, skipping composition (video, games, fullscreen browser).
        -- Was blocked by "user settings" before this.
        direct_scanout = 1,
    },
})

-- Keep the mouse cursor visible when driving the desktop by touch (2026-08-13)
-- Hyprland hides the pointer as soon as input comes from a touch device
-- (cursor:hide_on_touch defaults to true). That is right for a real touchscreen,
-- but wrong when the "touch" is a Moonlight client streaming this desktop to a
-- tablet -- there you still want to see where the pointer is.
--
-- NOT setting cursor:no_hardware_cursors here on purpose: forcing a software
-- cursor composites it into the framebuffer (which is what makes it show up in a
-- KMS screen capture), but it also defeats the direct_scanout = 1 set above.
-- Only add it if the cursor turns out to be missing from the stream itself.
hl.config({
    cursor = {
        hide_on_touch = false,
    },
})
