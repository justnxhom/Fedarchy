#!/bin/bash
# Two TUI applications take their colours from configuration files that the
# template pipeline does not write, and both have a way of looking themed while
# nothing has changed:
#
#   Ekphos  names a theme in config.toml, which is either a built-in or a file in
#           a themes directory. Writing the theme file is not enough: until that
#           key names it, ekphos keeps using whatever it was using.
#
#   Kaizen  has no theme file at all. Its colours live in a hand-edited config
#           that also holds settings with nothing to do with colour, so it has to
#           be updated in place -- which brings two traps. A key that is not
#           already there must not be added, since kaizen would ignore it. And
#           hex colours have to stay quoted, because an unquoted `#d8dee9` in
#           YAML is a comment: it parses as null, and kaizen falls back to
#           whatever it does for a missing colour, with nothing reported.
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
export OMARCHY_THEME_HEADLESS=1
mkdir -p "$HOME/.local/state/omarchy/current" "$HOME/.config/ekphos" "$HOME/.config/kaizen"

CURRENT="$HOME/.local/state/omarchy/current"
CONFIG_DIR="$HOME/.config"

step() {
  bash "$ROOT/bin/$1" >/dev/null
}

ACCENT="#7ab7d4"
BG="#101010"
FG="#f0f0f0"
MUTED="#5a5a5a"
SELECTION="#504945"
ORANGE="#e1875c"

stage_theme() {
  rm -rf "$CURRENT/next-theme" "$CURRENT/theme"
  mkdir -p "$CURRENT/next-theme"

  cat >"$CURRENT/next-theme/colors.toml" <<COLORS
mode = "dark"
background = "$BG"
dark_background = "$BG"
darker_background = "$BG"
lighter_background = "#3c3836"
foreground = "$FG"
accent = "$ACCENT"
selection = "$SELECTION"
muted = "$MUTED"
blue = "$ACCENT"
cyan = "#6f9e8f"
magenta = "#c07fd7"
red = "#d66767"
green = "#7fbf7f"
yellow = "#e0c060"
orange = "$ORANGE"
purple = "#c07fd7"
bright_red = "#d66767"
bright_yellow = "#e0c060"
bright_green = "#7fbf7f"
COLORS

  step omarchy-theme-set-templates
  mv "$CURRENT/next-theme" "$CURRENT/theme"
}

# --- neither config is invented ---------------------------------------------

stage_theme

rm -rf "$CONFIG_DIR/ekphos" "$CONFIG_DIR/kaizen"
step omarchy-theme-set-ekphos
[[ ! -e $CONFIG_DIR/ekphos/config.toml ]] \
  || fail "an ekphos config was created for an application that is not configured"
step omarchy-theme-set-kaizen
[[ ! -e $CONFIG_DIR/kaizen/config.yaml ]] \
  || fail "a kaizen config was created for an application that is not configured"
pass "no config is invented for an application that has none"

# --- ekphos ------------------------------------------------------------------

mkdir -p "$CONFIG_DIR/ekphos"
cat >"$CONFIG_DIR/ekphos/config.toml" <<'TOML'
notes_dir = "/home/notes"
welcome_shown = true
theme = "kanagawa"
syntax_theme = "base16-ocean.dark"
transparent_bg = false

[editor]
tab_width = 4
TOML

step omarchy-theme-set-ekphos

THEME_FILE="$CONFIG_DIR/ekphos/themes/omarchy.toml"
[[ -f $THEME_FILE ]] || fail "no ekphos theme was written"

# Writing the file is not enough. Until config.toml names it, ekphos keeps using
# the built-in theme it was already on, and reports no problem.
grep -qE '^[[:space:]]*theme[[:space:]]*=[[:space:]]*"omarchy"[[:space:]]*$' "$CONFIG_DIR/ekphos/config.toml" \
  || fail "ekphos config.toml does not select the generated theme"

# A second theme key would leave the file with two answers. Ekphos takes the last
# one, so the generated theme would be ignored while the config still looked
# correct.
[[ $(grep -cE '^[[:space:]]*theme[[:space:]]*=' "$CONFIG_DIR/ekphos/config.toml") -eq 1 ]] \
  || fail "the theme key was duplicated; ekphos reads the last occurrence"
