# Kaizen colour values, generated from default/themed/kaizen.yaml.tpl.
#
# This is a map of the keys kaizen's config already uses, not a replacement for
# it. kaizen's config also holds settings that have nothing to do with colour
# (DownloadToWorkingDirectory), and it is edited by hand, so it is updated in
# place: only the keys listed here are touched, and only where they already
# exist. A key kaizen does not have is skipped rather than added -- inventing
# colour entries the application does not read would leave the config looking
# themed while nothing changed, and would bury the real settings in noise.
#
# The dotted paths are matched against the nesting in config.yaml, so the three
# `light`/`dark` pairs are told apart by the key they sit under.
#
# Both variants of each pair are set from the palette. The light/dark split in
# kaizen's config distinguishes a light terminal from a dark one, but the
# terminal is already following the Omarchy theme, so both get the theme's own
# colours and the result is the same either way.

DefaultForeground.light = "{{ foreground }}"
DefaultForeground.dark = "{{ foreground }}"
DefaultUnfocused.light = "{{ muted }}"
DefaultUnfocused.dark = "{{ muted }}"
DefaultActiveTab.light = "{{ accent }}"
DefaultActiveTab.dark = "{{ accent }}"
Tab1.focus.active = "{{ accent }}"
Tab1.focus.inactive = "{{ muted }}"
Tab1.table.selected.foreground = "{{ background }}"
Tab1.table.selected.background = "{{ selection }}"
Tab1.spinner.color = "{{ accent }}"
Tab1.spinner.msg.color = "{{ orange }}"
Tab1.ASCII Art.color = "{{ accent }}"
