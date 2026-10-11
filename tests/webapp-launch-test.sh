#!/bin/bash
# omarchy-launch-webapp resolves the browser the user actually has, and opens the
# URL where it belongs.
#
# Two separate bugs lived here.
#
# First, it matched the default browser against a list of Chromium-family desktop
# file names and substituted chromium.desktop for anything else. Firefox's entry is
# named after its reverse-DNS id -- org.mozilla.firefox.desktop -- so it never
# matched, every URL became chromium.desktop, that file does not exist on a machine
# with Firefox, and the Exec line read out of a missing file left an empty command.
# The launch degraded to `setsid --app=<url>`, which setsid rejects as an unknown
# option. Nothing was printed, so every documentation link in the menu just did
# nothing.
#
# Second, once that was fixed the links still misbehaved: --app requests a
# chromeless application window, which Firefox opens even when one is already
# running. Every Learn link arrived as its own bare window instead of a tab in the
# browser you were already using. A tab when an instance is up, a window when there
# is not, is the behaviour wanted -- and --new-tab is passed explicitly rather than
# relying on Firefox's own preference, which can be set to open new windows.
#
# The browser, the desktop-entry lookup and the idle check are all stubbed, so this
# never opens a window.
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
APPS="$TMP/applications"
XDG_APPS="$TMP/xdgapplications"
mkdir -p "$MOCK" "$APPS" "$XDG_APPS"

export PATH="$MOCK:$PATH"
export XDG_DATA_HOME="$TMP/xdgdata"
mkdir -p "$XDG_DATA_HOME/applications"

export LAUNCH_LOG="$TMP/launch.log"

# Records what it was asked to run, and pretends to be a real executable.
make_browser() {
  local name="$1"
  cat >"$MOCK/$name" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$LAUNCH_LOG"
STUB
  chmod +x "$MOCK/$name"
}

# Reports whatever desktop id the test is currently pretending the default is,
# which is what "xdg-settings get default-web-browser" answers with.
make_xdg_settings() {
  local id="$1"
  cat >"$MOCK/xdg-settings" <<STUB
#!/bin/bash
printf '%s\n' "$id"
STUB
  chmod +x "$MOCK/xdg-settings"
}

# Hyprland reports no windows by default; the tests that care stub their own.
cat >"$MOCK/hyprctl" <<'STUB'
#!/bin/bash
if [[ $1 == clients ]]; then
  [[ -n $FAKE_CLIENTS ]] && printf '%s' "$FAKE_CLIENTS"
  exit 0
fi
exit 1
STUB
chmod +x "$MOCK/hyprctl"

# pgrep is stubbed too, and this matters: the fallback in browser_running is
# `pgrep -f <name>`, which on a real desktop matches the user's own browser. Left
# unstubbed, whether this test claims Firefox is running depends on whether
# Firefox happens to be open when it runs.
cat >"$MOCK/pgrep" <<'STUB'
#!/bin/bash
[[ -n $FAKE_PGREP_MATCH ]] && exit 0
exit 1
STUB
chmod +x "$MOCK/pgrep"

export FAKE_CLIENTS="" FAKE_PGREP_MATCH=""
make_xdg_settings "org.mozilla.firefox.desktop"
cat >"$XDG_APPS/firefox.desktop" <<'DESK'
[Desktop Entry]
Name=Firefox
Exec=firefox %u
DESK
cp "$XDG_APPS/firefox.desktop" "$XDG_DATA_HOME/applications/org.mozilla.firefox.desktop"
make_browser firefox

# --- already running: a tab, not a second window ------------------------------

: >"$LAUNCH_LOG"
export FAKE_CLIENTS='[{"class":"org.mozilla.firefox"}]'
export FAKE_PGREP_MATCH=1
bash "$ROOT/bin/omarchy-launch-webapp" 'https://wiki.hypr.land/' >/dev/null 2>&1 || true

