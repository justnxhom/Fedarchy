#!/bin/bash
# A theme repo is mostly wallpapers, and installing it whole can pull a few
# hundred megabytes to apply one palette. omarchy-theme-install clones without
# blob content, picks the wallpapers to keep from the tree alone, and fetches
# only those, so the rest of the repository is never downloaded.
#
# Everything here runs against a local repository, so the clone, the sparse
# checkout, the swap and the failure paths are exercised without a network.
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

# The apply step is exercised too, because the install is only useful if the
# theme it stages is one the theme set can actually use.
cat >"$MOCK/omarchy-theme-set" <<'MOCKED'
#!/bin/bash
name="$1"
theme="$HOME/.config/omarchy/themes/$name"
staged="$HOME/.local/state/omarchy/current/theme"
rm -rf "$staged"
mkdir -p "$staged"
for entry in "$theme"/*; do
  name_entry=$(basename "$entry")
  case "$name_entry" in
    colors.toml | shell.toml | icons.theme | chromium.theme) cp "$entry" "$staged/$name_entry" ;;
    backgrounds)
      mkdir -p "$staged/backgrounds"
      for bg in "$entry"/*; do cp "$bg" "$staged/backgrounds/$(basename "$bg")"; done
      ;;
    *.css | *.png | *.jpg | *.webp) cp "$entry" "$staged/$name_entry" ;;
  esac
done
printf 'theme-set %s\n' "$name" >>"$CALL_LOG"
exit 0
MOCKED

cat >"$MOCK/omarchy-git-url-check" <<'MOCKED'
#!/bin/bash
exit 0
MOCKED

chmod +x "$MOCK"/*
export PATH="$MOCK:$ROOT/bin:$PATH"

# --- a repo with a palette and eight wallpapers ------------------------------

make_repo() {
  local repo="$1" name="$2"
  mkdir -p "$repo/backgrounds/nested"
  printf 'background = "#101010"\nforeground = "#f0f0f0"\naccent = "#7ab7d4"\n' \
    >"$repo/colors.toml"
  printf 'shell=zsh\n' >"$repo/shell.toml"
  printf '[Icon Theme]\nName=%s\n' "$name" >"$repo/icons.theme"
  printf '* { color: #101010; }\n' >"$repo/gtk.css"

  local index
  for index in 0 1 2 3 4 5 6 7; do
    # Distinct sizes so "did the big ones get skipped" is observable.
    head -c $(( (index + 1) * 4096 )) /dev/zero | tr '\0' 'x' \
      >"$repo/backgrounds/$index-scene.png"
  done
  # Not something the theme set or the picker looks at.
  head -c 2048 /dev/zero | tr '\0' 'x' >"$repo/backgrounds/nested/buried.png"

  # The author's own machine configuration, which must never be applied.
  printf 'general { border_color = #ff0000 }\n' >"$repo/hyprland.conf"
  printf 'return {}\n' >"$repo/hyprland.lua"
  printf 'return {}\n' >"$repo/neovim.lua"
  printf 'shell fish\n' >"$repo/kitty.conf"
  printf '{ "editor.tabSize": 7 }\n' >"$repo/settings.json"

  git -C "$repo" init --quiet --initial-branch=master
  git -C "$repo" -c user.email=t@e -c user.name=t add -A
  git -C "$repo" -c user.email=t@e -c user.name=t commit --quiet -m "theme"
}

make_repo "$TMP/repos/omarchy-scenic-theme" scenic
REPO_URL="file://$TMP/repos/omarchy-scenic-theme"

# --- the default keeps four wallpapers ---------------------------------------

output="$(bash "$ROOT/bin/omarchy-theme-install" "$REPO_URL" 2>&1)" || fail "install failed: $output"

THEME="$HOME/.config/omarchy/themes/scenic"
[[ -d $THEME ]] || fail "the theme was not installed"
[[ $output == *"Keeping 4 of 8"* ]] || fail "the cap was not reported: $output"

count=$(find "$THEME/backgrounds" -maxdepth 1 -type f | wc -l)
[[ $count -eq 4 ]] || fail "expected 4 wallpapers on disk, found $count"
pass "the default keeps four wallpapers"

names=$(ls "$THEME/backgrounds" | tr '\n' ' ')
[[ $names == "0-scene.png 1-scene.png 2-scene.png 3-scene.png "* ]] \
  || fail "the wrong wallpapers were kept: $names"
pass "the first four in name order are the ones kept"

[[ ! -e "$THEME/backgrounds/4-scene.png" ]] || fail "a skipped wallpaper was fetched anyway"
[[ ! -e "$THEME/backgrounds/nested/buried.png" ]] || fail "a nested wallpaper was fetched"
pass "the wallpapers that were not chosen were never fetched"

# The palette still has to be there, or none of this is a theme.
[[ -f "$THEME/colors.toml" ]] || fail "colors.toml is missing from the install"
[[ -f "$THEME/shell.toml" ]] || fail "shell.toml is missing from the install"
pass "the palette and the other payloads are installed"

# The repository is left usable, so omarchy-theme-update still works on it.
git -C "$THEME" rev-parse --verify HEAD >/dev/null 2>&1 || fail "the install is not a git checkout"
pass "the install is a real repository, so updates still work"

# --- naming the wallpapers ----------------------------------------------------

output="$(bash "$ROOT/bin/omarchy-theme-install" -w 7-scene.png -w 5-scene.png "$REPO_URL" 2>&1)" \
  || fail "naming wallpapers failed: $output"
names=$(ls "$THEME/backgrounds" | tr '\n' ' ')
[[ $names == "5-scene.png 7-scene.png " ]] || fail "named wallpapers were not honoured: $names"
pass "--wallpaper keeps exactly the wallpapers it is given"

# --- a different count -------------------------------------------------------

output="$(bash "$ROOT/bin/omarchy-theme-install" --wallpapers 2 "$REPO_URL" 2>&1)" \
  || fail "--wallpapers failed: $output"
count=$(find "$THEME/backgrounds" -maxdepth 1 -type f | wc -l)
[[ $count -eq 2 ]] || fail "expected 2 wallpapers, found $count"
pass "--wallpapers N keeps N"

# --- the escape hatch --------------------------------------------------------

output="$(bash "$ROOT/bin/omarchy-theme-install" --all-wallpapers "$REPO_URL" 2>&1)" \
  || fail "--all-wallpapers failed: $output"
count=$(find "$THEME/backgrounds" -maxdepth 1 -type f | wc -l)
[[ $count -eq 8 ]] || fail "expected all 8 wallpapers, found $count"
pass "--all-wallpapers keeps the whole set"

# --- failures leave an existing install untouched -----------------------------

bash "$ROOT/bin/omarchy-theme-install" -n 4 "$REPO_URL" >/dev/null 2>&1
good_colors=$(cat "$THEME/colors.toml")

output="$(bash "$ROOT/bin/omarchy-theme-install" -w no-such-wallpaper.png "$REPO_URL" 2>&1)" && \
  fail "a wallpaper that does not exist was accepted"
[[ $output == *"no wallpaper named"* ]] || fail "the missing wallpaper was not reported: $output"
[[ -f "$THEME/colors.toml" ]] || fail "a failed install removed the existing theme"
[[ $(cat "$THEME/colors.toml") == "$good_colors" ]] || fail "a failed install altered the existing theme"
count=$(find "$THEME/backgrounds" -maxdepth 1 -type f | wc -l)
[[ $count -eq 4 ]] || fail "a failed install changed the wallpapers on disk"
pass "a failed install leaves the existing theme exactly as it was"

output="$(bash "$ROOT/bin/omarchy-theme-install" "file://$TMP/repos/does-not-exist" 2>&1)" && \
  fail "an unreachable repository was accepted"
[[ $output == *"could not reach or clone"* ]] || fail "an unreachable repository was not reported: $output"
[[ -f "$THEME/colors.toml" ]] || fail "an unreachable repository removed the existing theme"
pass "an unreachable repository is reported and changes nothing"

# A repo with no palette cannot be applied, and must not be swapped in.
make_repo "$TMP/repos/omarchy-paletteless-theme" paletteless
rm "$TMP/repos/omarchy-paletteless-theme/colors.toml"
rm "$TMP/repos/omarchy-paletteless-theme/alacritty.toml" 2>/dev/null || true
git -C "$TMP/repos/omarchy-paletteless-theme" -c user.email=t@e -c user.name=t commit --quiet -am "no palette"
output="$(bash "$ROOT/bin/omarchy-theme-install" "file://$TMP/repos/omarchy-paletteless-theme" 2>&1)" && \
  fail "a theme with no palette was accepted"
[[ $output == *"neither colors.toml nor alacritty.toml"* ]] || fail "the missing palette was not reported: $output"
[[ -d "$HOME/.config/omarchy/themes/paletteless" ]] && fail "a theme with no palette was installed anyway"
pass "a repo with no palette is refused and not installed"

# A legacy repo that only has the terminal config still yields a palette.
make_repo "$TMP/repos/omarchy-legacy-theme" legacy
rm "$TMP/repos/omarchy-legacy-theme/colors.toml"
printf 'background = "#202020"\nforeground = "#e0e0e0"\naccent = "#8fb573"\n' \
  >"$TMP/repos/omarchy-legacy-theme/alacritty.toml"
git -C "$TMP/repos/omarchy-legacy-theme" -c user.email=t@e -c user.name=t add -A
git -C "$TMP/repos/omarchy-legacy-theme" -c user.email=t@e -c user.name=t commit --quiet -m "legacy"
output="$(bash "$ROOT/bin/omarchy-theme-install" "file://$TMP/repos/omarchy-legacy-theme" 2>&1)" \
  || fail "a legacy palette-only repo was refused: $output"
[[ -f "$HOME/.config/omarchy/themes/legacy/alacritty.toml" ]] || fail "the legacy palette was not installed"
pass "a repo with only alacritty.toml is still installable"

# Nothing half-written is left in the themes directory.
strays=$(find "$HOME/.config/omarchy/themes" -maxdepth 1 -name '.incoming-*' | wc -l)
[[ $strays -eq 0 ]] || fail "$strays staged clone(s) were left behind"
pass "no staged clone is left behind"

# --- the install actually applies the theme ----------------------------------

: >"$CALL_LOG"
bash "$ROOT/bin/omarchy-theme-install" "$REPO_URL" >/dev/null 2>&1
grep -q "theme-set scenic" "$CALL_LOG" || fail "the install did not apply the theme"
[[ -f "$HOME/.local/state/omarchy/current/theme/colors.toml" ]] \
  || fail "the applied theme has no palette"
[[ -e "$HOME/.local/state/omarchy/current/theme/hyprland.lua" ]] \
  && fail "the repo's own hyprland.lua was applied"
[[ -e "$HOME/.local/state/omarchy/current/theme/settings.json" ]] \
  && fail "the repo's own settings.json was applied"
pass "the install applies the theme without the repo's own configuration"
