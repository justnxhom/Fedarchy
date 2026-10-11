#!/bin/bash

# Workspace layout selection and the lock fallback (no real Hyprland, no sudo).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MOCK="$TMP/mock"
mkdir -p "$MOCK"

# Redirect HOME before anything below resolves a user path. This suite writes
# and deletes real layout rules under ~/.local/state, so running it against the
# developer's live state directory would both read and clobber actual user
# configuration. The lock sections further down sandbox PATH independently.
export HOME="$TMP/home"
export XDG_STATE_HOME="$HOME/.local/state"
mkdir -p "$XDG_STATE_HOME/omarchy/workspace-layouts"

fail() { echo "FAILED: $*" >&2; exit 1; }

# --- layout mocks -------------------------------------------------------
# ACTIVE_WS is the workspace the fake Hyprland reports as active, and
# FAKE_STATE holds the layout it currently has. Applying a rule updates it.
cat > "$MOCK/hyprctl" <<'HYP'
#!/bin/bash
printf '%s\n' "$*" >> "$HYP_LOG"
state_file="$FAKE_STATE"
last_rule=""

case "$1" in
  activeworkspace)
    printf '{"id": %s}\n' "$FAKE_WS"
    exit 0
    ;;
  workspaces)
    current=$(cat "$state_file" 2>/dev/null || echo dwindle)
    printf '[{"id": %s, "tiledLayout": "%s"}]\n' "$FAKE_WS" "$current"
    exit 0
    ;;
  eval)
    rule="$2"
    for layout in dwindle master scrolling; do
      if [[ $rule == *"layout = \"$layout\""* ]]; then
        printf '%s' "$layout" > "$state_file"
      fi
    done
    exit 0
    ;;
esac

case "$*" in
  *notification*) exit 0 ;;
esac
exit 0
HYP

cat > "$MOCK/omarchy-notification-send" <<'NOTIFY'
#!/bin/bash
printf '%s\n' "$*" > "$NOTIFY_LOG"
NOTIFY

