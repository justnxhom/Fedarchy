#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

MOCK="$TMP/bin"
mkdir -p "$MOCK"

# --- fixture themes -------------------------------------------------------

THEMES="$TMP/omarchy/themes"
make_theme() {
  local name="$1"
  local body="$2"
  mkdir -p "$THEMES/$name/backgrounds"
  printf '%s\n' "$body" >"$THEMES/$name/colors.toml"
  printf 'shell=zsh\n' >"$THEMES/$name/shell.toml"
  printf 'image-bytes-%s\n' "$name" >"$THEMES/$name/backgrounds/one.png"
}

make_theme tokyo-night 'background = "#1e1e2e"
foreground = "#cdd6f4"
accent = "#89b4fa"'
make_theme nord 'background = "#2e3440"
foreground = "#eceff4"
accent = "#88c0d0"'
make_theme no-palette 'not a palette at all'
: >"$THEMES/no-palette/colors.toml"

cp -r "$THEMES" "$TMP/omarchy-themes-user"
rm -rf "$THEMES/no-palette"
mkdir -p "$THEMES/no-palette/backgrounds"
: >"$THEMES/no-palette/colors.toml"

export HOME="$TMP/home"
export OMARCHY_PATH="$TMP/omarchy"
export XDG_RUNTIME_DIR="$TMP/run"
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/omarchy/default"
cp -r "$ROOT/default/themed" "$TMP/omarchy/default/themed"
mkdir -p "$HOME/.local/state/omarchy/current" "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME"
ln -s "$THEMES/nord" "$HOME/.config-omarchy-placeholder" 2>/dev/null || true
rm -f "$HOME/.config-omarchy-placeholder"
ln -s "$THEMES/nord/backgrounds/one.png" "$HOME/.local/state/omarchy/current/background"
printf 'nord\n' >"$HOME/.local/state/omarchy/current/theme.name"

# --- mocks ----------------------------------------------------------------

cat >"$MOCK/omarchy-shell" <<'MOCKED'
#!/bin/bash
printf 'shell %s\n' "$*" >> "$CALL_LOG"
exit 0
MOCKED

cat >"$MOCK/omarchy-notification-send" <<'MOCKED'
#!/bin/bash
printf 'notification %s\n' "$*" >> "$CALL_LOG"
MOCKED

cat >"$MOCK/omarchy-hook" <<'MOCKED'
#!/bin/bash
printf 'hook %s\n' "$*" >> "$CALL_LOG"
exit 0
MOCKED

cat >"$MOCK/omarchy-theme-switcher" <<'MOCKED'
#!/bin/bash
printf 'switcher-preload\n' >> "$CALL_LOG"
exit 0
MOCKED

cat >"$MOCK/omarchy-theme-bg-cache" <<'MOCKED'
#!/bin/bash
exit 0
MOCKED

cat >"$MOCK/omarchy-restart-terminal" <<'MOCKED'
#!/bin/bash
theme_dir="$HOME/.local/state/omarchy/current/theme"
for generated in kitty.conf alacritty.toml ghostty.conf foot.ini; do
  if [[ -f $theme_dir/$generated ]]; then
    printf 'terminal-reload-saw %s\n' "$generated" >> "$CALL_LOG"
  else
    printf 'terminal-reload-missing %s\n' "$generated" >> "$CALL_LOG"
  fi
done
exit 0
MOCKED

for command in restart-hyprctl restart-btop restart-opencode restart-helix \
  theme-set-foot theme-set-tmux theme-set-gnome theme-set-pi theme-set-claude \
  theme-set-hermes theme-set-t3code theme-set-browser theme-set-vscode \
  theme-set-obsidian theme-set-keyboard; do
  printf '#!/bin/bash\nexit 0\n' >"$MOCK/omarchy-$command"
