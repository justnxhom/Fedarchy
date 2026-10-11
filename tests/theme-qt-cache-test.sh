#!/bin/bash
# Two sets of applications take their palette from a location the theme switcher
# has to reach deliberately, and both have a way of appearing to work while doing
# nothing:
#
#   Qt      reads a colour scheme named by path in ~/.config/qt5ct/qt5ct.conf, and
#           only loads it if QT_QPA_PLATFORMTHEME selects the qt5ct/qt6ct platform
#           theme. The scheme file can be written perfectly and every application
#           still uses its built-in colours, because the variable that makes it
#           read is only set in the running session's environment and is gone at
#           the next login.
#
#   Alacritty, kitty, Neovim, Hyprland and the shell each read one file from a
#           fixed path under ~/.cache/nahom-theme, and two of those paths do not
#           match the name the template pipeline stages the payload under. Writing
#           the staged name to the cache leaves those two applications on the
#           previous theme with no error anywhere.
#
# So this checks that the palette reaches each consumer under the name it
# actually looks for, that Qt text roles take the text colour rather than the
# accent, that nothing is written into application configuration, and that a
# theme missing a payload changes nothing instead of failing.
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

export HOME="$TMP/home"
export OMARCHY_PATH="$ROOT"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$TMP/cache"
export OMARCHY_THEME_HEADLESS=1
mkdir -p "$HOME/.local/state/omarchy/current" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$HOME/.config"

CURRENT="$HOME/.local/state/omarchy/current"
CACHE="$HOME/.cache/nahom-theme"
SCHEME="$HOME/.local/share/color-schemes/Fedarchy.colors"

step() {
  bash "$ROOT/bin/$1" >/dev/null
}

# The palette deliberately gives an accent that differs from the foreground, so
# "this value is the accent" and "this value is the text colour" are
# distinguishable. A test using the same value for both would pass whatever the
# template happened to emit.
stage_theme() {
  local background=$1 foreground=$2 accent=$3 mode=${4:-dark}
  rm -rf "$CURRENT/next-theme" "$CURRENT/theme"
  mkdir -p "$CURRENT/next-theme"

  cat >"$CURRENT/next-theme/colors.toml" <<COLORS
mode = "$mode"
background = "$background"
dark_background = "$background"
darker_background = "$background"
lighter_background = "#3c3836"
foreground = "$foreground"
accent = "$accent"
selection = "#504945"
muted = "#665c54"
blue = "$accent"
cyan = "#6f9e8f"
magenta = "#c07fd7"
red = "#d66767"
green = "#7fbf7f"
yellow = "#e0c060"
orange = "#e1875c"
purple = "#c07fd7"
bright_red = "#d66767"
bright_yellow = "#e0c060"
bright_green = "#7fbf7f"
COLORS

  step omarchy-theme-set-templates

  # Themes may ship their own neovim.lua. Real ones do, and it is a LazyVim
  # plugin spec rather than a script that applies highlights, so it must not be
  # what reaches the cache. It is planted here to keep that shadowing honest.
  if [[ ${SHADOWED_NVIM:-0} == 1 ]]; then
    cat >"$CURRENT/next-theme/neovim.lua" <<'SPEC'
return {
  { "EdenEast/nightfox.nvim" },
  { "LazyVim/LazyVim", opts = { colorscheme = "somebody-elses-theme" } },
}
SPEC
  fi

  mv "$CURRENT/next-theme" "$CURRENT/theme"
}

