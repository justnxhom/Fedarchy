#!/bin/bash
# btop and yazi each keep their own hand-written configuration, and a theme has
# to reach both without taking any of it over:
#
#   btop         has no include directive, so a `theme =` key has to go in the
#                user's btop.conf -- and only that key, with every other setting
#                left alone and an existing key replaced rather than duplicated.
#   yazi         names its theme from yazi.toml; an explicit choice there is
#                respected, and the theme is written to the path yazi falls back
#                to when there is none.
#
# The shell prompt is deliberately not here: it is Starship now, on a fixed
# two-segment config of its own that no theme repaints.
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
  "$HOME/.config" "$XDG_CACHE_HOME"
cp -r "$ROOT/default/themed" "$TMP/omarchy/default/themed"

for command in notification-send hook theme-switcher theme-bg-cache restart-terminal; do
  printf '#!/bin/bash\nexit 0\n' >"$MOCK/omarchy-$command"
done
for command in restart-hyprctl restart-btop restart-opencode restart-helix \
  theme-set-foot theme-set-tmux theme-set-gnome theme-set-pi theme-set-claude \
  theme-set-hermes theme-set-t3code theme-set-browser theme-set-vscode \
  theme-set-obsidian theme-set-keyboard; do
  printf '#!/bin/bash\nexit 0\n' >"$MOCK/omarchy-$command"
