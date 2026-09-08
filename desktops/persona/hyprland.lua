-- Hyprland 0.56 Lua configuration. Home Manager supplies session lifecycle hooks.
hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@120", position = "0x0", scale = 2 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.env("XCURSOR_THEME", "@cursorTheme@")
hl.env("XCURSOR_SIZE", "@cursorSize@")
hl.env("HYPRCURSOR_THEME", "@cursorTheme@")
hl.env("HYPRCURSOR_SIZE", "@cursorSize@")

hl.on("hyprland.start", function()
    hl.exec_cmd("@persona@")
    hl.exec_cmd("fcitx5")
end)

hl.config({
    input = { kb_layout = "us", follow_mouse = 1 },
    general = {
        gaps_in = 8,
        gaps_out = 16,
        border_size = 2,
        layout = "dwindle",
        col = { active_border = "rgb(7fc8ff)", inactive_border = "rgb(244568)" },
    },
    decoration = {
        rounding = 12,
        active_opacity = 1.0,
        inactive_opacity = 0.95,
        blur = { enabled = true, size = 3, passes = 2 },
    },
    dwindle = { preserve_split = true },
    animations = { enabled = true },
    misc = { disable_hyprland_logo = true, force_default_wallpaper = 0 },
})

hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))
hl.bind("SUPER + E", hl.dsp.exec_cmd("thunar"))
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("@persona@ ipc call searchapp toggle"))
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

for _, direction in ipairs({ "left", "right", "up", "down" }) do
    hl.bind("SUPER + " .. direction, hl.dsp.focus({ direction = direction }))
    hl.bind("SUPER + CTRL + " .. direction, hl.dsp.window.move({ direction = direction }))
end
for i = 1, 9 do
    hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + CTRL + " .. i, hl.dsp.window.move({ workspace = i }))
end
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 10%+"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 10%-"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))

-- External HDMI displays generally have no /sys/class/backlight device.
local backlights = io.popen("brightnessctl --class=backlight --list 2>/dev/null")
if backlights then
    local devices = backlights:read("*a")
    backlights:close()
    if devices:find("Device '") then
        hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl --class=backlight set +10%"), { repeating = true })
        hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl --class=backlight set 10%-"), { repeating = true })
    end
end