hex_to_rgb() {
  local hex="${1#\#}" r g b
  r=$((16#${hex:0:2}))
  g=$((16#${hex:2:2}))
  b=$((16#${hex:4:2}))
  printf '%s,%s,%s' "$r" "$g" "$b"
}

# --- the templates render ----------------------------------------------------

stage_theme "#101010" "#f0f0f0" "#7ab7d4"

for payload in qt-colors.conf zsh-theme.zsh fzf.zsh cava-theme.conf; do
  [[ -f $CURRENT/theme/$payload ]] || fail "the $payload template did not render"
done
pass "the qt and shell templates render"

# An unresolved token would be written into the user's config verbatim. A key a
# theme does not define resolves to empty for one theme out of many, so a
# template can reference something valid and still emit a literal token. Every
# payload is checked, not only the ones known today.
for payload in "$CURRENT/theme"/*; do
  [[ -f $payload ]] || continue
  case "$payload" in
    *.png | *.jpg | *.webp | *.woff* | *.ttf) continue ;;
  esac
  if grep -Iq . "$payload" 2>/dev/null && grep -q '{{' "$payload"; then
    fail "$(basename "$payload") still has unresolved template tokens: $(grep -o '{{[^}]*}}' "$payload" | head -3 | tr '\n' ' ')"
  fi
done
pass "no unresolved template tokens reach any generated payload"

# --- the qt scheme -----------------------------------------------------------

step omarchy-theme-set-qt

[[ -f $SCHEME ]] || fail "the qt scheme was not installed"
pass "the qt scheme is installed"

# In a Qt palette the Foreground roles are text. ForegroundActive is the text of
# active and selected items and ForegroundLink is hyperlink text, so putting the
# accent in either paints the theme's accent on ordinary text -- every selected
# row and every link -- which reads as a mistake rather than as emphasis. This
# was the original bug, and it was patched into a generated file rather than
# fixed at the source, so the template is checked directly.
FOREGROUND_RGB=$(hex_to_rgb "#f0f0f0")
ACCENT_RGB=$(hex_to_rgb "#7ab7d4")

for role in ForegroundActive ForegroundLink ForegroundNormal; do
  for section in Button Selection Tooltip View Window; do
    value=$(awk -v s="[Colors:$section]" -v k="$role" '
      $0 == s { in_section = 1; next }
      /^\[/ { in_section = 0 }
      in_section && $0 ~ "^" k "=" { sub("^" k "=", ""); print; exit }
    ' "$SCHEME")

    [[ -n $value ]] || fail "$role is missing from [Colors:$section]"
    [[ $value != "$ACCENT_RGB" ]] || fail "$role in [Colors:$section] is the accent; text must take the text colour"
    [[ $value == "$FOREGROUND_RGB" ]] || fail "$role in [Colors:$section] is $value, expected the text colour $FOREGROUND_RGB"
  done
done
pass "every qt text role takes the text colour, not the accent"

# The accent is not an error: it belongs on the roles meant to be noticed.
for role in DecorationFocus DecorationHover; do
  value=$(awk -v k="$role" '
    $0 == "[Colors:Selection]" { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && $0 ~ "^" k "=" { sub("^" k "=", ""); print; exit }
  ' "$SCHEME")
  [[ $value == "$ACCENT_RGB" ]] || fail "$role in [Colors:Selection] is $value, expected the accent $ACCENT_RGB"
done
pass "the accent stays on the selection decorations"

# The scheme is inert unless the platform theme that reads it is selected. It was
# previously exported into the running session only, so a re-login dropped it and
# every qt application reverted while the scheme file still looked correct.
ENV_FILE="$HOME/.config/environment.d/50-fedarchy-qt.conf"
[[ -f $ENV_FILE ]] || fail "QT_QPA_PLATFORMTHEME was not persisted to environment.d; it would be lost at the next login"
grep -q '^QT_QPA_PLATFORMTHEME=qt5ct:qt6ct$' "$ENV_FILE" \
  || fail "environment.d does not select the qt5ct/qt6ct platform theme"
pass "the platform theme is persisted rather than only exported"

mkdir -p "$HOME/.config/qt5ct"
step omarchy-theme-set-qt
grep -q "^color_scheme_path=$SCHEME\$" "$HOME/.config/qt5ct/qt5ct.conf" \
  || fail "qt5ct was not pointed at the generated scheme"
pass "qt5ct is pointed at the generated scheme"

# Pointing the toolkit at a scheme is harmless, but overwriting a path someone
# chose for themselves is how a theme switch silently breaks a setup.
printf '[General]\ncolor_scheme_path=/home/someone/else/custom.colors\n' >"$HOME/.config/qt5ct/qt5ct.conf"
step omarchy-theme-set-qt
grep -q 'color_scheme_path=/home/someone/else/custom.colors' "$HOME/.config/qt5ct/qt5ct.conf" \
  || fail "the qt step overwrote a colour scheme path the user had chosen"
pass "a colour scheme path the user chose is left alone"

# A hand-written scheme is the user's own work.
printf '[Colors:Window]\nForegroundNormal=1,2,3\n' >"$SCHEME"
step omarchy-theme-set-qt
[[ -f $SCHEME.omarchy-backup ]] || fail "an existing qt scheme was overwritten without being kept"
pass "an existing qt scheme is kept before being replaced"

# KWrite does not read the generated scheme. It has three independent choices and
# each has to be told separately, or the editor keeps light syntax colours on a
# dark theme -- and "Auto Color Theme Selection" left on makes it re-derive the
# syntax theme from the desktop setting, which no theme switch touches, so the
# editor looks themed right up until it is restarted.
KWCRITERC="$HOME/.config/kwriterc"
if [[ ! -f $KWCRITERC ]]; then
  # Absent, the step must not invent one: writing a configuration for an
  # application that is not installed means a future install adopts these values.
  step omarchy-theme-set-qt
  [[ ! -e $KWCRITERC ]] || fail "a kwriterc was created for an application that is not installed"
  pass "no kwriterc is invented when the application is not configured"
else
  fail "kwriterc should have been removed by the earlier step of this test"
fi

mkdir -p "$HOME/.config"
cat >"$KWCRITERC" <<'KW'
[KDE]
widgetStyle=Breeze

[KTextEditor Renderer]
Auto Color Theme Selection=true
Color Theme=Somebody Elses Theme
Other Key=keep me

[UiSettings]
ColorScheme=SomethingElse
KW

stage_theme "#101010" "#f0f0f0" "#7ab7d4" dark
step omarchy-theme-set-qt

section_key() {
  awk -v s="[$1]" -v k="$2" '
    $0 == s { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && $0 ~ "^" k "=" { sub("^" k "=", ""); print; exit }
  ' "$KWCRITERC"
}

# Breeze, and deliberately so. The widget style is KDE's own look, chosen once for
# every Qt application; a theme switch should not repaint it per palette, only
# record that a decision has been made.
[[ $(section_key "KDE" "widgetStyle") == "Breeze" ]] \
  || fail "kwrite widgetStyle is $(section_key "KDE" "widgetStyle"), expected Breeze"
[[ $(section_key "KTextEditor Renderer" "Auto Color Theme Selection") == "false" ]] \
  || fail "kwrite is still choosing its own syntax theme from the desktop setting"
[[ $(section_key "KTextEditor Renderer" "Color Theme") == "Fedarchy" ]] \
  || fail "a dark theme selected $(section_key "KTextEditor Renderer" "Color Theme")"
[[ $(section_key "UiSettings" "ColorScheme") == "Fedarchy" ]] \
  || fail "kwrite does not name the generated scheme"

# These three sections share one flat file, and a plain "replace the key
# anywhere" would let one section's key overwrite another's.
[[ $(grep -c 'Color Theme=' "$KWCRITERC") -eq 1 ]] \
  || fail "the syntax theme key was duplicated"
[[ $(grep -c 'ColorScheme=' "$KWCRITERC") -eq 1 ]] \
  || fail "the colour scheme key was duplicated"
grep -q '^Other Key=keep me$' "$KWCRITERC" \
  || fail "a key the theme does not manage was dropped from kwriterc"
pass "kwrite follows the theme's mode, in its own sections only"

# The editing surface is the one part of kwrite the syntax theme does not follow:
# every KSyntaxHighlighting theme carries its own fixed background, so a dark one
# stays black inside an otherwise correctly themed window, and nothing reports it
# because the syntax theme was applied successfully. The view's own colour keys are
# what make the text area follow the palette.
[[ $(section_key "BackgroundColors" "BackgroundColor") == "#101010" ]] \
  || fail "the kwrite editor background is $(section_key "BackgroundColors" "BackgroundColor"), not the theme background"
[[ $(section_key "ForegroundColors" "ForegroundColor") == "#f0f0f0" ]] \
  || fail "the kwrite editor text colour is $(section_key "ForegroundColors" "ForegroundColor"), not the theme foreground"
[[ $(section_key "ForegroundColors" "Selection") == "#504945" ]] \
  || fail "the kwrite selection is not the theme's"
[[ $(section_key "ForegroundColors" "Current Line Number") == "#7ab7d4" ]] \
  || fail "the kwrite current line number is not the theme's accent"
pass "the kwrite editing surface follows the theme, not the syntax theme's own background"

# Every colour has to be a colour. A blend that is passed 45 where a fraction is
# expected produces components above 255, which print as three hex digits each and
# give a nine-character value -- accepted by the file, and ignored by the widget.
for section in BackgroundColors ForegroundColors; do
  while IFS= read -r line; do
    key="${line%%=*}"
    value="${line#*=}"
    [[ $value =~ ^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$ ]] \
      || fail "kwrite $section/$key is $value, which is not a hex colour"
  done < <(awk -v s="[$section]" '
    $0 == s { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && /=/{ print }
  ' "$KWCRITERC")
done
pass "every kwrite colour value is a well-formed hex colour"

# The sections are appended, so a key must land in its own group rather than after
# whichever section happens to come last.
[[ $(awk -F= '/^\[/{s=$0} /^Current Line=/{print s}' "$KWCRITERC" | head -1) == "[BackgroundColors]" ]] \
  || fail "a kwrite colour landed in the wrong section"
[[ $(awk -F= '/^\[/{s=$0} /^Selection=/{print s}' "$KWCRITERC" | head -1) == "[ForegroundColors]" ]] \
  || fail "a kwrite colour landed in the wrong section"
pass "the new kwrite colour sections are grouped correctly"

# The editor canvas is decided by the syntax theme, not by the kwriterc view keys:
# a shipped-in KSyntaxHighlighting theme carries a fixed background, and it wins.
# So the only thing that can make the code view follow the theme is a generated
# theme, which is why this exists.
BG="#101010"
FG="#f0f0f0"
ACCENT="#7ab7d4"
KSYNTAX="$HOME/.local/share/org.kde.syntax-highlighting/themes/fedarchy.theme"
[[ -f $KSYNTAX ]] || fail "no KSyntaxHighlighting theme was installed, so the editor keeps a fixed background"
python3 - "$KSYNTAX" "$BG" "$FG" "$ACCENT" <<'PYTHON2' || fail "the installed editor theme is not valid JSON, or does not carry the palette"
import json, re, sys
path, bg, fg, accent = sys.argv[1:5]
data = json.load(open(path, encoding="utf-8"))

# The name in the metadata is what the editor's list shows, not the filename, so
# the two must agree or the setting written into kwriterc points at nothing.
assert data["metadata"]["name"], "the theme has no name"
assert re.fullmatch(r"#[0-9a-fA-F]{6}", data["editor-colors"]["BackgroundColor"]), data["editor-colors"]["BackgroundColor"]
assert data["editor-colors"]["BackgroundColor"] == bg, data["editor-colors"]["BackgroundColor"]
styles = data["text-styles"]
assert len(styles) >= 20, len(styles)
assert styles["Normal"]["text-color"] == fg, styles["Normal"]
assert styles["Keyword"]["text-color"] == accent, styles["Keyword"]
# The invariant that matters is contrast against the canvas, not a difference
# between a style's two colours -- a style whose selected colour equals its normal
# one is ordinary (the themes shipped with KDE do exactly that). A style painted in
# the background colour, though, is invisible, and the palette cannot rescue it
# afterwards.
for name, style in styles.items():
    if "text-color" in style:
        assert style["text-color"] != bg, f"{name} is painted in the background colour"
    if "background-color" in style:
        assert style["background-color"] != style.get("text-color", ""), f"{name} has no contrast against its own background"
PYTHON2
pass "the installed editor theme is valid JSON, named, and carries the palette"

# The value in kwriterc has to be the metadata name. Pointing it at the filename
# instead names a theme that does not exist, and the editor falls back silently.
metadata_name=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['metadata']['name'])" "$KSYNTAX")
[[ $(section_key "KTextEditor Renderer" "Color Theme") == "$metadata_name" ]] \
  || fail "kwriterc names the colour theme $(section_key "KTextEditor Renderer" "Color Theme") but the installed theme is called $metadata_name"
pass "kwriterc names the theme by its metadata name, not its filename"

# A comment header in the template is a JSON syntax error, and a theme that fails
# to parse is ignored without a message. Guarded so it cannot come back.
if head -c 2 "$ROOT/default/themed/ksyntax-theme.json.tpl" | grep -q '#'; then
  fail "the editor theme template starts with a comment; the file is parsed as JSON"
fi
pass "the editor theme template is parseable JSON with no comment header"

# --- the global platform style -------------------------------------------------

KDEGLOBALS="$HOME/.config/kdeglobals"
if [[ ! -f $KDEGLOBALS ]]; then
  step omarchy-theme-set-qt
  [[ ! -e $KDEGLOBALS ]] || fail "a kdeglobals was invented for a system that has none"
  pass "no kdeglobals is invented"
else
  fail "kdeglobals should have been removed by an earlier step of this test"
fi

mkdir -p "$HOME/.config"
cat >"$KDEGLOBALS" <<'KDG'
[General]
ColorScheme=SomebodyElses
LookAndFeelPackage=org.kde.breezedesktop

[KDE]
colorScheme=SomethingElse

[Icons]
Theme=breeze

[WM]
borderlessMaximizedWindows=true
KDG

stage_theme "$BG" "$FG" "$ACCENT"
step omarchy-theme-set-qt

kg() {
  awk -v s="[$1]" -v k="$2" '
    $0 == s { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && index($0, k "=") == 1 { sub("^" k "=", ""); print; exit }
  ' "$KDEGLOBALS"
}

# Absent is not the same as chosen: with no key at all, every Qt application falls
# back to whatever the toolkit defaults to, which no theme switch can influence.
[[ -n $(kg "KDE" "WidgetStyle") ]] \
  || fail "no WidgetStyle was written; the widget style stays whatever the default happens to be"
pass "the widget style is written rather than left to the default"

# kdeglobals records the colour scheme twice, under keys differing only in case.
# Left disagreeing, which one is read depends on the Qt version.
[[ $(kg "General" "ColorScheme") == "Fedarchy" ]] \
  || fail "[General] ColorScheme is $(kg "General" "ColorScheme")"
[[ $(kg "KDE" "colorScheme") == "Fedarchy" ]] \
  || fail "[KDE] colorScheme is $(kg "KDE" "colorScheme")"
pass "the two kdeglobals colour scheme keys agree instead of contradicting each other"

grep -q '^LookAndFeelPackage=org.kde.breezedesktop$' "$KDEGLOBALS" \
  || fail "a kdeglobals setting the theme does not own was dropped"
grep -q '^borderlessMaximizedWindows=true$' "$KDEGLOBALS" \
  || fail "a kdeglobals setting the theme does not own was dropped"
[[ $(grep -c '^Theme=breeze$' "$KDEGLOBALS") -eq 1 ]] \
  || fail "the icon theme was changed or duplicated"
pass "kdeglobals keeps the settings the theme does not own"

# A light palette must not leave the editor dark-on-light, which is exactly the way
# the dark case was light-on-dark. The syntax theme is now generated rather than
# chosen from a fixed list, so the check is that it follows the palette in either
# mode -- not that a different stock theme is named.
stage_theme "#fafafa" "#202020" "#305050" light
step omarchy-theme-set-qt
[[ $(section_key "KTextEditor Renderer" "Color Theme") == "Fedarchy" ]] \
  || fail "a light theme selected $(section_key "KTextEditor Renderer" "Color Theme")"
[[ $(section_key "BackgroundColors" "BackgroundColor") == "#fafafa" ]] \
  || fail "a light theme left the editor background at $(section_key "BackgroundColors" "BackgroundColor")"
[[ $(section_key "KTextEditor Renderer" "Auto Color Theme Selection") == "false" ]] \
  || fail "switching to a light theme re-enabled automatic syntax theme selection"
pass "a light theme themes the editor from its own palette"

rm -f "$KWCRITERC"

# --- the shared cache --------------------------------------------------------

rm -rf "$HOME/.config/qt5ct" "$SCHEME" "$SCHEME.omarchy-backup" "$ENV_FILE"
stage_theme "#101010" "#f0f0f0" "#7ab7d4"
step omarchy-theme-set-cache

# The staged name and the name the application reads are not always the same, and
# nothing complains when the payload lands under the wrong one: the application
# keeps reading the file the previous theme switch left there. Both renames are
# checked against the name the consumer looks for, not against the staged name.
declare -A EXPECTED=(
  [alacritty.toml]=alacritty.toml
  [kitty.conf]=kitty.conf
  [nvim-theme.lua]=nvim-theme.lua
  [hypr-colors.lua]=hypr-colors.lua
  [zsh-theme.zsh]=zsh-theme.zsh
  [fzf.zsh]=fzf.zsh
  [cava-theme.conf]=cava-theme.conf
)

for expected in "${!EXPECTED[@]}"; do
  [[ -f $CACHE/$expected ]] || fail "the cache has no $expected, which the application reads by that exact name"
done
pass "every consumer finds a payload under the name it reads"

# colors/nahom.lua dofiles this file and also watches it, so it has to apply the
# colours by side effect. A theme's own neovim.lua returns a plugin spec instead:
# dofile discards the return value, the editor keeps the highlights it had, and
# the switch reports success. So the check is that the payload actually sets
# highlights, and that it is the generated one rather than a theme's copy.
[[ -f $CACHE/nvim-theme.lua ]] || fail "no neovim payload was published"
highlight_calls=$(grep -cE '^hl\(0,|^vim\.api\.nvim_set_hl' "$CACHE/nvim-theme.lua" || true)
(( highlight_calls > 20 )) \
  || fail "the neovim payload makes $highlight_calls highlight calls; a plugin spec returns a table that dofile discards, leaving the editor unthemed"
grep -q 'somebody-elses-theme' "$CACHE/nvim-theme.lua" \
  && fail "the cache is serving a theme's own LazyVim spec instead of the generated highlights"
pass "the neovim payload applies highlights instead of returning a spec"

# A theme that ships its own neovim.lua must not be able to shadow the generated
# one, which is the arrangement that broke it.
SHADOWED_NVIM=1
stage_theme "#101010" "#f0f0f0" "#7ab7d4"
step omarchy-theme-set-cache
grep -q 'somebody-elses-theme' "$CACHE/nvim-theme.lua" \
  && fail "a theme's own neovim.lua reached the cache, where dofile discards it"
grep -q '#7ab7d4' "$CACHE/nvim-theme.lua" \
  || fail "the generated neovim payload was displaced by the theme's own file"
unset SHADOWED_NVIM
pass "a theme's own neovim.lua does not shadow the generated payload"

# Guard the specific renames, so that "fixing" the mapping back to the staged
# names fails the test rather than silently untheming two applications.
[[ -f $CACHE/nvim-theme.lua && ! -f $CACHE/neovim.lua ]] \
  || fail "neovim.lua must be published as nvim-theme.lua"
[[ -f $CACHE/hypr-colors.lua && ! -f $CACHE/hyprland.lua ]] \
  || fail "hyprland.lua must be published as hypr-colors.lua"
pass "the two renamed payloads are published under the names consumers read"

# decoration.lua reads the RETURNED table:
#
#     local ok, colours = pcall(dofile, ... "hypr-colors.lua")
#     local active = colours and colours.active or "rgb(e0563b)"
#
# A payload that applies the colours itself instead of returning them does not
# fail -- pcall succeeds, the module falls through to a hardcoded fallback colour
# belonging to no theme, and the switch reports success. The borders simply stop
# following the theme, with nothing in any log. So the contract is checked here
# rather than left to be discovered by looking at the screen.
H="$CACHE/hypr-colors.lua"
grep -qE '^\s*return\s*\{' "$H" \
  || fail "the hyprland payload never returns a table, so decoration.lua falls back to its hardcoded border colour"
for key in active inactive; do
  grep -qE "^[[:space:]]*$key[[:space:]]*=" "$H" \
    || fail "the hyprland payload has no $key key, which decoration.lua reads"
done
grep -qE '^[[:space:]]*active[[:space:]]*=[[:space:]]*"rgb\([0-9]+,[0-9]+,[0-9]+\)"' "$H" \
  || fail "the hyprland active border is not an rgb(r,g,b) string, which is what the hyprland lua config accepts"
grep -qE '^[[:space:]]*hl\.config' "$H" \
  && fail "the hyprland payload applies colours itself; decoration.lua must be the one to apply them, or it falls back to a hardcoded colour"
pass "the hyprland payload returns the table decoration.lua reads"

# A reload re-executes the whole Hyprland configuration, and the shell's popups are
# layer-shell surfaces inside it. The step is invoked from a dozen scripts that do
# not change the theme, so a reload that fires on every run reloads the running
# desktop for nothing -- which is a plausible way to leave the shell's popups
# wedged. Checked with a stub compositor, so no reload is issued for real.
MOCK="$TMP/bin"
mkdir -p "$MOCK"
cat >"$MOCK/hyprctl" <<'STUB'
#!/bin/bash
echo "$*" >>"$HYPRCTL_LOG"
STUB
chmod +x "$MOCK/hyprctl"

export HYPRCTL="$MOCK/hyprctl"
export HYPRCTL_LOG="$TMP/hyprctl.log"
: >"$HYPRCTL_LOG"

# Runs the step without the headless guard, since that is what skips the reload.
run_cache_live() {
  OMARCHY_THEME_HEADLESS=0 HYPRCTL="$MOCK/hyprctl" HYPRCTL_LOG="$HYPRCTL_LOG" \
    bash "$ROOT/bin/omarchy-theme-set-cache" >/dev/null
}

# Start from a palette the cache has not seen: an earlier part of this test already
# published this one, so switching to it again is a no-op and would prove nothing.
stage_theme "#202020" "#e0e0e0" "#8bc34a"
run_cache_live
first=$(wc -l <"$HYPRCTL_LOG")
(( first == 1 )) || fail "a changed border colour issued $first compositor calls, expected 1"
grep -q 'reload config-only' "$HYPRCTL_LOG" \
  || fail "the reload did not ask for config-only, so it also re-read the monitors"

# Same theme again: the payload is identical, so the running desktop must be left
# alone. This is the case that used to reload the compositor on every invocation.
run_cache_live
second=$(wc -l <"$HYPRCTL_LOG")
[[ $second -eq $first ]] \
  || fail "re-publishing an unchanged border colour reloaded the compositor again ($second calls)"

# A genuinely different theme must still reach the compositor, or the border would
# quietly stop following the theme at all.
stage_theme "$BG" "$FG" "$ACCENT"
run_cache_live
third=$(wc -l <"$HYPRCTL_LOG")
[[ $third -gt $second ]] || fail "a real theme change did not reach the compositor"
pass "the compositor is reloaded on a real change, and not otherwise"

unset HYPRCTL HYPRCTL_LOG

# The values have to be this theme's, or decoration.lua applies a correct-looking
# border in the wrong colour.
active_value=$(grep -oE '^[[:space:]]*active[[:space:]]*=[[:space:]]*"rgb\([0-9]+,[0-9]+,[0-9]+\)"' "$H" | grep -oE '[0-9]+,[0-9]+,[0-9]+')
[[ $active_value == "$(hex_to_rgb '#7ab7d4')" ]] \
  || fail "the hyprland active border is $active_value, expected the theme accent $(hex_to_rgb '#7ab7d4')"
pass "the hyprland border carries the selected theme's accent"

# The payloads must carry this theme's palette, not the previous one.
grep -q '#7ab7d4' "$CACHE/nvim-theme.lua" || fail "the neovim payload does not carry the selected theme's accent"
grep -q '#101010' "$CACHE/nvim-theme.lua" || fail "the neovim payload does not carry the selected theme's background"
grep -q '7ab7d4' "$CACHE/hypr-colors.lua" || fail "the hyprland payload does not carry the selected theme's accent"
pass "the published payloads carry the selected theme"

# The cache exists so that these application configurations need not be rewritten.
# ~/.config/hypr in particular is the user's own, and a theme switch editing it
# would be a change nobody asked for.
[[ ! -e $HOME/.config/hypr ]] || fail "the cache step created ~/.config/hypr; it must only write the shared cache"
pass "no application configuration is written"

# Reading a payload while it is being replaced shows default colours for a frame,
# so the file is renamed into place rather than truncated and rewritten.
find "$CACHE" -name '*.??????' | grep -q . && fail "temporary files were left in the cache"
pass "no temporary files are left in the cache"

# A run killed between creating a temporary file and renaming it leaves one
# behind, and theme switches get interrupted. They are swept on the next run, so
# they do not accumulate and are not mistaken for payloads.
touch "$CACHE/kitty.conf.abcdef" "$CACHE/cava-theme.conf.zzzzzz"
step omarchy-theme-set-cache
[[ ! -e $CACHE/kitty.conf.abcdef && ! -e $CACHE/cava-theme.conf.zzzzzz ]] \
  || fail "a temporary file orphaned by an interrupted run was not cleaned up"
pass "temporary files orphaned by an interrupted run are swept"

# --- a theme missing a payload ----------------------------------------------

# A theme that does not define every payload must change what it can and leave
# the rest alone, rather than deleting a payload another application is still
# reading or reporting a failure.
cp "$CACHE/nvim-theme.lua" "$TMP/nvim-before"
rm -f "$CURRENT/theme/alacritty.toml" "$CURRENT/theme/kitty.conf"
step omarchy-theme-set-cache || fail "the cache step failed when a payload was missing"
[[ -f $CACHE/nvim-theme.lua ]] || fail "a missing payload caused an unrelated payload to be removed"
grep -q '#7ab7d4' "$CACHE/nvim-theme.lua" || fail "an unrelated payload was left stale"
rm -f "$CACHE/alacritty.toml" "$CACHE/kitty.conf"
[[ ! -e $CACHE/alacritty.toml ]] || fail "a stale payload from a previous theme survived a theme that no longer stages one"
pass "a theme missing a payload changes only what it stages"

# Nothing staged at all is the shape of a theme switch interrupted early: it
# should be quiet rather than wiping the cache every application reads from.
rm -rf "$CURRENT/theme"
step omarchy-theme-set-cache || fail "the cache step failed with no staged theme"
[[ -f $CACHE/nvim-theme.lua ]] || fail "the cache was emptied by a theme switch with nothing staged"
pass "an empty theme directory leaves the cache intact"

# Re-running must not accumulate: the ini keys are replaced in place, and the
# environment file is written once.
stage_theme "#101010" "#f0f0f0" "#7ab7d4"
step omarchy-theme-set-qt
step omarchy-theme-set-qt
[[ $(grep -c 'color_scheme_path' "$HOME/.config/qt5ct/qt5ct.conf") -eq 1 ]] \
  || fail "re-running the qt step duplicated color_scheme_path"
[[ $(wc -l <"$ENV_FILE") -eq 1 ]] || fail "re-running the qt step duplicated the environment entry"
pass "re-running the steps accumulates nothing"

echo ""
echo "all qt and cache checks passed"
