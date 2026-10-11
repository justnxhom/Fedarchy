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

MOCK="$TMP/mock"
RUNTIME="$TMP/runtime"
mkdir -p "$MOCK" "$RUNTIME/fedarchy/shell"
: >"$MOCK/calls"
: >"$RUNTIME/fedarchy/shell/shell.qml"

command cat >"$MOCK/quickshell" <<'MOCK'
#!/bin/bash
if [[ ${1:-} == kill ]]; then
  exit 1
fi
if [[ ${1:-} == -p && ${3:-} == --ping ]]; then
  [[ ${MOCK_QUICKSHELL_STATUS:-0} == 0 ]]
  exit
fi
printf 'quickshell %s\n' "$*" >>"$MOCK/calls"
[[ ! -e /proc/$$/fd/9 ]] || exit 90
exec sleep 30
MOCK
command cat >"$MOCK/systemd-cat" <<'MOCK'
#!/bin/bash
while [[ ${1:-} != -- ]]; do shift; done
shift
printf 'systemd-cat %s\n' "$*" >>"$MOCK/calls"
exec "$@"
MOCK
command cat >"$MOCK/logger" <<'MOCK'
#!/bin/bash
exit 0
MOCK
command cat >"$MOCK/hyprctl" <<'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$MOCK"/*

export MOCK="$MOCK"
export MOCK_QUICKSHELL_STATUS=0
export OMARCHY_PATH="$RUNTIME/fedarchy"
export OMARCHY_SHELL_RUNTIME_DIR="$RUNTIME/locks"
export PATH="$MOCK:/usr/bin:/bin"

"$ROOT/bin/omarchy-launch-shell" >"$TMP/first.log" 2>&1 &
launcher_pid=$!
for _ in {1..50}; do
  command grep -q '^quickshell -n -p' "$MOCK/calls" 2>/dev/null && break
  kill -0 "$launcher_pid" 2>/dev/null || break
  sleep 0.05
done
command grep -q '^systemd-cat .*quickshell -n -p' "$MOCK/calls" || fail "launcher did not execute through systemd-cat"

duplicate_output=$("$ROOT/bin/omarchy-launch-shell" 2>&1) || fail "duplicate launcher did not exit successfully"
[[ $duplicate_output == *"already supervises"* ]] || fail "duplicate launcher did not explain why it did not start"
[[ $(command grep -c '^quickshell -n -p' "$MOCK/calls") == 1 ]] || fail "duplicate launcher started a second engine"

kill -TERM "$launcher_pid"
wait "$launcher_pid" || fail "singleton launcher did not stop truthfully"
pass "launcher holds one singleton lock and starts directly through systemd"

exec 7>"$OMARCHY_SHELL_RUNTIME_DIR/restart.lock"
flock -n 7 || fail "restart lock test could not acquire the lock"
touch "$RUNTIME/ready"

: >"$MOCK/systemctl"
command cat >"$MOCK/systemctl" <<'MOCK'
#!/bin/bash
if [[ ${1:-} == --user && ${2:-} == show-environment ]]; then
  printf 'OMARCHY_PATH=%s\n' "$OMARCHY_PATH"
  exit 0
fi
exit 0
MOCK
command cat >"$MOCK/omarchy-hyprland-session-locked" <<'MOCK'
#!/bin/bash
exit 1
MOCK
command cat >"$MOCK/omarchy-shell" <<'MOCK'
#!/bin/bash
exit 0
MOCK
command cat >"$MOCK/hyprctl" <<'MOCK'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$MOCK/calls"
exit "${MOCK_HYPRCTL_STATUS:-0}"
MOCK
chmod +x "$MOCK/systemctl" "$MOCK/omarchy-hyprland-session-locked" "$MOCK/omarchy-shell" "$MOCK/hyprctl"

restart_output=$("$ROOT/bin/omarchy-restart-shell" 2>&1) || fail "concurrent restart did not exit idempotently"
[[ $restart_output == *"already in progress"* ]] || fail "concurrent restart did not report lock contention"
command grep -q '^hyprctl dispatch' "$MOCK/calls" && fail "concurrent restart reached Hyprland"
exec 7>&-

MOCK_HYPRCTL_STATUS=1 "$ROOT/bin/omarchy-restart-shell" >"$TMP/restart-failure.log" 2>&1 && fail "restart claimed success when Hyprland refused dispatch"
command grep -q 'Hyprland refused to dispatch' "$TMP/restart-failure.log" || fail "restart failure was not truthful"
pass "restart lock serializes work and dispatch failure remains nonzero"

export HOME="$TMP/home"
export XDG_RUNTIME_DIR="$TMP/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
"$ROOT/scripts/dev-run.sh" --test-arg >"$TMP/dev-run.log" 2>&1 || fail "development launcher failed"
command grep -q -- '--test-arg' "$MOCK/calls" || fail "development launcher did not forward arguments"

MOCK_QUICKSHELL_STATUS=0 status_output=$("$ROOT/scripts/fedarchy-shell" status) || fail "status did not report a running shell"
[[ $status_output == *"Status:   running"* ]] || fail "running status was not reported"
if MOCK_QUICKSHELL_STATUS=1 "$ROOT/scripts/fedarchy-shell" status >"$TMP/status-down.log" 2>&1; then
  fail "status returned success for a stopped shell"
fi
[[ $(command grep -c 'Status:   not running' "$TMP/status-down.log") == 1 ]] || fail "stopped status was not reported"

command cat >"$MOCK/journalctl" <<'MOCK'
#!/bin/bash
printf 'journalctl %s\n' "$*" >>"$MOCK/calls"
printf 'mock lifecycle log\n'
MOCK
chmod +x "$MOCK/journalctl"
log_output=$("$ROOT/scripts/fedarchy-shell" log) || fail "log command failed"
[[ $log_output == "mock lifecycle log" ]] || fail "journal log output was not returned"
command grep -q -- '-t fedarchy-dev-shell' "$MOCK/calls" || fail "log command did not use the development journal tag"
pass "development status and journal log reflect mocked runtime state"

command cat >"$MOCK/sleep" <<'MOCK'
#!/bin/bash
exit 0
MOCK
command cat >"$MOCK/omarchy-osd" <<'MOCK'
#!/bin/bash
exit 0
MOCK
command cat >"$MOCK/omarchy-hyprland-window-close-all" <<'MOCK'
#!/bin/bash
exit 0
MOCK
command cat >"$MOCK/hyprctl" <<'MOCK'
#!/bin/bash
printf 'logout %s\n' "$*" >>"$MOCK/calls"
exit "${MOCK_LOGOUT_STATUS:-0}"
MOCK
chmod +x "$MOCK/sleep" "$MOCK/omarchy-osd" "$MOCK/omarchy-hyprland-window-close-all" "$MOCK/hyprctl"
MOCK_LOGOUT_STATUS=1 "$ROOT/bin/omarchy-system-logout" >"$TMP/logout.log" 2>&1 && fail "logout claimed success when Hyprland failed"
command grep -q '^logout dispatch exit' "$MOCK/calls" || fail "logout dispatch was not mocked"
pass "logout propagates the mocked Hyprland result"
