-- Hyprland border colours.
--
-- Generated from default/themed/hypr-colors.lua.tpl. Edit that template, not
-- this copy: a theme switch rewrites this file.
--
-- This file is dofile'd by ~/.config/hypr/modules/decoration.lua, which reads
-- the returned table:
--
--     local ok, colours = pcall(dofile, ... "hypr-colors.lua")
--     local active = colours and colours.active or "rgb(e0563b)"
--
-- Two things follow from that, and both were got wrong before:
--
--   The table has to be RETURNED. Applying the colours here instead -- calling
--   hl.config from this file -- looks like it works, because the call succeeds,
--   but dofile then hands back nil, the module falls through to its fallback, and
--   the borders stay on a hardcoded colour that belongs to no theme. The switch
--   reports success either way, because nothing failed.
--
--   The colours have to be rgb(r,g,b) strings, which is what the hyprland lua
--   config expects. A #rrggbb literal is not accepted there.

return {
  accent = "{{ accent }}",
  active = "rgb({{ accent_rgb }})",
  inactive = "rgb({{ muted_rgb }})",
}
