# zsh prompt colours.
#
# Generated from default/themed/zsh-theme.zsh.tpl. Edit that template, not this
# copy: a theme switch rewrites this file.
#
# PROMPT is set here too, but Starship owns the left-hand prompt and is
# initialised after this file, so what survives is RPROMPT -- the time and
# user@host on the right. The left-hand colours are kept consistent with the
# Starship palette for the case where Starship is not loaded.

PROMPT='%F{ {{ accent }} }%~%f %F{ {{ foreground }} }>%f '
RPROMPT='%F{ {{ green }} }%D{%%H:%%M}%f %F{ {{ orange }} }%n@%m%f'

ZSH_THEME_GIT_PROMPT_PREFIX="%F{ {{ green }} }"
ZSH_THEME_GIT_PROMPT_SUFFIX="%f"
ZSH_THEME_GIT_PROMPT_DIRTY="%F{ {{ bright_red }} }✗%f"
ZSH_THEME_GIT_PROMPT_CLEAN="%F{ {{ bright_green }} }✓%f"
