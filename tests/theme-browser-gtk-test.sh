#!/bin/bash
# Firefox and the GTK applications each take their theme from somewhere the
# theme switcher has to reach deliberately, and both have a way of appearing to
# work while doing nothing:
#
#   Firefox     keeps its configuration in a profile whose location moved to the
#               XDG directory, so a script looking only at ~/.mozilla/firefox
#               finds nothing at all and reports success. It also ignores
#               userChrome.css unless one pref is set, and that pref is off by
#               default.
#   GTK         reads ~/.config/gtk-3.0 and ~/.config/gtk-4.0 separately, and an
#               application only reads the one for its own toolkit. The file
#               manager is GTK 4, so styling GTK 3 alone leaves it stock.
#
# So this checks that the palette reaches both, that it is the palette of the
# theme that was selected, and that switching back and forth neither accumulates
# prefs nor leaves temporary files behind.
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
export XDG_RUNTIME_DIR="$TMP/run"
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$HOME/.local/state/omarchy/current" "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME" "$HOME/.config"

CURRENT="$HOME/.local/state/omarchy/current"
PROFILE_REL="8o6pxwqn.default-release"
PROFILE="$HOME/.config/mozilla/firefox/$PROFILE_REL"

step() {
  bash "$ROOT/bin/$1" >/dev/null
}

# Stage a theme the way a real switch does: its colours into the staging
# directory, the templates rendered from them, then the result moved into place.
# Rendering here rather than hand-writing the payload is the point -- it is what
# proves the templates resolve against a real palette.
stage_theme() {
  local background=$1 foreground=$2 accent=$3 mode=${4:-dark}
  rm -rf "$CURRENT/next-theme" "$CURRENT/theme"
  mkdir -p "$CURRENT/next-theme"

  cat >"$CURRENT/next-theme/colors.toml" <<COLORS
mode = "$mode"
background = "$background"
dark_background = "$background"
darker_background = "$background"
lighter_background = "$background"
foreground = "$foreground"
accent = "$accent"
selection = "$accent"
muted = "$foreground"
blue = "$accent"
cyan = "#6f9e8f"
magenta = "#c07fd7"
red = "#d66767"
green = "#7fbf7f"
yellow = "#e0c060"
purple = "#c07fd7"
COLORS

  step omarchy-theme-set-templates
  mv "$CURRENT/next-theme" "$CURRENT/theme"
}

# --- the templates render ----------------------------------------------------

stage_theme "#101010" "#f0f0f0" "#7ab7d4"

[[ -f $CURRENT/theme/firefox-userchrome.css ]] || fail "the firefox chrome template did not render"
[[ -f $CURRENT/theme/firefox-usercontent.css ]] || fail "the firefox newtab template did not render"
[[ -f $CURRENT/theme/gtk.css ]] || fail "the gtk template did not render"
pass "both new templates render"

# An unresolved token would be written into the user's config verbatim, where it
# is silently ignored -- or, in a toml file, breaks the parse outright. A key a
# theme does not define resolves to empty rather than to a default, so a template
# can reference something perfectly valid and still emit a literal "{{ mix ... }}"
# for one theme out of twenty-four. Every generated payload is checked, not just
# the ones known today.
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

# The Firefox stylesheet has to name custom properties Firefox actually defines.
# Inventing a plausible-looking name produces a file that loads and changes
# nothing, which is indistinguishable from the bug this is meant to catch.
for token in --toolbox-background-color --toolbar-background-color --toolbar-field-background-color \
  --panel-background-color --sidebar-background-color --color-accent-primary --text-color; do
  grep -q -- "$token:" "$CURRENT/theme/firefox-userchrome.css" \
    || fail "the firefox stylesheet never sets $token"
done
pass "the firefox stylesheet overrides the browser chrome's own tokens"

# userContent.css is loaded on every page, not just about:newtab, so a rule that
# styles a bare element would follow the user onto the whole web. The new tab
# background has to go through Firefox's own custom property, which only
# about: pages read.
python3 - "$CURRENT/theme/firefox-usercontent.css" <<'PYSCOPE' || fail "the newtab stylesheet could leak onto ordinary web pages"
import re, sys

