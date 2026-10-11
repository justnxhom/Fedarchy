# Ekphos theme, generated from default/themed/ekphos.toml.tpl.
#
# Installed as ~/.config/ekphos/themes/omarchy.toml and selected by setting
# `theme = "omarchy"` in ~/.config/ekphos/config.toml. The name is fixed rather
# than per-Omarchy-theme so that switching themes rewrites one file instead of
# leaving a dozen near-identical ones behind for ekphos to choose between.
#
# The section and key names are ekphos's own -- [ui.sidebar], [ui.content] and
# the rest are read directly by it, so a key that does not exist here is not
# themed. The roles are borrowed from the stock themes' structure: headings walk
# the palette from accent through the warm and cool ends, and syntax colours
# follow the same mapping, so headings and code agree.
#
# Text is the foreground colour, not the accent. The accent is for the things
# meant to be noticed: the focused border, the dialog border, the title.

[base]
background = "{{ background }}"
background_secondary = "{{ lighter_background }}"
foreground = "{{ foreground }}"
muted = "{{ muted }}"

[accent]
primary = "{{ accent }}"
secondary = "{{ magenta }}"

[semantic]
error = "{{ red }}"
warning = "{{ yellow }}"
success = "{{ green }}"
info = "{{ cyan }}"

[ui]
border = "{{ mix lighter_background muted 50% }}"
border_focused = "{{ accent }}"
selection = "{{ selection }}"
cursor = "{{ foreground }}"

# Status bar component
[ui.statusbar]
background = "{{ background }}"
foreground = "{{ foreground }}"
brand = "{{ accent }}"
mode = "{{ muted }}"
separator = "{{ mix lighter_background muted 50% }}"

# Dialog/popup component
[ui.dialog]
background = "{{ background }}"
border = "{{ accent }}"
title = "{{ accent }}"
text = "{{ foreground }}"

# Sidebar component
[ui.sidebar]
background = "{{ background }}"
item = "{{ foreground }}"
item_selected = "{{ yellow }}"
folder = "{{ cyan }}"
folder_expanded = "{{ cyan }}"

# Content view component
[ui.content]
background = "{{ background }}"
text = "{{ foreground }}"
heading1 = "{{ accent }}"
heading2 = "{{ green }}"
heading3 = "{{ yellow }}"
heading4 = "{{ magenta }}"
link = "{{ cyan }}"
link_invalid = "{{ red }}"
code = "{{ green }}"
code_background = "{{ lighter_background }}"
blockquote = "{{ muted }}"
list_marker = "{{ magenta }}"

# Outline component
[ui.outline]
background = "{{ background }}"
heading1 = "{{ accent }}"
heading2 = "{{ green }}"
heading3 = "{{ yellow }}"
heading4 = "{{ magenta }}"

# Search component
[ui.search]
background = "{{ lighter_background }}"
border = "{{ accent }}"
input = "{{ foreground }}"
match_highlight = "{{ yellow }}"
match_current = "{{ orange }}"
match_count = "{{ muted }}"

# Editor highlighting component
[ui.editor]
heading1 = "{{ accent }}"
heading2 = "{{ green }}"
heading3 = "{{ yellow }}"
heading4 = "{{ magenta }}"
heading5 = "{{ cyan }}"
heading6 = "{{ muted }}"
code = "{{ green }}"
link = "{{ cyan }}"
blockquote = "{{ muted }}"
list_marker = "{{ magenta }}"
bold = "{{ yellow }}"
italic = "{{ cyan }}"
