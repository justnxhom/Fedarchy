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

for lua_file in \
  "$ROOT/default/hypr/autostart.lua" \
  "$ROOT/default/hypr/helpers.lua" \
  "$ROOT/default/hypr/bootstrap.lua"; do
  luac -p "$lua_file" || fail "Lua parse failed: $lua_file"
done

command lua - "$ROOT" <<'LUA'
local root = assert(arg[1])
local listeners = {}
local commands = {}

hl = {
  on = function(event, callback)
    table.insert(listeners, { event = event, callback = callback })
  end,
  exec_cmd = function(command)
    table.insert(commands, command)
  end,
}

dofile(root .. "/default/hypr/helpers.lua")
o.on_start("first")
o.on_start("first")
o.on_start_detached("background")
o.on_start("second")
o.dispatch_startup()

assert(#listeners == 1, "hyprland.start callback was registered more than once")
assert(listeners[1].event == "hyprland.start", "startup callback used the wrong event")
listeners[1].callback()
assert(#commands == 1, "startup event dispatched more than once")
assert(commands[1] == "first ; ( background >/dev/null 2>&1 & ) ; second", "startup order or detached execution changed")

dofile(root .. "/default/hypr/autostart.lua")
assert(#listeners == 1, "autostart registered a duplicate hyprland.start callback")
listeners[1].callback()
assert(#commands == 2, "autostart did not dispatch exactly once")
assert(commands[2]:find("printenv .* systemctl %-%-user import%-environment"), "environment import was not first")
assert(commands[2]:find("dbus%-update%-activation%-environment %-%-systemd %-%-all"), "activation environment update was not second")
local shell_step = commands[2]:find("omarchy%-launch%-shell")
assert(shell_step, "shell launch is missing from autostart")
assert(commands[2]:find("sleep 2 && omarchy%-hook post%-boot"), "post-boot hook is missing from autostart")
LUA

if command grep -ERn '(^|[[:space:]])(uwsm|uwsm-app)([[:space:]]|$)' \
  "$ROOT/scripts/install.sh" \
  "$ROOT/scripts/dev-run.sh" \
  "$ROOT/scripts/fedarchy-shell" \
  "$ROOT/bin/omarchy-launch-shell" \
  "$ROOT/bin/omarchy-restart-shell" \
  "$ROOT/bin/omarchy-system-logout" \
  "$ROOT/default/hypr/autostart.lua" \
  "$ROOT/default/hypr/helpers.lua" \
  "$ROOT/default/hypr/bootstrap.lua" \
  "$ROOT/default/wayland-sessions" \
  "$ROOT/default/sddm/omarchy/Main.qml"; then
  fail "executable UWSM dependency remains"
fi

pass "Hyprland startup is ordered, deduplicated, and free of executable UWSM dependencies"