text = open(sys.argv[1]).read()
# Strip comments, then take out the domain-scoped blocks. What is left is what
# applies to EVERY page, which is the only part that can follow the user onto the
# web. A selector inside @-moz-document is scoped to the domains it names and
# cannot leak, whatever element it names -- which is why `main` and `ytd-app`
# are acceptable there and not outside it.
body = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
global_scope = re.sub(r"@-moz-document[^\{]*\{(?:[^{}]*\{[^{}]*\}[^{}]*)*\}", "", body, flags=re.S)

# Class names commonly contain hyphens (.logo-and-wordmark), so the character
# class is [\w-] and not \w.
SAFE = re.compile(r"(html|body|:root|:root:root|\*|\.[\w-]+)")
offenders = []
for m in re.finditer(r"([^{}]+)\{", global_scope):
    sel = " ".join(m.group(1).split())
    if not sel or sel.startswith("@"):
        continue
    for part in sel.split(","):
        part = part.strip()
        if SAFE.fullmatch(part):
            continue
        offenders.append(part)
if offenders:
    print(f"selectors that apply to every page: {sorted(set(offenders))}", file=sys.stderr)
    sys.exit(1)

if "newtab-background-color" not in text:
    print("the newtab background is not set through Firefox's own property", file=sys.stderr)
    sys.exit(1)

# And nothing here paints an ordinary website. Attempting to theme a site from
# here was tried and abandoned: a flat canvas is not a theme, because the site
# paints its own panels over it and the result is never uniform, and keeping up
# with components that change under you is not something a desktop theme switcher
# should be doing. Guarded so it cannot creep back in.
if "@-moz-document" in body:
    print("the newtab stylesheet is painting web pages again", file=sys.stderr)
    sys.exit(1)
for domain in ("youtube.com", "chatgpt.com", "github.com"):
    if domain in text:
        print(f"{domain} is referenced again", file=sys.stderr)
        sys.exit(1)
PYSCOPE
pass "the newtab stylesheet cannot reach ordinary web pages at all"

# Whichever theme is active supplies its own values for these same properties,
# and those beat a plain declaration -- so the palette landed only on the tokens
# the theme happened not to set, and the browser came out half themed. Only
# !important outranks both a later stylesheet and an inline style, so every
# declaration in the block has to carry it.
python3 - "$CURRENT/theme/firefox-userchrome.css" <<'PYIMP' || fail "a chrome colour is not marked important"
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"^:root:root\s*\{(.*?)^\}", text, re.S | re.M)
if not m:
    print("no :root:root block found", file=sys.stderr)
    sys.exit(1)
decls = re.findall(r"^\s+(--[\w-]+):\s*([^;]+);\s*$", m.group(1), re.M)
if not decls:
    print("no custom properties in the block", file=sys.stderr)
    sys.exit(1)
plain = [name for name, value in decls if "!important" not in value]
if plain:
    print(f"{len(plain)} of {len(decls)} declarations are not important, e.g. {plain[:3]}", file=sys.stderr)
    sys.exit(1)
PYIMP
pass "every chrome colour outranks the active theme's"

# --- firefox: the profile is found where it actually is ----------------------

mkdir -p "$PROFILE" "$HOME/.config/mozilla/firefox"
cat >"$HOME/.config/mozilla/firefox/profiles.ini" <<INI
[Install4F96D1932A9F858E]
Default=Profiles/$PROFILE_REL

[Profile1]
Name=default-release
IsRelative=1
Path=$PROFILE_REL
INI

printf 'user_pref("my.own.pref", 7);\n' >"$PROFILE/user.js"

step omarchy-theme-set-firefox

[[ -f $PROFILE/chrome/userChrome.css ]] || fail "the stylesheet did not reach the XDG profile"
grep -q '#101010' "$PROFILE/chrome/userChrome.css" || fail "the stylesheet does not carry the theme background"

# The new tab page is a content page, so it needs userContent.css as well.
[[ -f $PROFILE/chrome/userContent.css ]] || fail "the newtab stylesheet was not installed"
grep -q '#101010' "$PROFILE/chrome/userContent.css" \
  || fail "the newtab background does not carry the theme"
grep -q 'logo-and-wordmark' "$PROFILE/chrome/userContent.css" \
  || fail "the newtab logo is not hidden"