done
chmod +x "$MOCK"/*

export CALL_LOG="$TMP/calls.log"
export PATH="$MOCK:$ROOT/bin:$PATH"

# --- name resolution ------------------------------------------------------

output="$(bash "$ROOT/bin/omarchy-theme-set" "Tokyo Night" 2>&1)" || fail "Tokyo Night was rejected: $output"
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name") == "tokyo-night" ]] ||
  fail "'Tokyo Night' did not resolve to tokyo-night"

output="$(bash "$ROOT/bin/omarchy-theme-set" "TOKYO_NIGHT" 2>&1)" || fail "TOKYO_NIGHT was rejected: $output"
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name") == "tokyo-night" ]] ||
  fail "'TOKYO_NIGHT' did not resolve to tokyo-night"

output="$(bash "$ROOT/bin/omarchy-theme-set" "Nord" 2>&1)" || fail "Nord was rejected: $output"
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name") == "nord" ]] ||
  fail "'Nord' did not resolve to nord"

output="$(bash "$ROOT/bin/omarchy-theme-set" "does-not-exist" 2>&1)" && fail "an unknown theme was accepted"
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name") == "nord" ]] ||
  fail "an unknown theme changed the current theme"

# --- the generated terminal configs exist before the reload signal --------

: >"$CALL_LOG"
bash "$ROOT/bin/omarchy-theme-set" "Tokyo Night" >/dev/null 2>&1
grep -q "terminal-reload-saw kitty.conf" "$CALL_LOG" ||
  fail "kitty.conf was not generated before the terminal reload signal"
grep -q "terminal-reload-saw alacritty.toml" "$CALL_LOG" ||
  fail "alacritty.toml was not generated before the terminal reload signal"
if grep -q "terminal-reload-missing" "$CALL_LOG"; then
  fail "a terminal config was missing at reload time: $(grep terminal-reload-missing "$CALL_LOG")"
fi

# --- the wallpaper stays resolvable across a swap -------------------------

bash "$ROOT/bin/omarchy-theme-set" "Nord" >/dev/null 2>&1
background="$(readlink -f "$HOME/.local/state/omarchy/current/background")"
[[ -f $background ]] || fail "the background symlink does not resolve after a theme swap: $background"
compgen -G "$HOME/.local/state/omarchy/current/theme.rollback.*" >/dev/null &&
  fail "a rollback directory was left behind"

ln -nsf "$HOME/.local/state/omarchy/current/theme/backgrounds/one.png" "$HOME/.local/state/omarchy/current/background"
OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1 bash "$ROOT/bin/omarchy-theme-set" "Tokyo Night" >/dev/null 2>&1
background="$(readlink -f "$HOME/.local/state/omarchy/current/background")"
[[ -f $background ]] || fail "skip-background left an outgoing-theme wallpaper dangling: $background"
grep -Fxq 'image-bytes-nord' "$background" || fail "skip-background did not preserve the outgoing wallpaper"

mkdir -p "$HOME/.config/omarchy/backgrounds/nord"
printf 'user-background\n' >"$HOME/.config/omarchy/backgrounds/nord/user.png"
bash "$ROOT/bin/omarchy-theme-set" "Nord" >/dev/null 2>&1
background="$(readlink -f "$HOME/.local/state/omarchy/current/background")"
[[ $background == "$HOME/.config/omarchy/backgrounds/nord/user.png" ]] ||
  fail "the user background path was not preserved"

cat >"$MOCK/ln" <<'MOCKED'
#!/bin/bash
if [[ -n ${FAIL_BACKGROUND_LINK:-} && ${!#} == "$HOME/.local/state/omarchy/current/background" && ! -e "$MOCK/link-failed" ]]; then
  : >"$MOCK/link-failed"
  exit 1
fi
exec /usr/bin/ln "$@"
MOCKED
chmod +x "$MOCK/ln"
set +e
output="$(FAIL_BACKGROUND_LINK=1 bash "$ROOT/bin/omarchy-theme-set" "Tokyo Night" 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]] || fail "a post-move background failure reported success"
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name") == "nord" ]] ||
  fail "a post-move background failure changed theme.name"
grep -q 'background = "#2e3440"' "$HOME/.local/state/omarchy/current/theme/colors.toml" ||
  fail "a post-move background failure did not restore the previous theme"
background="$(readlink -f "$HOME/.local/state/omarchy/current/background")"
[[ -f $background ]] || fail "a post-move background failure left the wallpaper dangling"


bash "$ROOT/bin/omarchy-theme-set" "Nord" >/dev/null 2>&1
before="$(cat "$HOME/.local/state/omarchy/current/theme/colors.toml")"

set +e
output="$(bash "$ROOT/bin/omarchy-theme-set" "no-palette" 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]] || fail "a theme with an empty colors.toml was applied"
[[ $output == *"no colors.toml"* ]] || fail "the empty colors.toml was not reported: $output"
[[ $(cat "$HOME/.local/state/omarchy/current/theme/colors.toml") == "$before" ]] ||
  fail "a rejected theme replaced the current colors.toml"
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name") == "nord" ]] ||
  fail "a rejected theme changed theme.name"

printf 'background = "#000"\nthis line has no assignment and no comment marker\x00\n' \
  >"$THEMES/no-palette/colors.toml"
set +e
output="$(bash "$ROOT/bin/omarchy-theme-set" "no-palette" 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]] || fail "a theme with a malformed colors.toml was applied"
[[ $(cat "$HOME/.local/state/omarchy/current/theme/colors.toml") == "$before" ]] ||
  fail "a malformed theme replaced the current colors.toml"
rm -f "$THEMES/no-palette/colors.toml"
printf 'background = "#000"\n' >"$THEMES/no-palette/colors.toml"
printf 'background = "#000"\nforeground = "#fff"\n' >"$THEMES/no-palette/colors.toml"

# --- a failed swap restores the previous theme ----------------------------

cat >"$MOCK/mv" <<'MOCKED'
#!/bin/bash
printf 'mv %s\n' "$*" >> "$CALL_LOG"
if [[ -n ${FAIL_THEME_SWAP:-} && ${1:-} == "$HOME/.local/state/omarchy/current/next-theme" && ${2:-} == "$HOME/.local/state/omarchy/current/theme" ]]; then
  exit 1
fi
exec /usr/bin/mv "$@"
MOCKED
chmod +x "$MOCK/mv"

set +e
output="$(FAIL_THEME_SWAP=1 bash "$ROOT/bin/omarchy-theme-set" "Tokyo Night" 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]] || fail "a failed swap reported success"
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name") == "nord" ]] ||
  fail "a failed swap changed theme.name"
grep -q 'background = "#2e3440"' "$HOME/.local/state/omarchy/current/theme/colors.toml" ||
  fail "a failed swap did not restore the previous theme directory"
background="$(readlink -f "$HOME/.local/state/omarchy/current/background")"
[[ -f $background ]] || fail "a failed swap left the wallpaper path dangling: $background"

# --- the previous theme outlives the link being repointed -----------------

cat >"$MOCK/rm" <<'MOCKED'
#!/bin/bash
printf 'rm %s\n' "$*" >> "$CALL_LOG"
exec /usr/bin/rm "$@"
MOCKED
cat >"$MOCK/ln" <<'MOCKED'
#!/bin/bash
printf 'ln %s\n' "$*" >> "$CALL_LOG"
exec /usr/bin/ln "$@"
MOCKED
chmod +x "$MOCK/rm" "$MOCK/ln"

: >"$CALL_LOG"
bash "$ROOT/bin/omarchy-theme-set" "Tokyo Night" >/dev/null 2>&1
rollback_removed=$(grep -n 'rm -rf .*theme\.rollback' "$CALL_LOG" | tail -n1 | cut -d: -f1)
background_relinked=$(grep -n 'ln -nsf .*current/background' "$CALL_LOG" | tail -n1 | cut -d: -f1)
[[ -n $rollback_removed ]] || fail "the outgoing theme directory was never removed"
[[ -n $background_relinked ]] || fail "the background link was never repointed"
(( rollback_removed > background_relinked )) ||
  fail "the outgoing theme directory was deleted before the wallpaper was relinked"
rm -f "$MOCK/rm" "$MOCK/ln"

# --- post-hook failures are reported without rolling the theme back -------

bash "$ROOT/bin/omarchy-theme-set" "Nord" >/dev/null 2>&1
cat >"$MOCK/omarchy-restart-terminal" <<'MOCKED'
#!/bin/bash
printf 'terminal-reload-missing-check\n' >> "$CALL_LOG"
exit 3
MOCKED
chmod +x "$MOCK/omarchy-restart-terminal"

set +e
output="$(bash "$ROOT/bin/omarchy-theme-set" "Tokyo Night" 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]] || fail "a failing post-hook reported success"
[[ $output == *"omarchy-restart-terminal"* ]] || fail "the failing hook was not named: $output"
[[ $output == *"is applied"* ]] || fail "the report did not say the theme was applied: $output"
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name") == "tokyo-night" ]] ||
  fail "a post-hook failure rolled the theme back"
[[ -f $(readlink -f "$HOME/.local/state/omarchy/current/background") ]] ||
  fail "a post-hook failure left the wallpaper dangling"

printf '%s\n' "mocked theme-set tests passed"