pass "ekphos selects the generated theme, exactly once"

# Everything the theme does not own has to survive.
for key in 'notes_dir = "/home/notes"' 'syntax_theme = "base16-ocean.dark"' 'tab_width = 4'; do
  grep -q "$key" "$CONFIG_DIR/ekphos/config.toml" \
    || fail "the ekphos step dropped a setting it does not own: $key"
done
pass "ekphos keeps the settings the theme does not own"

# The theme has to be valid TOML carrying this palette. A key ekphos does not
# read is not a theme, however plausible it looks.
python3 - "$THEME_FILE" "$ACCENT" "$BG" "$FG" <<'PYTHON' || fail "the ekphos theme is not valid TOML, or does not carry the palette"
import sys, tomllib
path, accent, bg, fg = sys.argv[1:5]
with open(path, "rb") as handle:
    data = tomllib.load(handle)
# Keyed by full dotted path. Leaf names repeat across sections -- there are four
# different `background` keys -- so a flat map would silently compare one section's
# value against another's expectation.
flat = {}
def walk(node, prefix=""):
    for key, value in node.items():
        path = f"{prefix}{key}"
        if isinstance(value, dict):
            walk(value, path + ".")
        else:
            flat[path] = value
walk(data)
for required in ("base.background", "base.foreground", "ui.border_focused",
                 "accent.primary", "semantic.error", "ui.selection"):
    if required not in flat:
        sys.exit(1)
assert flat["base.background"] == bg, flat["base.background"]
assert flat["base.foreground"] == fg, flat["base.foreground"]
assert flat["ui.border_focused"] == accent, flat["ui.border_focused"]
assert flat["accent.primary"] == accent, flat["accent.primary"]
# The accent belongs on the focused border, not on the text.
assert flat["base.foreground"] != accent
PYTHON
pass "the ekphos theme is valid TOML carrying the palette, with the accent off the text"

# One file, rewritten each switch. A per-theme filename would leave every theme
# ever selected sitting in the directory, all but one stale.
step omarchy-theme-set-ekphos
themes=$(find "$CONFIG_DIR/ekphos/themes" -name '*.toml' | wc -l)
(( themes == 1 )) || fail "re-running left $themes theme files; the generated one is rewritten in place"
pass "re-running rewrites the one theme file rather than accumulating them"

# --- kaizen ------------------------------------------------------------------

mkdir -p "$CONFIG_DIR/kaizen"

# Shaped like the real config: quoted hex, inconsistent indentation, and a
# non-colour setting that must not be touched.
cat >"$CONFIG_DIR/kaizen/config.yaml" <<'YAML'
DefaultForeground:
  light: "#874Bfd"
  dark: "#7d56f4"

DefaultUnfocused:
  light: "#3a3a3a"
  dark: "#b0b0b0"

DefaultActiveTab:
  light: "#9F2B68"
  dark: "#AA336A"

Tab1:
  focus:
    active: "#9F2B68"
    inactive: "#666666"
  table:
    selected:
      foreground: "#ffffcc"
      background: "#5c5cd6"
  spinner:
     color: "#AA336A"
     msg:
      color: "#c43b7b"
  ASCII Art:
      color: "#AA336A"

DownloadToWorkingDirectory: false
YAML

before_keys=$(grep -cE ':' "$CONFIG_DIR/kaizen/config.yaml")
step omarchy-theme-set-kaizen
after_keys=$(grep -cE ':' "$CONFIG_DIR/kaizen/config.yaml")
[[ $before_keys -eq $after_keys ]] \
  || fail "the kaizen step changed the number of keys ($before_keys -> $after_keys); it must only replace values"
pass "the kaizen step replaces values without adding or removing keys"

grep -q '^DownloadToWorkingDirectory: false$' "$CONFIG_DIR/kaizen/config.yaml" \
  || fail "the kaizen step dropped a setting that has nothing to do with colour"
pass "kaizen keeps the settings that are not colours"

# The values have to arrive as colours. An unquoted #d8dee9 is a YAML comment,
# so it parses as null -- the config looks updated and kaizen is left with no
# colour at all.
python3 - "$CONFIG_DIR/kaizen/config.yaml" "$ACCENT" "$FG" "$MUTED" <<'PYTHON' || fail "kaizen's colours did not parse as colours; unquoted hex reads as a YAML comment"
import sys, yaml
path, accent, fg, muted = sys.argv[1:5]
with open(path, encoding="utf-8") as handle:
    data = yaml.safe_load(handle)