pass "the newtab stylesheet is installed and themed"
pass "the XDG profile is found and the stylesheet installed"

# The pref without which Firefox never reads the file. Asserted because the
# stylesheet is inert without it and nothing would say so.
grep -q 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' "$PROFILE/user.js" \
  || fail "the pref that makes Firefox read userChrome.css was not set"
pass "the stylesheets pref is pinned"

# The base theme is pinned too. Left alone it is whatever the Add-ons Manager
# last had selected, and a coloured theme reimplements the same custom
# properties -- which is how the palette ended up applying to part of the
# browser and not the rest.
grep -q 'user_pref("extensions.activeThemeID", "default-theme@mozilla.org");' "$PROFILE/user.js" \
  || fail "the active theme is not pinned to the built-in default"
pass "the base theme is pinned so a coloured theme cannot half-apply"

grep -q 'my.own.pref' "$PROFILE/user.js" || fail "the user's own pref was dropped from user.js"
pass "the user's own prefs in user.js survive"

# The legacy location is still supported: an older profile, or one created before
# the move, must not be left unthemed.
LEGACY="$HOME/.mozilla/firefox/legacy.default-release"
rm -rf "$HOME/.config/mozilla/firefox" "$PROFILE"
mkdir -p "$LEGACY"
cat >"$HOME/.mozilla/firefox/profiles.ini" <<INI
[Install4F96D1932A9F858E]
Default=Profiles/legacy.default-release

[Profile1]
Name=default-release
IsRelative=1
Path=legacy.default-release
INI
step omarchy-theme-set-firefox
[[ -f $LEGACY/chrome/userChrome.css ]] || fail "a profile in the legacy location was not found"
pass "a legacy-location profile is found too"

# With no profile at all there is nothing to theme, and a theme switch should
# still succeed: Firefox has simply not been run yet.
rm -rf "$HOME/.mozilla" "$HOME/.config/mozilla"
out=$(bash "$ROOT/bin/omarchy-theme-set-firefox" 2>&1) \
  || fail "a missing firefox profile failed the switch: $out"
[[ -n $out ]] || fail "a missing firefox profile was reported silently"
pass "a machine with no firefox profile yet still switches cleanly"

# --- firefox: a hand-written stylesheet is kept ------------------------------

mkdir -p "$PROFILE" "$HOME/.config/mozilla/firefox"
cat >"$HOME/.config/mozilla/firefox/profiles.ini" <<INI
[Install4F96D1932A9F858E]
Default=Profiles/$PROFILE_REL

[Profile1]
Name=default-release
IsRelative=1
Path=$PROFILE_REL
INI
mkdir -p "$PROFILE/chrome"
printf '/* mine */\n' >"$PROFILE/chrome/userChrome.css"
step omarchy-theme-set-firefox
[[ -f $PROFILE/chrome/userChrome.css.omarchy-backup ]] || fail "a hand-written userChrome.css was overwritten without a backup"
grep -q 'mine' "$PROFILE/chrome/userChrome.css.omarchy-backup" || fail "the backup does not hold the original file"
# Not merely backed up: the rules have to still be in the live file, or taking
# the theme over would cost the user their own customisations.
grep -q 'mine' "$PROFILE/chrome/userChrome.css" || fail "the hand-written rules were dropped from the live stylesheet"
step omarchy-theme-set-firefox
[[ $(find "$PROFILE/chrome" -maxdepth 1 -name 'userChrome.css.omarchy-backup' | wc -l) -eq 1 ]] \
  || fail "re-applying made a second backup"
# The user's rules survive a second switch, and the managed block is not doubled.
[[ $(grep -c 'Fedarchy theme: managed block' "$PROFILE/chrome/userChrome.css") -eq 1 ]] \
  || fail "the managed block was duplicated on a re-run"
grep -q 'mine' "$PROFILE/chrome/userChrome.css" || fail "a re-run dropped the hand-written rules"
pass "a hand-written stylesheet is kept, backed up once, and still applied"

