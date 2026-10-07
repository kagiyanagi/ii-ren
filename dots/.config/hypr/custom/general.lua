hl.window_rule({
    match = {
        class = ".*"
    },
    no_blur = false
})


hl.layer_rule({
    match = {
        namespace = ".*"
    },
    blur = true,
    ignore_alpha = 0.2,
    xray = false
})
