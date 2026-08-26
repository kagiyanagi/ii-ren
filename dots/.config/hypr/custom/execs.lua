hl.on("hyprland.start", function()
    -- Fix gaps_out (Lua wrapper bug workaround)
    -- hl.exec_cmd("hyprctl eval \"hl.config({ general = { gaps_out = 8 } })\"")

    -- Start apps minimized to tray
    -- Delay so quickshell's tray host / StatusNotifierWatcher is up first,
    -- otherwise the tray icons fail to register (no icon = looks like it didn't start).
    hl.exec_cmd("sleep 6 && /home/ren/.appimages/beeper.appimage")
    hl.exec_cmd("sleep 6 && AyuGram -startintray")
    hl.exec_cmd("hyprctl setcursor macOS-White 28")
    hl.exec_cmd("sleep 6 && flatpak run --branch=master --arch=x86_64 --command=postcard --file-forwarding in.gxanshu.postcard --hidden")
end)