expected = {
    ("DefaultForeground", "light"): fg,
    ("DefaultForeground", "dark"): fg,
    ("DefaultUnfocused", "light"): muted,
    ("DefaultUnfocused", "dark"): muted,
    ("DefaultActiveTab", "light"): accent,
    ("DefaultActiveTab", "dark"): accent,
}
for (parent, leaf), want in expected.items():
    got = data[parent][leaf]
    assert isinstance(got, str) and got.startswith("#"), f"{parent}.{leaf} is {got!r}, not a colour"
    assert got == want, f"{parent}.{leaf} is {got}, expected {want}"

tab = data["Tab1"]
assert tab["focus"]["active"] == accent, tab["focus"]
assert tab["focus"]["inactive"] == muted, tab["focus"]
assert tab["spinner"]["color"] == accent, tab["spinner"]
# Siblings under the same parent, at different indents, must not be confused.
assert tab["spinner"]["msg"]["color"] == "#e1875c", tab["spinner"]
assert tab["ASCII Art"]["color"] == accent, tab["ASCII Art"]
assert data["DownloadToWorkingDirectory"] is False
PYTHON
pass "kaizen's colours parse as colours, and nested siblings stay distinct"

# A key the payload knows but the config lacks is skipped, never added. Simulated
# by removing a key the payload has a colour for: the step must not put it back.
before=$(grep -cE ':' "$CONFIG_DIR/kaizen/config.yaml")
python3 - "$CONFIG_DIR/kaizen/config.yaml" <<'PYTHON'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").readlines()
# Drop the ASCII Art colour block entirely.
out, skip = [], False
for line in lines:
    if line.startswith("  ASCII Art:"):
        skip = True
        continue
    if skip and line.strip() == "":
        skip = False
    if not skip:
        out.append(line)
open(path, "w", encoding="utf-8").writelines(out)
PYTHON
step omarchy-theme-set-kaizen
grep -q 'ASCII Art' "$CONFIG_DIR/kaizen/config.yaml" \
  && fail "the kaizen step added back a colour key the config no longer has"
[[ $(grep -cE ':' "$CONFIG_DIR/kaizen/config.yaml") -lt $before ]] \
  || fail "removing a key did not reduce the key count, so the test is not testing what it claims"
pass "a colour key the config does not have is not added"

# Put the key back for the stability check below, so that check runs against the
# full config rather than a trimmed one.
python3 - "$CONFIG_DIR/kaizen/config.yaml" <<'PYTHON'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace("DownloadToWorkingDirectory: false",
                    '  ASCII Art:\n      color: "#000000"\n\nDownloadToWorkingDirectory: false')
open(path, "w", encoding="utf-8").write(text)
PYTHON
step omarchy-theme-set-kaizen
after=$(grep -cE ':' "$CONFIG_DIR/kaizen/config.yaml")

# Re-running must not drift: same values, same key count, no duplicates.
step omarchy-theme-set-kaizen
[[ $(grep -cE ':' "$CONFIG_DIR/kaizen/config.yaml") -eq $after ]] \
  || fail "re-running the kaizen step changed the key count"
python3 -c "
import sys, yaml
d = yaml.safe_load(open('$CONFIG_DIR/kaizen/config.yaml', encoding='utf-8'))
assert d['DefaultForeground']['dark'].startswith('#'), d['DefaultForeground']
" || fail "re-running the kaizen step broke the quoting"
pass "re-running the kaizen step is stable"

# --- both steps are part of the theme switch ---------------------------------

grep -q 'omarchy-theme-set-ekphos' "$ROOT/bin/omarchy-theme-set" \
  || fail "the ekphos step is not registered in omarchy-theme-set"
grep -q 'omarchy-theme-set-kaizen' "$ROOT/bin/omarchy-theme-set" \
  || fail "the kaizen step is not registered in omarchy-theme-set"
pass "both steps are registered in omarchy-theme-set"

echo ""
echo "all tui application checks passed"
