# fzf colours.
#
# Generated from default/themed/fzf.zsh.tpl. Edit that template, not this copy: a
# theme switch rewrites this file.

export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
  --color=bg+:{{ lighter_background }},bg:{{ background }} \
  --color=fg+:{{ foreground }},fg:{{ muted }} \
  --color=hl:{{ bright_yellow }},hl+:{{ bright_yellow }} \
  --color=info:{{ accent }},prompt:{{ accent }} \
  --color=pointer:{{ bright_red }},marker:{{ bright_green }} \
  --color=spinner:{{ bright_green }},border:{{ muted }}"
