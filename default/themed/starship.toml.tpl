# Starship prompt, themed with the active Fedarchy palette.
#
# Generated from default/themed/starship.toml.tpl. Edit that template, not this
# copy: a theme switch rewrites this file.
#
# Two segments and nothing else -- the path, and a character to type at. The
# clock, shell name, user and repository are all deliberately absent; the panel
# shows the time and the terminal already shows the rest, and every extra
# segment is another thing between the path and the cursor.
#
# The path is the theme's own `foreground`, not its `accent`. That is a
# legibility decision rather than a taste one. A theme's foreground is chosen to
# contrast with its background, so it is legible everywhere; the accent is not.
# Hinterlands, for instance, pairs #222222 with an accent of #686868, which is
# 2.9:1 -- readable only just, and unreadable at a glance on a dark background.
# Using foreground instead keeps the prompt legible on every theme, including the
# near-monochrome ones, while still changing with the theme.
#
# The character is a mix of the foreground toward the background: the same hue,
# stepped back so the cursor reads as punctuation rather than as text. The
# 75/25 split is measured, not guessed -- across every installed theme that is
# the point at which the caret stays above the 3:1 that applies to a graphical
# object (it is a glyph, not text) while still reading as secondary to the path.
# Dimmer mixes fall away: at 45% the caret drops to 2.0:1 on the pale themes,
# faint enough to lose against a light background.
#
# Read the operand order in these two mixes carefully. The renderer computes
# A * (1 - N) + B * N, so the percentage weights the SECOND colour, not the
# first: "75% foreground" is `mix background foreground 75%`, not
# `mix foreground background 75%`. The other way round yields 25% foreground and
# a caret too dim to see, which is the whole thing these numbers avoid.
#
# The error colour is the theme's `red` pulled toward the foreground for the
# same reason -- several greyscale themes define `red` as a grey, which would
# make a failed command's prompt character the least visible thing on screen at
# exactly the moment it matters.

add_newline = false
command_timeout = 500

format = "$directory$character"

[directory]
style = "{{ foreground }}"
format = "[$path]($style) "
home_symbol = " ~"
read_only = " 🔒"

[character]
success_symbol = "[❯]({{ mix background foreground 75% }})"
error_symbol = "[❯]({{ mix foreground red 35% }})"