done
chmod +x "$MOCK"/*
export PATH="$MOCK:$ROOT/bin:$PATH"

# A staged theme with a palette, as omarchy-theme-set leaves for the steps.
THEME_DIR="$HOME/.local/state/omarchy/current/theme"
mkdir -p "$THEME_DIR"
cat >"$THEME_DIR/colors.toml" <<'COLORS'
background = "#101010"
foreground = "#f0f0f0"
accent = "#7ab7d4"
muted = "#505050"
selection = "#2a2a2a"
darker_background = "#080808"
blue = "#7ab7d4"
cyan = "#7fd4c1"
green = "#a3be8c"
magenta = "#b48ead"
orange = "#d08770"
purple = "#b48ead"
red = "#bf616a"
yellow = "#ebcb8b"
COLORS

render() {
  # The renderer reads the palette from the staging directory it writes into.
  NEXT="$HOME/.local/state/omarchy/current/next-theme"
  mkdir -p "$NEXT"
  cp "$THEME_DIR/colors.toml" "$NEXT/colors.toml"
  bash "$ROOT/bin/omarchy-theme-set-templates" >/dev/null 2>&1 || true
  [[ -f $NEXT/btop.theme ]] || fail "the btop template did not render"
  [[ -f $NEXT/yazi-theme.toml ]] || fail "the yazi template did not render"
  mv "$NEXT/btop.theme" "$THEME_DIR/btop.theme"
  mv "$NEXT/yazi-theme.toml" "$THEME_DIR/yazi-theme.toml"
}
render

run_step() {
  bash "$ROOT/bin/$1"
}

# --- btop --------------------------------------------------------------------

BTOP_CONF="$HOME/.config/btop/btop.conf"
mkdir -p "$HOME/.config/btop"
cat >"$BTOP_CONF" <<'BTOPCONF'
# A hand-written btop configuration.
theme_background = false
truecolor = true
graph_symbol = "braille"
vim_keys = true
update_ms = 2000
BTOPCONF

run_step omarchy-theme-set-btop >/dev/null
[[ -f "$HOME/.config/btop/themes/omarchy.theme" ]] || fail "the btop theme was not installed"
pass "the btop theme is installed where btop looks for it"

grep -qE '^theme[[:space:]]*=[[:space:]]*"themes/omarchy\.theme"' "$BTOP_CONF" \
  || fail "btop.conf was not pointed at the generated theme: $(grep -c theme "$BTOP_CONF")"
pass "btop.conf gains the theme key"

for key in theme_background truecolor graph_symbol vim_keys update_ms; do
  grep -qE "^$key[[:space:]]*=" "$BTOP_CONF" || fail "btop.conf lost the user's $key"
done
[[ $(grep -cE '^[a-z_]+[[:space:]]*=' "$BTOP_CONF") -eq 6 ]] \
  || fail "btop.conf gained or lost settings: $(grep -cE '^[a-z_]+[[:space:]]*=' "$BTOP_CONF") entries"
pass "every one of the user's btop settings survives"

# A second run must not stack up duplicate keys.
run_step omarchy-theme-set-btop >/dev/null
[[ $(grep -cE '^theme[[:space:]]*=' "$BTOP_CONF") -eq 1 ]] \
  || fail "the theme key was duplicated on a second run"
pass "re-applying the theme does not duplicate the key"

# An existing key is replaced, not appended alongside.
sed -i 's|^theme = .*|theme = "themes/something-else.theme"|' "$BTOP_CONF"
run_step omarchy-theme-set-btop >/dev/null
[[ $(grep -cE '^theme[[:space:]]*=' "$BTOP_CONF") -eq 1 ]] \
  || fail "an existing theme key was duplicated"
grep -q 'themes/omarchy.theme' "$BTOP_CONF" || fail "an existing theme key was not replaced"
pass "an existing theme key is replaced"

# A commented-out mention is not a setting and must be left alone.
cat >"$BTOP_CONF" <<'BTOPCONF'
# theme = "themes/old.theme"
truecolor = true
BTOPCONF
run_step omarchy-theme-set-btop >/dev/null
grep -q '^# theme = "themes/old.theme"' "$BTOP_CONF" || fail "a commented line was rewritten"
grep -qE '^theme[[:space:]]*=' "$BTOP_CONF" || fail "the theme key was not added"
pass "a commented-out theme line is left as it is"

# --- yazi --------------------------------------------------------------------

YAZI_DIR="$HOME/.config/yazi"
mkdir -p "$YAZI_DIR"
printf '[manager]\ncwd = { fg = "#007BFF" }\n' >"$YAZI_DIR/theme.toml"

run_step omarchy-theme-set-yazi >/dev/null
[[ -f $YAZI_DIR/theme.toml ]] || fail "the yazi theme was not installed"
grep -q '7ab7d4' "$YAZI_DIR/theme.toml" || fail "the yazi theme does not carry the palette"
[[ -f $YAZI_DIR/theme.toml.omarchy-backup ]] || fail "the hand-written yazi theme was not kept"
grep -q '007BFF' "$YAZI_DIR/theme.toml.omarchy-backup" || fail "the backup does not hold the original"
pass "the yazi theme is installed and the hand-written one is kept"

# Yazi validates its theme file strictly and refuses to start on a key it does
# not know, so the generated theme is checked against the structure yazi's own
# theme uses. A setting that belongs in yazi.toml -- show_hidden, sort_by -- is
# what an invented [files] section brings, and it makes yazi unopenable.
# Yazi validates its theme file strictly and refuses to start on a key it does
# not know, so the generated theme is checked against the sections and keys
# yazi's own theme defines. A setting that belongs in yazi.toml -- show_hidden,
# sort_by -- is what an invented [files] section brings, and it makes yazi
# impossible to open.
python3 - "$YAZI_DIR/theme.toml" <<'PYCHECK' || fail "the generated yazi theme has keys yazi would reject"
import sys, tomllib

# yazi's documented theme surface. Anything outside this is rejected by yazi.
KNOWN = {
    "manager": {
        "cwd", "hovered", "preview_hovered", "find_keyword", "find_position",
        "marker_copied", "marker_cut", "marker_selected", "tab_active",
        "tab_inactive", "border_symbol", "border_style",
    },
    "mode": {
        "normal_main", "normal_alt", "select_main", "select_alt",
        "unset_main", "unset_alt",
    },
    "status": {
        "separator_open", "separator_close", "separator_style",
        "mode_normal", "mode_select", "mode_unset",
        "permissions_t", "permissions_r", "permissions_w", "permissions_x",
        "permissions_s",
    },
    "input": {"border", "title", "value", "selected"},
    "select": {"border", "active", "inactive"},
    "tasks": {"border", "title", "hovered"},
    "which": {"mask", "cand", "rest", "desc", "separator", "separator_style"},
    "help": {"on", "exec", "desc", "hovered", "footer"},
    # File rows and icons. A theme that omits these leaves the file list and the
    # folder icons on yazi's built-in colours, which is what makes a theme look
    # only half applied.
    "filetype": {"rules"},
    "icon": {"globs", "dirs", "files", "exts", "conds"},
}

generated = tomllib.load(open(sys.argv[1], "rb"))
rejected = []
for section, keys in generated.items():
    if section not in KNOWN:
        rejected.append(f"section {section}")
        continue
    if not isinstance(keys, dict):
        continue
    for key in keys:
        if key not in KNOWN[section]:
            rejected.append(f"{section}.{key}")

# A rule is a table, and its style keys are yazi's, not arbitrary ones.
STYLE = {"fg", "bg", "bold", "italic", "underline", "reversed", "strikethrough"}
for rule in generated.get("filetype", {}).get("rules", []):
    for key in rule:
        if key not in STYLE | {"mime", "url", "is", "name", "text"}:
            rejected.append(f"filetype.rules.{key}")
for group in ("dirs", "files", "exts", "conds"):
    for rule in generated.get("icon", {}).get(group, []):
        for key in rule:
            if key not in STYLE | {"name", "text", "if", "mime", "url", "is"}:
                rejected.append(f"icon.{group}.{key}")
if rejected:
    print("yazi would reject: " + ", ".join(rejected), file=sys.stderr)
    sys.exit(1)
PYCHECK
pass "the generated yazi theme only uses keys yazi accepts"

# A setting is not a theme field: one slipped in once and made yazi refuse to
# start at all.
for setting in show_hidden sort_by; do
  if grep -qE "^[[:space:]]*$setting[[:space:]]*=" "$YAZI_DIR/theme.toml"; then
    fail "the yazi theme sets '$setting', which belongs in yazi.toml"
  fi
done
pass "the yazi theme carries no yazi.toml settings"

[[ -f $YAZI_DIR/yazi.toml ]] || fail "yazi.toml was created when there was none"
grep -qE '^\[ui\]' "$YAZI_DIR/yazi.toml" || fail "yazi.toml has no [ui] table"
grep -qE '^theme[[:space:]]*=[[:space:]]*"theme.toml"' "$YAZI_DIR/yazi.toml" \
  || fail "yazi.toml does not name the generated theme"
pass "yazi.toml is pointed at the generated theme"

# A theme the user chose themselves is respected, not overridden.
printf '[ui]\ntheme = "my-own.theme"\n' >"$YAZI_DIR/yazi.toml"
run_step omarchy-theme-set-yazi >/dev/null
[[ $(grep -cE '^theme[[:space:]]*=' "$YAZI_DIR/yazi.toml") -eq 1 ]] \
  || fail "a second theme key was added to yazi.toml"
grep -q 'my-own.theme' "$YAZI_DIR/yazi.toml" || fail "the user's own yazi theme was overridden"
pass "an explicit yazi theme choice is left alone"

# Re-running must not add the key again.
run_step omarchy-theme-set-yazi >/dev/null
[[ $(grep -cE '^theme[[:space:]]*=' "$YAZI_DIR/yazi.toml") -eq 1 ]] \
  || fail "the yazi theme key was duplicated on a second run"
pass "re-applying does not duplicate the yazi theme key"

# --- the configs are replaced atomically --------------------------------------
#
# A plain copy truncates its target first, and a running btop or yazi reading
# that file mid-copy sees half a file -- which is what a broken theme right
# after a switch looks like. Renaming into place cannot be caught that way, so
# the writes are checked to go through a temporary file.
for step in omarchy-theme-set-btop omarchy-theme-set-yazi; do
  source_file="$ROOT/bin/$step"
  grep -q 'mktemp' "$source_file" || fail "$step writes its target without a temporary file"
  grep -qE '(^|[^a-z_])mv -f' "$source_file" || fail "$step does not rename into place"
done
pass "both configs are replaced by rename, not by an in-place copy"

run_step omarchy-theme-set-btop >/dev/null
run_step omarchy-theme-set-yazi >/dev/null
# Looked for by the name the install actually creates -- the target plus a
# mktemp suffix -- rather than a loose glob, which matches unrelated files such
# as user-dirs.locale and would report them as leftovers.
leftovers=0
for target in "$HOME/.config/btop/themes/omarchy.theme" \
  "$HOME/.config/yazi/theme.toml"; do
  found=$(find "$(dirname "$target")" -maxdepth 1 -name "$(basename "$target").??????" 2>/dev/null | wc -l)
  leftovers=$((leftovers + found))
done
[[ $leftovers -eq 0 ]] || fail "$leftovers temporary install file(s) were left behind"
pass "no temporary install file is left behind"

# A reader must never see a partial file, so the source is made large and valid:
# big enough that a non-atomic copy has a window to be caught in. btop's theme is
# line-based, so it is padded with one long comment that a half-written copy
# would leave truncated.
python3 - "$THEME_DIR/btop.theme" <<'PYBIG' || fail "could not enlarge the btop theme"
import sys

path = sys.argv[1]
with open(path, "a") as handle:
    handle.write("# " + "x" * 400000 + "\n")
PYBIG
run_step omarchy-theme-set-btop >/dev/null
python3 -c "
import sys
tail = open('$HOME/.config/btop/themes/omarchy.theme').read().rstrip('\n').rsplit('\n', 1)[-1]
assert tail == '# ' + 'x' * 400000, 'the installed copy is truncated: a partial write'
" || fail "the installed btop theme is short, so it was not written atomically"
pass "a large config is installed whole, never half-written"

# --- a theme with no such payload is a no-op, not a failure -----------------

rm -f "$THEME_DIR/btop.theme" "$THEME_DIR/yazi-theme.toml"
for step in omarchy-theme-set-btop omarchy-theme-set-yazi; do
  run_step "$step" >/dev/null || fail "$step failed when the theme had no payload for it"
done
pass "a theme without these payloads leaves the two alone"
