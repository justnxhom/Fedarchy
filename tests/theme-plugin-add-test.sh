#!/bin/bash
# `omarchy plugin add` is how people reach for a theme, so it recognises one
# and hands it to the theme installer instead of failing validation over a
# manifest.json the repository was never going to have. The probe that decides
# this must not download the content: a theme's wallpapers are the reason, and
# validating first meant cloning a few hundred megabytes in order to discard
# them.
#
# A real plugin must still install exactly as before.
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
mkdir -p "$TMP/omarchy/default" "$HOME/.local/state/omarchy/current" "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME" \
  "$HOME/.config/omarchy" "$XDG_CACHE_HOME"
cp -r "$ROOT/default/themed" "$TMP/omarchy/default/themed"

# The theme installer is real: the point is that a theme goes through it, with
# the wallpaper options this command forwards.
cat >"$MOCK/omarchy-theme-set" <<'MOCKED'
#!/bin/bash
printf 'theme-set %s\n' "$1" >>"$CALL_LOG"
exit 0
MOCKED

cat >"$MOCK/omarchy-hook" <<'MOCKED'
#!/bin/bash
printf 'hook %s\n' "$*" >>"$CALL_LOG"
exit 0
MOCKED

cat >"$MOCK/omarchy-shell" <<'MOCKED'
#!/bin/bash
printf 'shell %s\n' "$*" >>"$CALL_LOG"
exit 0
MOCKED

cat >"$MOCK/omarchy-notification-send" <<'MOCKED'
#!/bin/bash
printf 'notification %s\n' "$*" >>"$CALL_LOG"
exit 0
MOCKED

