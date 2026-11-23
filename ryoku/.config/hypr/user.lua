-- --- hypr/user.lua --------------------------------------------------------
-- Your Hyprland overrides, in Ryoku's `hl` Lua API. Loaded LAST, so anything
-- here wins over Ryoku's defaults and over Ryoku Settings. Updates never touch
-- it. Reach for it only for raw config the GUI does not expose.
--
-- --- who owns what --------------------------------------------------------
--   Ryoku defaults   the base modules           replaced by updates   don't edit
--   Ryoku Settings   settings.lua, rebinds.lua  the GUI writes these  edit in-app
--   you              this file (edit it here); whole-file forks in user_edits  yours
--
-- --- take over a whole module ---------------------------------------------
-- Copy it into the overlay at the same path and edit there, e.g.
--   ~/.config/ryoku/user_edits/hypr/modules/binds.lua
-- You then own that file: `ryoku doctor` warns when an update changes the
-- original, and `ryoku reset hypr/modules/binds.lua` hands it back.
--
-- --- examples -------------------------------------------------------------
-- hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("kitty"))
-- hl.window_rule({ name = "float-mpv", match = { class = "mpv" }, float = true })
-- hl.config({ general = { border_size = 3 } })

-- tuber (avatar para OBS): sigue animándose aunque su ventana esté en otro espacio.
hl.window_rule({ name = "tuber", match = { class = "^miniquad-application$", title = "^tuber$" }, render_unfocused = true })
hl.config({ misc = { render_unfocused_fps = 60 } })

-- Alt + N escribe ñ (Alt + Shift + N, Ñ). La opción xkb enie:code230 (~/.config/xkb)
-- pone ñ/Ñ en un código libre, y send_shortcut la manda sin la Alt presionada,
-- que haría que la ventana descarte el carácter. Reemplaza las opciones del Hub.
hl.config({ input = { kb_options = "enie:code230" } })
hl.bind("ALT + N", hl.dsp.send_shortcut({ mods = "", key = "code:230" }))
hl.bind("ALT + SHIFT + N", hl.dsp.send_shortcut({ mods = "SHIFT", key = "code:230" }))
