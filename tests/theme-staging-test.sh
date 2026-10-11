#!/bin/bash
# A theme installed from a git repo may contribute its palette and its media,
# and nothing else. The apply steps write some theme files straight into the
# user's real configuration -- omarchy-theme-set-vscode merges a theme's
# settings.json into ~/.config/Code/User/settings.json, and the claude and pi
# steps copy the theme's json over the agent's settings -- so a stranger's repo
# staging those would be editing the user's machine, not their colours.
#
# A theme the user wrote themselves, and Omarchy's own bundled themes, are
# staged whole and must stay that way.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

MOCK="$TMP/bin"
mkdir -p "$MOCK"

export HOME="$TMP/home"
export OMARCHY_PATH="$TMP/omarchy"
export XDG_RUNTIME_DIR="$TMP/run"
export XDG_CACHE_HOME="$TMP/cache"
export CALL_LOG="$TMP/calls.log"
mkdir -p "$TMP/omarchy/default" "$HOME/.local/state/omarchy/current" "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME"
cp -r "$ROOT/default/themed" "$TMP/omarchy/default/themed"

# --- mocks -------------------------------------------------------------------

cat >"$MOCK/omarchy-shell" <<'MOCKED'
#!/bin/bash
printf 'shell %s\n' "$*" >>"$CALL_LOG"
exit 0
MOCKED

for command in notification-send hook theme-switcher theme-bg-cache restart-terminal; do
  printf '#!/bin/bash\nexit 0\n' >"$MOCK/omarchy-$command"
done

for command in restart-hyprctl restart-btop restart-opencode restart-helix \
  theme-set-foot theme-set-tmux theme-set-gnome theme-set-pi theme-set-claude \
  theme-set-hermes theme-set-t3code theme-set-browser theme-set-vscode \
  theme-set-obsidian theme-set-keyboard theme-set-templates; do
  printf '#!/bin/bash\nexit 0\n' >"$MOCK/omarchy-$command"
done

