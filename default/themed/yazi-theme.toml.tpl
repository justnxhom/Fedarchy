# Yazi theme, generated from the active Omarchy theme.
#
# The sections and keys here are exactly the ones yazi accepts in a theme file,
# which is why this follows yazi's own default theme rather than a list of
# things that look like they ought to be themeable: yazi validates this file
# strictly, and a key that belongs in yazi.toml (a setting such as show_hidden
# or sort_by) makes it refuse to start at all.
#
# Regenerated on every theme change. To change the result, edit this file (or a
# copy in ~/.config/omarchy/themed), not the generated output.

[manager]
cwd = { fg = "{{ accent }}" }

hovered = { fg = "{{ foreground }}", bg = "{{ dark_background }}", bold = true }
preview_hovered = { underline = true }

find_keyword = { fg = "{{ accent }}", bold = true }
find_position = { fg = "{{ muted }}", bg = "reset" }

marker_copied = { fg = "{{ green }}", bg = "{{ green }}" }
marker_cut = { fg = "{{ red }}", bg = "{{ red }}" }
marker_selected = { fg = "{{ accent }}", bg = "{{ accent }}" }

tab_active = { fg = "{{ background }}", bg = "{{ accent }}", bold = true }
tab_inactive = { fg = "{{ muted }}", bg = "{{ darker_background }}" }

border_symbol = "│"
border_style = { fg = "{{ dark_background }}" }

[mode]
normal_main = { fg = "{{ background }}", bg = "{{ accent }}", bold = true }
normal_alt = { fg = "{{ accent }}", bg = "{{ darker_background }}" }

select_main = { fg = "{{ background }}", bg = "{{ green }}", bold = true }
select_alt = { fg = "{{ green }}", bg = "{{ darker_background }}" }

unset_main = { fg = "{{ background }}", bg = "{{ red }}", bold = true }
unset_alt = { fg = "{{ red }}", bg = "{{ darker_background }}" }

[status]
separator_open = ""
separator_close = ""
separator_style = { fg = "{{ dark_background }}", bg = "{{ dark_background }}" }

mode_normal = { fg = "{{ background }}", bg = "{{ accent }}", bold = true }
mode_select = { fg = "{{ background }}", bg = "{{ green }}", bold = true }
mode_unset = { fg = "{{ background }}", bg = "{{ red }}", bold = true }

permissions_t = { fg = "{{ accent }}" }
permissions_r = { fg = "{{ yellow }}" }
permissions_w = { fg = "{{ red }}" }
permissions_x = { fg = "{{ green }}" }
permissions_s = { fg = "{{ muted }}" }

[input]
border = { fg = "{{ accent }}" }
title = {}
value = {}
selected = { reversed = true }

[select]
border = { fg = "{{ accent }}" }
active = { fg = "{{ accent }}", bold = true }
inactive = {}

[tasks]
border = { fg = "{{ accent }}" }
title = {}
hovered = { fg = "{{ accent }}", underline = true }

[which]
mask = { bg = "{{ darker_background }}" }
cand = { fg = "{{ accent }}" }
rest = { fg = "{{ muted }}" }
desc = { fg = "{{ foreground }}" }
separator = " "
separator_style = { fg = "{{ dark_background }}" }

[help]
on = { fg = "{{ accent }}" }
exec = { fg = "{{ green }}" }
desc = { fg = "{{ foreground }}" }
hovered = { bg = "{{ dark_background }}", bold = true }
footer = { fg = "{{ muted }}", bg = "{{ darker_background }}" }

# File rows. Without this section yazi falls back to the colours built into it,
# so the file list keeps its own colours while the rest of the theme follows
# the palette -- which is what makes a theme look only half applied.

[filetype]
rules = [
  { mime = "image/*", fg = "{{ magenta }}" },
  { mime = "{audio,video}/*", fg = "{{ magenta }}" },
  { mime = "application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}", fg = "{{ red }}" },
  { mime = "application/{pdf,doc,rtf}", fg = "{{ cyan }}" },
  { mime = "vfs/{absent,stale}", fg = "{{ muted }}" },
  { url = "*", is = "orphan", bg = "{{ red }}" },
  { url = "*", is = "exec", fg = "{{ green }}" },
  { url = "*", is = "dummy", bg = "{{ red }}" },
  { url = "*/", is = "dummy", bg = "{{ red }}" },
  { url = "*/", fg = "{{ blue }}" },
]

# The per-extension icon list is deliberately not generated. Yazi replaces the
# whole [icon] table rather than merging it with its defaults, so emitting only
# the folder and fallback rules deletes every other icon -- the file icons
# vanish. Theming the icons means shipping yazi's entire table, which is not
# worth it here: the file rows themselves are themed by [filetype] above.
