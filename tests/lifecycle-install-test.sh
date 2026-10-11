#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$*"
}

command -v rsync >/dev/null 2>&1 || fail "rsync is required"

export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
mkdir -p "$HOME"

unset OMARCHY_PATH
# --yes authorises the mutation: install refuses to run without an
# interactive terminal otherwise, and this suite is non-interactive.
"$ROOT/scripts/install.sh" --yes install >"$TMP/install.log" 2>&1 || {
  command cat "$TMP/install.log" >&2
  fail "installer failed with an isolated HOME"
}

TARGET="$XDG_DATA_HOME/fedarchy"
for path in \
  config/omarchy/shell.json \
  shell/shell.qml \
  bin/omarchy-launch-shell \
  bin/omarchy-restart-shell \
  default/hypr/bootstrap.lua \
  default/hypr/helpers.lua \
  default/hypr/autostart.lua \
  default/wayland-sessions/omarchy.desktop; do
  [[ -f "$TARGET/$path" ]] || fail "deployed layout is missing $path"
done

[[ -f "$XDG_CONFIG_HOME/omarchy/shell.json" ]] || fail "default user config was not installed"
cmp -s "$ROOT/config/omarchy/shell.json" "$XDG_CONFIG_HOME/omarchy/shell.json" || fail "installed user config has the wrong source"
[[ -x "$HOME/.local/bin/omarchy-launch-shell" ]] || fail "launcher was not installed into the fake HOME"
[[ $TARGET == "$HOME"/* ]] || fail "deployment escaped the isolated HOME"
[[ -f "$XDG_CONFIG_HOME/fedarchy/environment" ]] || fail "session environment was not installed"

"$ROOT/scripts/install.sh" check >"$TMP/check.log" 2>&1 || {
  command cat "$TMP/check.log" >&2
  fail "deployed layout failed the runtime contract"
}

pass "installer uses the real config source and consistent deployed layout"