grep -q -- '--new-tab' "$LAUNCH_LOG" \
  || fail "firefox was not given --new-tab while an instance was running: $(cat "$LAUNCH_LOG")"
grep -q -- 'https://wiki.hypr.land/' "$LAUNCH_LOG" \
  || fail "the url was not passed to firefox: $(cat "$LAUNCH_LOG")"
# The regression itself: --app asks for a chromeless window regardless of whether
# one is already open, which is what produced a bare window per link.
grep -q -- '--app' "$LAUNCH_LOG" \
  && fail "firefox was still launched with --app, which opens a separate window"
pass "an already-running firefox gets a tab in the existing window"

# --- not running: a window of its own ----------------------------------------

: >"$LAUNCH_LOG"
unset FAKE_CLIENTS
unset FAKE_PGREP_MATCH
bash "$ROOT/bin/omarchy-launch-webapp" 'https://wiki.hypr.land/' >/dev/null 2>&1 || true

grep -q -- 'https://wiki.hypr.land/' "$LAUNCH_LOG" \
  || fail "the url was not passed to firefox: $(cat "$LAUNCH_LOG")"
# With no instance up there is no tab to open, and --new-tab against a browser
# that is not running is at best ignored and at worst refused.
grep -q -- '--new-tab' "$LAUNCH_LOG" \
  && fail "--new-tab was passed with no firefox running: $(cat "$LAUNCH_LOG")"
pass "with no firefox running the url opens a window"

# --- an Exec line with arguments and field codes ------------------------------

: >"$LAUNCH_LOG"
make_browser chromium
cat >"$XDG_DATA_HOME/applications/org.mozilla.firefox.desktop" <<DESK
[Desktop Entry]
Name=Thing
Exec=$MOCK/chromium-stable --profile-directory=Default %U
DESK
cp "$MOCK/chromium" "$MOCK/chromium-stable"
chmod +x "$MOCK/chromium-stable"

bash "$ROOT/bin/omarchy-launch-webapp" 'https://omarchy.org/manual/' >/dev/null 2>&1 || true
grep -q -- 'https://omarchy.org/manual/' "$LAUNCH_LOG" \
  || fail "an Exec line with arguments did not resolve: $(cat "$LAUNCH_LOG")"
# The %U field code must not be passed through as a literal argument.
grep -q '%U' "$LAUNCH_LOG" && fail "a desktop field code was passed to the browser as an argument"
pass "an Exec line with arguments and field codes is handled"

# --- no resolvable browser falls back to xdg-open ----------------------------

: >"$LAUNCH_LOG"
cat >"$MOCK/xdg-open" <<'STUB'
#!/bin/bash
printf 'xdg-open %s\n' "$*" >>"$LAUNCH_LOG"
STUB
chmod +x "$MOCK/xdg-open"
# An id that does not exist on disk at all.
make_xdg_settings "nonexistent.desktop"

bash "$ROOT/bin/omarchy-launch-webapp" 'https://example.com/' >/dev/null 2>&1 || true
grep -q 'xdg-open https://example.com/' "$LAUNCH_LOG" \
  || fail "an unresolvable browser did not fall back to xdg-open: $(cat "$LAUNCH_LOG")"
pass "an unresolvable browser falls back to xdg-open instead of failing silently"

# --- no residual dependency on the missing command ----------------------------

if grep -qE '\$\(xdg-terminal-exec|\$\(xdg-terminal-exec --print-id\)' "$ROOT/bin/omarchy-launch-webapp"; then
  fail "the script still captures xdg-terminal-exec output"
fi
pass "no unguarded xdg-terminal-exec capture remains"

# --- a non-URL argument is refused --------------------------------------------

if bash "$ROOT/bin/omarchy-launch-webapp" 'not a url' >/dev/null 2>&1; then
  fail "a non-URL argument was accepted"
fi
pass "a non-URL argument is refused"

echo ""
echo "all webapp launch checks passed"