chmod +x "$MOCK"/*
export PATH="$MOCK:$ROOT/bin:$PATH"

# --- a repo theme carrying both payloads and its own configuration -----------

REPO_THEME="$HOME/.config/omarchy/themes/repotest"
mkdir -p "$REPO_THEME/.git" "$REPO_THEME/backgrounds/nested" "$REPO_THEME/icons/scalable" \
  "$REPO_THEME/waybar-theme" "$REPO_THEME/config"

# The palette and media: these must survive.
printf 'background = "#111111"\nforeground = "#eeeeee"\naccent = "#88c0d0"\n' \
  >"$REPO_THEME/colors.toml"
printf 'shell=zsh\n' >"$REPO_THEME/shell.toml"
printf '[Icon Theme]\nName=repotest\n' >"$REPO_THEME/icons.theme"
printf '[Chromium]\ncolor=#111111\n' >"$REPO_THEME/chromium.theme"
printf '* { color: #111111; }\n' >"$REPO_THEME/gtk.css"
printf 'png-bytes\n' >"$REPO_THEME/backgrounds/one.png"
printf 'png-bytes-nested\n' >"$REPO_THEME/backgrounds/nested/two.png"
printf 'svg-bytes\n' >"$REPO_THEME/icons/scalable/icon.svg"

# The author's own machine configuration: none of this may be staged.
printf 'general { border_color = #ff0000 }\n' >"$REPO_THEME/hyprland.conf"
printf 'return {}\n' >"$REPO_THEME/hyprland.lua"
printf 'return {}\n' >"$REPO_THEME/neovim.lua"
printf 'return {}\n' >"$REPO_THEME/gum_env.lua"
printf 'exec fish\n' >"$REPO_THEME/config/extra.lua"
printf 'shell fish\n' >"$REPO_THEME/kitty.conf"
printf 'profile: default\n' >"$REPO_THEME/warp.yaml"
printf '{ "editor.fontFamily": "Comic Sans" }\n' >"$REPO_THEME/zed.json"
printf '{ "editor.tabSize": 7 }\n' >"$REPO_THEME/settings.json"
printf '[{"id":"evil.ext"}]\n' >"$REPO_THEME/extensions.json"
printf '{ "theme": "dark" }\n' >"$REPO_THEME/claude.json"
printf '{ "css": "#000" }\n' >"$REPO_THEME/waybar-theme/colors.json"
printf 'set -gx COLOR 1\n' >"$REPO_THEME/colors.fish"
# A capitalised name must not slip past the list.
printf 'shell alacritty\n' >"$REPO_THEME/Alacritty.toml"
# Docs are dropped quietly, so they must not be reported.
printf '# repotest\n' >"$REPO_THEME/README.md"

staged() {
  printf '%s' "$HOME/.local/state/omarchy/current/theme/$1"
}

assert_staged() {
  [[ -f "$(staged "$1")" ]] || fail "a repo theme's $1 was dropped but the apply steps read it"
  pass "a repo theme keeps $1"
}

assert_not_staged() {
  [[ ! -e "$(staged "$1")" ]] || fail "a repo theme's own $1 reached the staged theme"
  pass "a repo theme does not stage $1"
}

output="$(bash "$ROOT/bin/omarchy-theme-set" repotest 2>&1)" || fail "the repo theme was rejected: $output"

assert_staged colors.toml
assert_staged shell.toml
assert_staged icons.theme
assert_staged chromium.theme
assert_staged gtk.css
assert_staged backgrounds/one.png
assert_staged icons/scalable/icon.svg

# Media nested inside a directory is still media: the old walk copied a
# directory's contents with no filter at all.
[[ -f "$(staged backgrounds/nested/two.png)" ]] \
  || fail "media nested in a subdirectory was dropped"
pass "a repo theme keeps media nested in a subdirectory"

assert_not_staged hyprland.conf
assert_not_staged hyprland.lua
assert_not_staged neovim.lua
assert_not_staged gum_env.lua
assert_not_staged config/extra.lua
assert_not_staged kitty.conf
assert_not_staged warp.yaml
assert_not_staged zed.json
assert_not_staged settings.json
assert_not_staged extensions.json
assert_not_staged claude.json
assert_not_staged waybar-theme/colors.json
assert_not_staged colors.fish
assert_not_staged Alacritty.toml
assert_not_staged README.md

# The user is told what was dropped, and that this was deliberate.
[[ $output == *"hyprland.lua"* ]] || fail "the report did not name the dropped files: $output"
[[ $output == *"palette and media"* ]] || fail "the report did not say what a repo theme may contribute: $output"
[[ $output != *"README.md"* ]] || fail "a README was reported as a dropped config file: $output"
pass "the report names the dropped files and stays quiet about docs"

# --- a theme the user wrote is theirs to fill however they like --------------

USER_THEME="$HOME/.config/omarchy/themes/mine"
mkdir -p "$USER_THEME/backgrounds"
printf 'background = "#222222"\nforeground = "#dddddd"\naccent = "#a3be8c"\n' >"$USER_THEME/colors.toml"
printf 'return {}\n' >"$USER_THEME/hyprland.lua"
printf '{ "editor.tabSize": 3 }\n' >"$USER_THEME/settings.json"
printf 'png-bytes\n' >"$USER_THEME/backgrounds/one.png"

output="$(bash "$ROOT/bin/omarchy-theme-set" mine 2>&1)" || fail "a hand-written theme was rejected: $output"

[[ -f "$(staged hyprland.lua)" ]] || fail "a hand-written theme lost its hyprland.lua"
[[ -f "$(staged settings.json)" ]] || fail "a hand-written theme lost its settings.json"
[[ $output != *"palette and media"* ]] || fail "the repo-theme report fired for a hand-written theme: $output"
pass "a hand-written theme is still staged whole"

# --- a bundled theme is untouched too ----------------------------------------

# Omarchy's own themes live in $OMARCHY_PATH/themes and are copied whole, which
# is where the hyprland.lua and gum_env.lua that Hyprland loads at login come
# from. Only a repo the user installed is reduced to colour and media.
BUNDLED="$OMARCHY_PATH/themes/bundled"
mkdir -p "$BUNDLED/backgrounds"
printf 'background = "#333333"
foreground = "#cccccc"
accent = "#b48ead"\n' >"$BUNDLED/colors.toml"
printf 'return {}\n' >"$BUNDLED/hyprland.lua"
printf 'return {}\n' >"$BUNDLED/gum_env.lua"
printf 'png-bytes\n' >"$BUNDLED/backgrounds/one.png"

output="$(bash "$ROOT/bin/omarchy-theme-set" bundled 2>&1)" || fail "a bundled theme was rejected: $output"
[[ -f "$(staged hyprland.lua)" ]] || fail "a bundled theme lost its hyprland.lua"
[[ -f "$(staged gum_env.lua)" ]] || fail "a bundled theme lost its gum_env.lua"
[[ $output != *"palette and media"* ]] || fail "the repo-theme report fired for a bundled theme: $output"
pass "a bundled theme still ships its own payloads"
