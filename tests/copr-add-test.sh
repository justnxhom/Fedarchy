#!/bin/bash

# omarchy-copr-add backend behaviour (no network, no sudo, no real dnf5).
#
# Two faults are pinned here, both of which made the script fail in ways a
# glance at the code would not reveal:
#
# 1. It lowercased the owner/name it was given. COPR project names are case
#    sensitive -- lionheartp/Hyprland is a real project and lionheartp/hyprland
#    is a 404 -- so lowercasing rewrote a valid slug into a nonexistent one.
#    The comment above that line claimed the opposite, which is how the mistake
#    survived review.
#
# 2. Its already-enabled check grepped repolist output for the slash form of the
#    slug. dnf5 reports repository ids colon-separated as
#    copr:<host>:<owner>:<name>, so the slash form never appears in that output
#    and the check could never succeed. Enabling an already-enabled repository
#    silently re-ran the enable instead of reporting it as done.
#
# dnf5, sudo and the update lock are all stubbed, so this asserts on the exact
# arguments the script would hand to dnf5.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MOCK="$TMP/mock"
mkdir -p "$MOCK"

ENABLE_LOG="$TMP/enable.log"

# --- dnf5 stub ---------------------------------------------------------------
# Only `repolist --enabled` is answered. The enabled set is deliberately built
# to exercise the shapes the old check mishandled: a plain project, and a name
# that is a prefix of another so that a substring match would be wrong.
cat > "$MOCK/dnf5" <<'DNEF5'
#!/bin/bash
if [[ ${1:-} == repolist ]]; then
  cat <<'ROPOS'
repo id                                            repo name
copr:copr.fedorainfracloud.org:atim:starship       Copr repo for starship owned by atim
copr:copr.fedorainfracloud.org:atim:spotify-tui    Copr repo for spotify-tui owned by atim
fedora                                             Fedora 44 - x86_64
ROPOS
  exit 0
fi
# Anything that reaches a real transaction would be a bug in a test context.
echo "UNEXPECTED dnf5 invocation: $*" >&2
exit 99
DNEF5

# --- sudo / lock stubs -------------------------------------------------------
# sudo records the command and returns success without executing anything, so
# the enable is observed but never performed.
cat > "$MOCK/sudo" <<SUDO
#!/bin/bash
printf '%s\n' "\$*" >> "$ENABLE_LOG"
exit 0
SUDO

cat > "$MOCK/omarchy-update-lock" <<'LOCK'
#!/bin/bash
shift
exec "$@"
LOCK

# copr-add sources this as a library, so it has to be valid bash.
printf '#!/bin/bash\ntrue\n' > "$MOCK/omarchy-sudo-keepalive"

chmod +x "$MOCK/dnf5" "$MOCK/sudo" "$MOCK/omarchy-update-lock" "$MOCK/omarchy-sudo-keepalive"
export PATH="$MOCK:$PATH"

[ -x "$ROOT/bin/omarchy-copr-add" ] || { echo "omarchy-copr-add is not executable"; exit 1; }

# --- case is preserved -------------------------------------------------------
echo "== a mixed-case slug reaches dnf5 unchanged =="
: > "$ENABLE_LOG"
bash "$ROOT/bin/omarchy-copr-add" 'lionheartp/Hyprland' >/dev/null
grep -qxF 'dnf5 copr enable -y lionheartp/Hyprland' "$ENABLE_LOG" ||
  { echo "mixed-case slug was altered before reaching dnf5:"; cat "$ENABLE_LOG"; exit 1; }

echo "== an already-lowercase slug is left alone =="
: > "$ENABLE_LOG"
bash "$ROOT/bin/omarchy-copr-add" 'atim/lazydocker' >/dev/null
grep -qxF 'dnf5 copr enable -y atim/lazydocker' "$ENABLE_LOG" ||
  { echo "lowercase slug was altered:"; cat "$ENABLE_LOG"; exit 1; }

echo "== -y is passed so the enable cannot stop for a prompt =="
grep -q 'copr enable -y ' "$ENABLE_LOG" || { echo "enable ran without -y"; exit 1; }

# --- already-enabled detection ----------------------------------------------
echo "== an already-enabled repository is reported, not re-enabled =="
: > "$ENABLE_LOG"
output=$(bash "$ROOT/bin/omarchy-copr-add" 'atim/starship')
grep -q 'already enabled' <<<"$output" || { echo "enabled repo not detected: $output"; exit 1; }
[[ ! -s $ENABLE_LOG ]] || { echo "an already-enabled repo was enabled again"; exit 1; }

echo "== detection matches the whole name, not a prefix of it =="
# atim/starship-extra is not in the enabled set. A substring match against the
# enabled atim/starship would wrongly claim it was already there.
: > "$ENABLE_LOG"
output=$(bash "$ROOT/bin/omarchy-copr-add" 'atim/starship-extra')
grep -q 'already enabled' <<<"$output" && { echo "prefix collision treated as already enabled"; exit 1; }
grep -qxF 'dnf5 copr enable -y atim/starship-extra' "$ENABLE_LOG" ||
  { echo "genuinely-absent repository was not enabled:"; cat "$ENABLE_LOG"; exit 1; }

echo "== a hyphenated name that is enabled is detected too =="
: > "$ENABLE_LOG"
output=$(bash "$ROOT/bin/omarchy-copr-add" 'atim/spotify-tui')
grep -q 'already enabled' <<<"$output" || { echo "enabled hyphenated repo not detected: $output"; exit 1; }
[[ ! -s $ENABLE_LOG ]] || { echo "enabled hyphenated repo was enabled again"; exit 1; }

# --- malformed input ---------------------------------------------------------
echo "== malformed owner/name is refused before dnf5 =="
for bad in 'atim' 'atim/star ship' 'atim/../../etc/passwd' 'atim/starship;rm -rf /' 'a/b/c'; do
  : > "$ENABLE_LOG"
  if bash "$ROOT/bin/omarchy-copr-add" "$bad" >/dev/null 2>&1; then
    echo "invalid input accepted: $bad"; exit 1
  fi
  [[ ! -s $ENABLE_LOG ]] || { echo "invalid input reached dnf5: $bad"; exit 1; }
done

echo "all copr add tests passed"