chmod +x "$MOCK"/*
export PATH="$MOCK:$ROOT/bin:$PATH"
export HYP_LOG="$TMP/hypr.log"
export NOTIFY_LOG="$TMP/notify.log"
export FAKE_WS=3
export FAKE_STATE="$TMP/layout.state"
printf 'dwindle' > "$FAKE_STATE"

layouts_dir="$HOME/.local/state/omarchy/workspace-layouts"
rm -f "$layouts_dir/3.lua"

echo "== set each layout =="
for layout in master scrolling dwindle; do
  bash "$ROOT/bin/omarchy-hyprland-workspace-layout" "$layout" >/dev/null
  [[ $(cat "$FAKE_STATE") == "$layout" ]] || fail "$layout was not applied"
  grep -Fq "layout = \"$layout\"" "$layouts_dir/3.lua" || fail "$layout was not persisted"
done

echo "== unknown layout is rejected =="
bash "$ROOT/bin/omarchy-hyprland-workspace-layout" nonsense 2>/dev/null && fail "invalid layout accepted"
printf 'dwindle' > "$FAKE_STATE"
before=$(cat "$layouts_dir/3.lua")
bash "$ROOT/bin/omarchy-hyprland-workspace-layout" bogus 2>/dev/null || true
[[ $(cat "$layouts_dir/3.lua") == "$before" ]] || fail "invalid layout overwrote the saved rule"

echo "== missing argument is rejected =="
bash "$ROOT/bin/omarchy-hyprland-workspace-layout" 2>/dev/null && fail "missing argument accepted"

echo "== toggle cycles dwindle -> master -> scrolling -> dwindle =="
printf 'dwindle' > "$FAKE_STATE"
expected=(master scrolling dwindle)
for want in "${expected[@]}"; do
  bash "$ROOT/bin/omarchy-hyprland-workspace-layout-toggle" >/dev/null
  [[ $(cat "$FAKE_STATE") == "$want" ]] || fail "expected $want, got $(cat "$FAKE_STATE")"
done

echo "== toggle recovers from an unknown layout =="
printf 'somethingelse' > "$FAKE_STATE"
bash "$ROOT/bin/omarchy-hyprland-workspace-layout-toggle" >/dev/null
[[ $(cat "$FAKE_STATE") == "dwindle" ]] || fail "unknown layout did not restart the cycle"

echo "== lock falls back to hyprlock when the shell refuses =="
# The lock tests must never be able to reach the real hyprlock: a lockscreen
# that grabs the session and then dies leaves Hyprland showing the crashed
# lockscreen overlay. Sandbox PATH for every lock invocation.
LOCKBIN="$TMP/lockbin"
mkdir -p "$LOCKBIN"
for tool in bash sh pgrep pkill pidwait timeout flock tr cat rm sleep date; do
  target=$(command -v "$tool" 2>/dev/null) && ln -sf "$target" "$LOCKBIN/$tool"
done

# Guard: prove the sandbox cannot see any real hyprlock before running anything.
rm -f "$MOCK/hyprlock"
if PATH="$MOCK:$LOCKBIN" command -v hyprlock >/dev/null 2>&1; then
  fail "sandbox PATH still reaches a real hyprlock"
fi

cat > "$MOCK/omarchy-shell" <<'SHELL'
#!/bin/bash
[[ $1 == lock && $2 == lock ]] && { echo "missing-pam"; exit 0; }
exit 0
SHELL
cat > "$MOCK/hyprlock" <<'LOCK'
#!/bin/bash
# A real lockscreen stays running for as long as the session is locked.
printf 'locked\n' >> "$LOCK_LOG"
echo $$ > "$LOCK_PID_FILE"
exec sleep 30
LOCK
cat > "$MOCK/setsid" <<'SETSID'
#!/bin/bash
exec "$@"
SETSID
chmod +x "$MOCK/omarchy-shell" "$MOCK/hyprlock" "$MOCK/setsid"
export LOCK_LOG="$TMP/hyprlock.log"
export LOCK_PID_FILE="$TMP/hyprlock.pid"

PATH="$MOCK:$LOCKBIN" bash "$ROOT/bin/omarchy-system-lock" >/dev/null 2>&1 || fail "lock script exited non-zero"
[[ -s $LOCK_LOG ]] || fail "hyprlock fallback was not used"
grep -q "omarchy-apply-lock" "$NOTIFY_LOG" || fail "no hint about fixing the shell lock screen"

echo "== lock reports failure when nothing can lock =="
rm -f "$MOCK/hyprlock"
: > "$NOTIFY_LOG"
PATH="$MOCK:$LOCKBIN" bash "$ROOT/bin/omarchy-system-lock" 2>/dev/null && fail "lock succeeded with no way to lock"
grep -q "Cannot lock" "$NOTIFY_LOG" || fail "no failure notification"

echo "== a hyprlock that dies is reported and cleaned up =="
cat > "$MOCK/hyprlock" <<'LOCK'
#!/bin/bash
# Grabs the session then exits immediately, like a misconfigured lockscreen.
printf 'grabbed-then-died\n' >> "$HYPER_LOG"
exit 1
LOCK
cat > "$MOCK/omarchy-shell" <<'SHELL'
#!/bin/bash
[[ $1 == lock && $2 == lock ]] && { echo "missing-pam"; exit 0; }
exit 0
SHELL
chmod +x "$MOCK/hyprlock" "$MOCK/omarchy-shell"
export HYPER_LOG="$TMP/dead-hyprlock.log"
: > "$HYPER_LOG"
: > "$NOTIFY_LOG"
PATH="$MOCK:$LOCKBIN" bash "$ROOT/bin/omarchy-system-lock" 2>/dev/null && fail "lock reported success after hyprlock died"
grep -q "clear_crashed_lockscreen" "$HYP_LOG" || fail "stale lockscreen overlay was not cleared"
grep -q "Lock failed" "$NOTIFY_LOG" || fail "no failure notification for a dead lockscreen"

echo "== lock uses the shell lock screen when it works =="
cat > "$MOCK/omarchy-shell" <<'SHELL'
#!/bin/bash
[[ $1 == lock && $2 == lock ]] && { echo "ok"; exit 0; }
exit 0
SHELL
cat > "$MOCK/hyprlock" <<'LOCK'
#!/bin/bash
printf 'locked\n' >> "$LOCK_LOG"
echo $$ > "$LOCK_PID_FILE"
exec sleep 30
LOCK
chmod +x "$MOCK/omarchy-shell" "$MOCK/hyprlock"
: > "$LOCK_LOG"
PATH="$MOCK:$LOCKBIN" bash "$ROOT/bin/omarchy-system-lock" >/dev/null 2>&1
[[ ! -s $LOCK_LOG ]] || fail "hyprlock used even though the shell lock screen worked"

# Stop the mock lockscreens this test started, by recorded pid only.
[[ -f $LOCK_PID_FILE ]] && kill "$(cat "$LOCK_PID_FILE")" 2>/dev/null
rm -f "$layouts_dir/3.lua"
echo "all workspace layout tests passed"