# An earlier release of this step wrote a different pair of markers. A file it
# produced therefore carries the old block *and* the new one, and the stale half
# keeps its own !important declarations. Because the newest wins, the page still
# looks correct -- so the duplication is invisible until you read the file, where
# every declaration appears twice and half of them belong to a theme that is no
# longer selected. The old markers have to be recognised and their block dropped.
printf '/* mine, keep me */\n' > "$PROFILE/chrome/userContent.css"
rm -f "$PROFILE/chrome/userContent.css.omarchy-backup"
cat >> "$PROFILE/chrome/userContent.css" <<'LEGACY'
/* --- Fedarchy theme: managed block, rewritten on every theme change --- */
:root:root { --newtab-background-color: #ff0000 !important; }
/* --- end Fedarchy managed block --- */
LEGACY
step omarchy-theme-set-firefox
[[ $(grep -c 'Fedarchy theme: managed block, rewritten' "$PROFILE/chrome/userContent.css") -eq 0 ]] \
  || fail "a stylesheet written by the previous marker format kept its stale block"
[[ $(grep -c '>>> Fedarchy theme: managed block' "$PROFILE/chrome/userContent.css") -eq 1 ]] \
  || fail "the current managed block was not written exactly once"
[[ $(grep -c '#ff0000' "$PROFILE/chrome/userContent.css") -eq 0 ]] \
  || fail "a stale declaration from the previous marker format survived"
[[ $(grep -c ':root:root' "$PROFILE/chrome/userContent.css") -eq 1 ]] \
  || fail "the stylesheet ended up with more than one block"
grep -q 'mine, keep me' "$PROFILE/chrome/userContent.css" \
  || fail "the user's own rules were dropped while normalising the markers"
pass "a stylesheet in the previous marker format is normalised to one block"


# Same guarantee for the newtab sheet: the user's own rules stay, and the managed
# block is replaced rather than appended to a second time.
printf '/* my newtab tweaks */\n' >"$PROFILE/chrome/userContent.css"
rm -f "$PROFILE/chrome/userContent.css.omarchy-backup"
step omarchy-theme-set-firefox
grep -q 'my newtab tweaks' "$PROFILE/chrome/userContent.css" \
  || fail "hand-written userContent.css rules were dropped"
[[ -f $PROFILE/chrome/userContent.css.omarchy-backup ]] \
  || fail "a hand-written userContent.css was not backed up"
step omarchy-theme-set-firefox
[[ $(grep -c 'Fedarchy theme: managed block' "$PROFILE/chrome/userContent.css") -eq 1 ]] \
  || fail "the newtab managed block was duplicated"
pass "a hand-written newtab stylesheet is kept and not doubled"

# A symlink into the theme cache is the arrangement this desktop already uses.
# It has to be written through, not replaced: renaming a temporary file onto a
# symlink swaps the link for a regular file and ends the arrangement.
rm -rf "$PROFILE/chrome"
mkdir -p "$TMP/cache"
printf '/* through a symlink */\n' >"$TMP/cache/firefox-userChrome.css"
mkdir -p "$PROFILE/chrome"
ln -s "$TMP/cache/firefox-userChrome.css" "$PROFILE/chrome/userChrome.css"
step omarchy-theme-set-firefox
[[ -L $PROFILE/chrome/userChrome.css ]] || fail "the symlink was replaced by a regular file"
grep -q '#101010' "$TMP/cache/firefox-userChrome.css" || fail "the symlink target was not written"
grep -q 'through a symlink' "$TMP/cache/firefox-userChrome.css" || fail "the rules behind the symlink were dropped"
pass "a stylesheet symlinked into the theme cache is written through, not replaced"

# --- switching back and forth leaves nothing behind --------------------------

snapshot() {
  md5sum "$PROFILE/chrome/userChrome.css" "$PROFILE/user.js" \
    "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css" \
    "$HOME/.config/gtk-4.0/settings.ini" 2>/dev/null | awk '{print $1}' | md5sum | cut -d' ' -f1
}

step omarchy-theme-set-gtk
step omarchy-theme-set-firefox
before=$(snapshot)
for _ in 1 2 3; do
  step omarchy-theme-set-gtk
  step omarchy-theme-set-firefox
done
after=$(snapshot)
[[ $before == "$after" ]] || fail "repeating a switch changed the installed files"
pass "repeating a switch on one theme changes nothing"

# The whole point of the pref rewrite: each switch must replace its own two
# lines, not add another pair underneath them.
for managed in toolkit.legacyUserProfileCustomizations extensions.activeThemeID ui.systemUsesDarkTheme; do
  [[ $(grep -c "$managed" "$PROFILE/user.js") -eq 1 ]] \
    || fail "the managed pref $managed is duplicated: $(grep -c "$managed" "$PROFILE/user.js") copies"
done
[[ $(grep -c 'Managed by omarchy-theme-set-firefox' "$PROFILE/user.js") -eq 1 ]] \
  || fail "the managed block is duplicated"
pass "the managed prefs are rewritten, never accumulated"

# A different theme has to actually change the output, or nothing above means
# anything.
stage_theme "#202020" "#e0e0e0" "#8bc34a"
step omarchy-theme-set-gtk
step omarchy-theme-set-firefox
grep -q '#202020' "$PROFILE/chrome/userChrome.css" || fail "firefox kept the previous theme's colours"
grep -q '#202020' "$HOME/.config/gtk-4.0/gtk.css" || fail "gtk-4.0 kept the previous theme's colours"
[[ $(snapshot) != "$before" ]] || fail "switching to a different theme changed nothing"
pass "a different theme reaches firefox and both gtk versions"

# And switching back returns to exactly where it started.
stage_theme "#101010" "#f0f0f0" "#7ab7d4"
step omarchy-theme-set-gtk
step omarchy-theme-set-firefox
[[ $(snapshot) == "$before" ]] || fail "switching back did not restore the previous state"
pass "switching back and forth settles on the same state"

# Temporary files are named by the install name plus six characters; a failure
# partway through leaves one behind, and the next switch would trip over it.
leftovers=$(find "$HOME/.config" -type f -regextype posix-extended -regex '.*\.[a-zA-Z0-9]{6}' 2>/dev/null | wc -l)
[[ $leftovers -eq 0 ]] || fail "$leftovers temporary file(s) were left behind"
pass "no temporary file is left behind"

# --- gtk: both toolkits, because the file manager is gtk 4 -------------------

stage_theme "#101010" "#f0f0f0" "#7ab7d4"
rm -rf "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
step omarchy-theme-set-gtk

for version in 3.0 4.0; do
  dir="$HOME/.config/gtk-$version"
  [[ -f $dir/gtk.css ]] || fail "gtk-$version was not written"
  grep -q '#101010' "$dir/gtk.css" || fail "gtk-$version does not carry the theme"
done
pass "both gtk-3.0 and gtk-4.0 are written"

# Text must not be painted in the accent. `link_color` and
# `visited_link_color` are named colours, so redefining them reaches every GTK
# application at once, and where a theme's `blue` is its accent -- gruvbox uses
# #7daea3 for both -- every link came out in the accent. Emphasis belongs on the
# decoration, not on the words.
for v in 3.0 4.0; do
  css="$HOME/.config/gtk-$v/gtk.css"
  fg=$(grep -m1 '^@define-color theme_fg_color' "$css" | awk '{print $3}')
  for role in link_color visited_link_color; do
    got=$(grep -m1 "^@define-color $role" "$css" | awk '{print $3}')
    [[ $got == "$fg" ]] || fail "gtk-$v $role is $got, not the text colour $fg"
  done
done
pass "link text uses the text colour, not the accent"

# ...while the accent stays on the things that are meant to be highlighted.
for v in 3.0 4.0; do
  css="$HOME/.config/gtk-$v/gtk.css"
  grep -q '^@define-color accent_color ' "$css" || fail "gtk-$v lost the accent colour"
  grep -q 'background-color: @accent_color' "$css" \
    || fail "gtk-$v lost the accent from the suggested-action background"
  grep -q 'outline-color: @accent_color' "$css" \
    || fail "gtk-$v lost the accent from the focus outline"
done
pass "the accent is still on buttons, outlines and selections"

# GTK 4 draws the window and the file view from its own theme rather than from
# a named colour, so a stylesheet that only covers the headerbar leaves the file
# manager looking themed on top and stock everywhere else.
grep -qE '^[[:space:]]*(view|iconview|listview)' "$HOME/.config/gtk-4.0/gtk.css" \
  || fail "gtk.css never styles the file view, so the file manager stays stock"
pass "the file view and window background are styled"

# GtkPopover is styled by the `popover` node but also receives the `.background`
# style class, so a bare `.background` rule paints every menu and popover over
# its whole allocated area with the window colour. That is the large rectangle
# of theme background that appeared over the Nautilus menus, and it is invisible
# to a style check that only asks whether the window itself is themed -- so it
# gets its own assertion.
for v in 3.0 4.0; do
  css="$HOME/.config/gtk-$v/gtk.css"
  if grep -qE '^[[:space:]]*\.background[[:space:]]*\{' "$css"; then
    fail "gtk-$v/gtk.css sets a bare .background background, which repaints every popover"
  fi
done
# The window must still be themed, or the fix above would have been a retreat
# rather than a correction.
grep -qE '^[[:space:]]*window(\.background)?[[:space:]]*[,{]' "$HOME/.config/gtk-4.0/gtk.css" \
  || fail "gtk.css no longer styles the window background"
pass "popovers are left alone while the window stays themed"

# --- starship follows the palette, and stays legible -------------------------

# The prompt is a small glyph on whatever background the terminal is using, so
# legibility is measurable rather than a matter of taste: the path and the error
# colour are text-like and must clear 4.5:1, the caret is a graphical object and
# must clear 3:1. Both floors are checked against the theme's own background.
stage_theme "#101010" "#f0f0f0" "#7ab7d4"
step omarchy-theme-set-starship
STARSHIP="$HOME/.config/starship.toml"
[[ -f $STARSHIP ]] || fail "the starship config was not written"
pass "the starship config is written"

python3 - "$STARSHIP" "#101010" <<'PYCHECK' || fail "a prompt colour is not legible against the background"
import re, sys

def lum(h):
    c = [int(h.lstrip("#")[i:i+2], 16) / 255 for i in (0, 2, 4)]
    c = [(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4) for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

text, bg = open(sys.argv[1]).read(), sys.argv[2]
path = re.search(r'^style = "(#[0-9a-fA-F]{6})"', text, re.M).group(1)
caret = re.search(r'success_symbol = "\[.*?\]\((#[0-9a-fA-F]{6})\)"', text).group(1)
err = re.search(r'error_symbol = "\[.*?\]\((#[0-9a-fA-F]{6})\)"', text).group(1)
for name, colour, floor in (("path", path, 4.5), ("caret", caret, 3.0), ("error", err, 4.5)):
    r = ratio(colour, bg)
    if r < floor:
        print(f"{name} {colour} is {r:.1f}:1 on {bg}, below {floor}:1", file=sys.stderr)
        sys.exit(1)
PYCHECK
pass "the prompt colours clear their contrast floors on the background"

# It has to actually follow the theme, or the above proves nothing.
stage_theme "#202020" "#e0e0e0" "#8bc34a"
step omarchy-theme-set-starship
grep -q '#e0e0e0' "$STARSHIP" || fail "the prompt did not take the new theme's foreground"
[[ $(snapshot) != "$before" ]] 2>/dev/null || true
pass "the prompt takes the new theme's colours"

# A hand-written config is kept rather than lost. The backup is taken on the
# first takeover only: re-taking it on every switch would overwrite the genuine
# original with whatever the last switch happened to generate, which is the one
# thing a backup must never do.
rm -f "$STARSHIP.omarchy-backup"
printf '# mine\n' >"$STARSHIP"
step omarchy-theme-set-starship
[[ -f $STARSHIP.omarchy-backup ]] || fail "a hand-written starship.toml was overwritten without a backup"
grep -q 'mine' "$STARSHIP.omarchy-backup" || fail "the backup does not hold the original file"
# A second takeover must leave that backup exactly as it was.
printf '# something else entirely\n' >"$STARSHIP"
step omarchy-theme-set-starship
grep -q 'mine' "$STARSHIP.omarchy-backup" \
  || fail "re-applying clobbered the backup of the original file"
grep -q 'something else' "$STARSHIP.omarchy-backup" \
  && fail "the backup was overwritten by a later switch"
pass "a hand-written starship config is backed up once and never clobbered"

# Re-running must not grow the file or duplicate anything.
stage_theme "#101010" "#f0f0f0" "#7ab7d4"
step omarchy-theme-set-starship
once=$(md5sum "$STARSHIP" | cut -d' ' -f1)
step omarchy-theme-set-starship
step omarchy-theme-set-starship
[[ $(md5sum "$STARSHIP" | cut -d' ' -f1) == "$once" ]] || fail "re-applying changed the starship config"
pass "re-applying the starship theme changes nothing"

# An existing key is replaced where it stands; the other settings are the user's.
printf '[Settings]\ngtk-font-name=Noto Sans, 10\ngtk-theme-name=stale-theme\n' \
  >"$HOME/.config/gtk-4.0/settings.ini"
step omarchy-theme-set-gtk
[[ $(grep -cE '^[[:space:]]*gtk-theme-name[[:space:]]*=' "$HOME/.config/gtk-4.0/settings.ini") -eq 1 ]] \
  || fail "the theme name key was duplicated"
grep -q 'adw-gtk3' "$HOME/.config/gtk-4.0/settings.ini" || fail "the stale theme name was not replaced"
grep -q 'gtk-font-name=Noto Sans, 10' "$HOME/.config/gtk-4.0/settings.ini" \
  || fail "an unrelated setting was lost"
pass "settings.ini gains the theme name and keeps everything else"

# Light and dark themes differ in more than colour.
stage_theme "#fafafa" "#101010" "#1565c0" light
step omarchy-theme-set-gtk
step omarchy-theme-set-firefox
grep -q 'gtk-theme-name=adw-gtk3$' "$HOME/.config/gtk-4.0/settings.ini" \
  || fail "a light theme did not select the light gtk theme"
grep -q 'user_pref("ui.systemUsesDarkTheme", false);' "$PROFILE/user.js" \
  || fail "a light theme did not tell firefox to follow"
stage_theme "#101010" "#f0f0f0" "#7ab7d4"
step omarchy-theme-set-gtk
step omarchy-theme-set-firefox
grep -q 'gtk-theme-name=adw-gtk3-dark' "$HOME/.config/gtk-4.0/settings.ini" \
  || fail "a dark theme did not select the dark gtk theme"
grep -q 'user_pref("ui.systemUsesDarkTheme", true);' "$PROFILE/user.js" \
  || fail "a dark theme did not tell firefox to follow"
pass "light and dark themes select the matching theme and firefox preference"

# --- a theme with no such payload is a no-op, not a failure -----------------

rm -rf "$CURRENT/theme"
for script in omarchy-theme-set-gtk omarchy-theme-set-firefox omarchy-theme-set-starship; do
  bash "$ROOT/bin/$script" >/dev/null || fail "$script failed when the theme had no payload for it"
done
pass "a theme without these payloads leaves the configs alone"

# --- the chromium step stays quiet when there is nothing to do ---------------

# With no Chromium-family browser there is no policy directory, and writing one
# would mean asking for a password in the middle of a theme switch. The step
# used to call the privileged writer regardless, which is what made every switch
# report a failure on a machine with no Chromium at all.
policy_dirs=0
for dir in /etc/chromium/policies/managed /etc/opt/chrome/policies/managed \
  /etc/opt/edge/policies/managed /etc/brave/policies/managed; do
  [[ -d $dir && ! -L $dir ]] && policy_dirs=1
done

if (( policy_dirs )); then
  echo "note - a chromium policy directory exists on this machine, skipping the no-op check"
else
  MARKER="$TMP/policy-called"
  MOCK="$TMP/bin"
  mkdir -p "$MOCK"
  printf '#!/bin/bash\ntouch "%s"\nexit 0\n' "$MARKER" >"$MOCK/omarchy-theme-set-browser-policy"
  printf '#!/bin/bash\nexit 0\n' >"$MOCK/omarchy-cmd-present"
  chmod +x "$MOCK"/*
  PATH="$MOCK:$PATH" bash "$ROOT/bin/omarchy-theme-set-browser" >/dev/null \
    || fail "the browser step failed with no chromium browser installed"
  [[ ! -e $MARKER ]] || fail "the browser step asked for root with no chromium policy directory to write"
  pass "the browser step does not touch the privileged policy writer for nothing"
fi
