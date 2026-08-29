-- MONITOR CONFIG
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "1"
})

hl.gesture({
    fingers = 3,
    direction = "swipe",
    action = "move"
})
hl.gesture({
    fingers = 3,
    direction = "pinch",
    action = "fullscreen"
})
hl.gesture({
    fingers = 4,
    direction = "horizontal",
    action = "workspace"
})
hl.gesture({
    fingers = 4,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end
})
hl.gesture({
    fingers = 4,
    direction = "down",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end
})

hl.config({
    gestures = {
        workspace_swipe_distance = 700,
        workspace_swipe_cancel_ratio = 0.2,
        workspace_swipe_min_speed_to_force = 5,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true
    },
    general = {
        -- Gaps and border
        gaps_in = 4,
        gaps_out = 5,
        gaps_workspaces = 50,

        border_size = 1,

        col = {
            active_border = "rgba(0DB7D455)",
            inactive_border = "rgba(31313600)"
        },
        resize_on_border = true,

        no_focus_fallback = true,
        allow_tearing = true, -- This just allows the `immediate` window rule to work
        snap = {
            enabled = true,
            window_gap = 4,
            monitor_gap = 5,
            respect_gaps = true
        }
    },
    decoration = {
        -- 2 = circle, higher = squircle, 4 = very obvious squircle
        -- Fuck clearly visible squircles. 100% Apple brainrot.
        rounding_power = 2.5,
        rounding = 18,

        blur = {
            enabled = true,
            xray = true,
            special = false,
            new_optimizations = true,
            size = 10,
            passes = 3,
            brightness = 1,
            noise = 0.05,
            contrast = 0.89,
            vibrancy = 0.5,
            vibrancy_darkness = 0.5,
            popups = false,
            popups_ignorealpha = 0.6,
            input_methods = true,
            input_methods_ignorealpha = 0.8
        },
        shadow = {
            enabled = true,
            range = 20,
            offset = {0, 2},
            render_power = 10,
            color = "rgba(00000020)"

        },
        -- Dim
        dim_inactive = true,
        dim_strength = 0.05,
        dim_special = 0.2
    },
    animations = {
        enabled = true
    },
    dwindle = {
        preserve_split = true,
        smart_split = false,
        smart_resizing = false
        -- precise_mouse_move = true,
    },
})
-- Curves
-- Material 3 Expressive motion physics (Android 16). These are native Hyprland springs,
-- so `speed` is ignored for them -- duration falls out of the physics.
--   stiffness = md.sys.motion.spring.<speed>.<kind>.stiffness (verbatim from AOSP)
--   dampening = 2 * dampingRatio * sqrt(stiffness * mass)
-- Spatial springs (position/size/scale) overshoot; effects springs (opacity/color) never do.
hl.curve("m3FastSpatial",    { type = "spring", mass = 1, stiffness = 800,  dampening = 33.9411 })  -- z 0.6, ~420ms, 9.5% overshoot
hl.curve("m3DefaultSpatial", { type = "spring", mass = 1, stiffness = 380,  dampening = 31.1897 })  -- z 0.8, ~530ms, 1.5% overshoot
hl.curve("m3SlowSpatial",    { type = "spring", mass = 1, stiffness = 200,  dampening = 22.6274 })  -- z 0.8, ~720ms, 1.5% overshoot
hl.curve("m3FastEffects",    { type = "spring", mass = 1, stiffness = 3800, dampening = 123.2883 }) -- z 1.0, ~220ms
hl.curve("m3DefaultEffects", { type = "spring", mass = 1, stiffness = 1600, dampening = 80 })       -- z 1.0, ~330ms
hl.curve("m3SlowEffects",    { type = "spring", mass = 1, stiffness = 800,  dampening = 56.5685 })  -- z 1.0, ~450ms
-- Kept for `hyprctl keyword animation` callers (Lock.qml, hyprset), which can only name a bezier.
hl.curve("menu_decel", {
    type = "bezier",
    points = {{0.1, 1}, {0, 1}}
})
-- Configs
-- Enters move on spatial springs (scale/slide with overshoot), exits and every fade on
-- effects springs (critically damped) -- same split Android 16 uses.
-- windows
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 3,
    spring = "m3DefaultSpatial",
    style = "popin 80%"
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 3,
    spring = "m3DefaultEffects"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2,
    spring = "m3DefaultEffects",
    style = "popin 90%"
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 2,
    spring = "m3FastEffects"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3,
    spring = "m3DefaultSpatial",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 10,
    spring = "m3SlowEffects"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 2.7,
    spring = "m3DefaultSpatial",
    style = "popin 93%"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 2.4,
    spring = "m3DefaultEffects",
    style = "popin 94%"
})
-- fade
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 0.5,
    spring = "m3DefaultEffects"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 2.7,
    spring = "m3DefaultEffects"
})
-- workspaces
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 7,
    spring = "m3DefaultSpatial",
    style = "slide"
})
-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 2.8,
    spring = "m3DefaultSpatial",
    style = "slidevert"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 1.2,
    spring = "m3FastEffects",
    style = "slidevert"
})
-- zoom
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 3,
    spring = "m3DefaultSpatial"
})

hl.config({
    input = {
        kb_layout = "us",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,

        follow_mouse = 1,
        off_window_axis_events = 2,

        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            clickfinger_behavior = true,
            scroll_factor = 0.7
        }
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        vrr = 0,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        enable_swallow = false,
        swallow_regex = "(foot|kitty|allacritty|Alacritty)",
        on_focus_under_fullscreen = 2,
        allow_session_lock_restore = true,
        session_lock_xray = true,
        initial_workspace_tracking = false,
        focus_on_activate = true
    },

    binds = {
        scroll_event_delay = 0,
        hide_special_on_workspace_change = true
    },

    cursor = {
        zoom_factor = 1,
        zoom_rigid = false,
        zoom_disable_aa = true,
        hotspot_padding = 1
    },

    xwayland = {
        force_zero_scaling = true
    }
})