chmod +x "$MOCK"/*
export PATH="$MOCK:$ROOT/bin:$PATH"

# --- a theme repository -------------------------------------------------------

make_theme_repo() {
  local repo="$1"
  mkdir -p "$repo/backgrounds"
  printf 'background = "#101010"\nforeground = "#f0f0f0"\naccent = "#7ab7d4"\n' >"$repo/colors.toml"
  printf 'return {}\n' >"$repo/hyprland.lua"
  local index
  for index in 0 1 2 3 4 5; do
    head -c $(( (index + 1) * 4096 )) /dev/zero | tr '\0' 'x' \
      >"$repo/backgrounds/$index-scene.png"
  done
  git -C "$repo" init --quiet --initial-branch=master
  git -C "$repo" -c user.email=t@e -c user.name=t add -A
  git -C "$repo" -c user.email=t@e -c user.name=t commit --quiet -m theme
}

make_theme_repo "$TMP/repos/omarchy-scenic-theme"
THEME_URL="file://$TMP/repos/omarchy-scenic-theme"

: >"$CALL_LOG"
output="$(bash "$ROOT/bin/omarchy-plugin-add" --yes "$THEME_URL" 2>&1)" \
  || fail "adding a theme through plugin add failed: $output"

[[ $output == *"That is a theme, not a shell plugin"* ]] \
  || fail "the theme was not recognised: $output"
[[ -d "$HOME/.config/omarchy/themes/scenic" ]] || fail "the theme was not installed"
[[ -d "$HOME/.config/omarchy/plugins/scenic" ]] && fail "the theme was installed as a plugin"
pass "a theme repository is installed as a theme, not as a plugin"

count=$(find "$HOME/.config/omarchy/themes/scenic/backgrounds" -maxdepth 1 -type f | wc -l)
[[ $count -eq 4 ]] || fail "the default wallpaper cap did not apply through plugin add: $count"
pass "the wallpaper cap still applies when a theme arrives through plugin add"

[[ -e "$HOME/.config/omarchy/themes/scenic/hyprland.lua" ]] \
  || fail "the theme was not staged with its palette"
[[ -e "$HOME/.local/state/omarchy/current/theme/hyprland.lua" ]] \
  && fail "the repo's own hyprland.lua was applied"
pass "the theme's own configuration is still not applied"

# The wallpaper options are forwarded, so one command covers both entry points.
output="$(bash "$ROOT/bin/omarchy-plugin-add" --yes -n 2 "$THEME_URL" 2>&1)" \
  || fail "--wallpapers was not forwarded: $output"
count=$(find "$HOME/.config/omarchy/themes/scenic/backgrounds" -maxdepth 1 -type f | wc -l)
[[ $count -eq 2 ]] || fail "--wallpapers was not forwarded to the theme installer: $count"
pass "--wallpapers is forwarded to the theme installer"

output="$(bash "$ROOT/bin/omarchy-plugin-add" --yes -w 4-scene.png "$THEME_URL" 2>&1)" \
  || fail "--wallpaper was not forwarded: $output"
names=$(ls "$HOME/.config/omarchy/themes/scenic/backgrounds" | tr '\n' ' ')
[[ $names == "4-scene.png " ]] || fail "--wallpaper was not forwarded: $names"
pass "--wallpaper is forwarded to the theme installer"

# A rejected option is refused before anything is cloned.
output="$(bash "$ROOT/bin/omarchy-plugin-add" --yes -n abc "$THEME_URL" 2>&1)" && \
  fail "a bad wallpaper count was accepted"
[[ $output == *"--wallpapers needs a number"* ]] || fail "the bad count was not reported: $output"
pass "a bad --wallpapers value is refused"

# Nothing is left half-written by any of the above.
strays=$(find "$HOME/.config/omarchy/plugins" "$HOME/.config/omarchy/themes" \
  -maxdepth 1 \( -name '.probe.tmp.*' -o -name '.add.tmp.*' -o -name '.incoming-*' \) | wc -l)
[[ $strays -eq 0 ]] || fail "$strays staged clone(s) were left behind"
pass "no staged clone is left behind"

# --- a real plugin still installs as a plugin --------------------------------

PLUGIN="$TMP/repos/omarchy-widget-plugin"
mkdir -p "$PLUGIN"
cat >"$PLUGIN/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.widget",
  "name": "Widget",
  "version": "1.0.0",
  "kinds": ["service"],
  "entryPoints": { "service": "Service.qml" }
}
JSON
printf 'import QtQuick\nItem {}\n' >"$PLUGIN/Service.qml"
git -C "$PLUGIN" init --quiet --initial-branch=master
git -C "$PLUGIN" -c user.email=t@e -c user.name=t add -A
git -C "$PLUGIN" -c user.email=t@e -c user.name=t commit --quiet -m plugin

: >"$CALL_LOG"
output="$(bash "$ROOT/bin/omarchy-plugin-add" --yes "file://$PLUGIN" 2>&1)" \
  || fail "a real plugin no longer installs: $output"
[[ $output != *"That is a theme"* ]] || fail "a plugin was mistaken for a theme: $output"
[[ -d "$HOME/.config/omarchy/plugins/acme.widget" ]] || fail "the plugin was not installed"
[[ -f "$HOME/.config/omarchy/plugins/acme.widget/manifest.json" ]] || fail "the plugin is incomplete"
[[ ! -d "$HOME/.config/omarchy/themes/widget" ]] || fail "a plugin was also installed as a theme"
pass "a real plugin still installs as a plugin"

# --- a repository that is neither is still refused ---------------------------

PLAIN="$TMP/repos/omarchy-plain-repo"
mkdir -p "$PLAIN"
printf 'nothing to see\n' >"$PLAIN/README.md"
git -C "$PLAIN" init --quiet --initial-branch=master
git -C "$PLAIN" -c user.email=t@e -c user.name=t add -A
git -C "$PLAIN" -c user.email=t@e -c user.name=t commit --quiet -m plain

output="$(bash "$ROOT/bin/omarchy-plugin-add" --yes "file://$PLAIN" 2>&1)" && \
  fail "a repository with no manifest and no palette was accepted"
[[ $output == *"refusing to add"* ]] || fail "the refusal was not reported: $output"
pass "a repository that is neither a plugin nor a theme is still refused"
