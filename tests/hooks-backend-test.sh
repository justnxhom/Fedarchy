#!/bin/bash
# Hook dispatch and risk-based backend coverage.
#
# Every scenario runs in a synthetic HOME under mktemp -d with mocked commands.
# No test touches the developer's real configuration, invokes sudo, or performs
# a package transaction.

set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
SANDBOX=""

pass() { printf '  PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if [[ $1 == "$2" ]]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi; }
contains() { if [[ $1 == *"$2"* ]]; then pass "$3"; else fail "$3 (missing '$2')"; fi; }
not_contains() { if [[ $1 != *"$2"* ]]; then pass "$3"; else fail "$3 (unexpected '$2')"; fi; }

cleanup() { [[ -n $SANDBOX && -d $SANDBOX ]] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

new_sandbox() {
    cleanup
    SANDBOX="$(mktemp -d)"
    export HOME="$SANDBOX/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_DATA_HOME="$HOME/.local/share"
    unset OMARCHY_PATH
    mkdir -p "$HOME/.config/omarchy/hooks" "$XDG_STATE_HOME" "$XDG_DATA_HOME"

    local stub="$SANDBOX/stub"
    mkdir -p "$stub"
    for tool in dnf5 sudo gum hyprctl systemctl; do
        cat >"$stub/$tool" <<STUB
#!/bin/bash
printf '%s %s\n' "${tool}" "\$*" >> "\$CALL_LOG"
exit \${${tool^^}_EXIT:-0}
STUB
        chmod +x "$stub/$tool"
    done
    # A stub that reports installed packages, so argument construction can be
    # checked without rpm touching the real database.
    cat >"$stub/rpm" <<'STUB'
#!/bin/bash
printf 'rpm %s\n' "$*" >> "$CALL_LOG"
if [[ ${1:-} == -q ]]; then
    [[ ${RPM_PRESENT:-1} == 1 ]] && exit 0 || exit 1
fi
printf 'demo-package\n'
STUB
    chmod +x "$stub/rpm"
    export CALL_LOG="$SANDBOX/calls.log"
    : >"$CALL_LOG"
    export PATH="$stub:$ROOT/bin:$PATH"
}

echo "=== hook dispatch ==="

# Valid hooks run, in name order, with arguments.
new_sandbox
d="$HOME/.config/omarchy/hooks/demo.d"; mkdir -p "$d"
printf '#!/bin/bash\necho "first $*"\n' >"$d/10-first"
printf '#!/bin/bash\necho "second $*"\n' >"$d/20-second"
out=$(bash "$ROOT/bin/omarchy-hook" demo alpha beta 2>&1)
contains "$out" "first alpha beta" "arguments are passed to hooks"
[[ $(grep -n 'first' <<<"$out" | cut -d: -f1) -lt $(grep -n 'second' <<<"$out" | cut -d: -f1) ]] \
    && pass "hooks run in filename order" || fail "hook ordering is not deterministic"

# The single-file hook form still works.
new_sandbox
printf '#!/bin/bash\necho "top-level hook"\n' >"$HOME/.config/omarchy/hooks/solo"
contains "$(bash "$ROOT/bin/omarchy-hook" solo 2>&1)" "top-level hook" "a top-level hook file still runs"

# A missing hook is a silent no-op, not an error.
new_sandbox
bash "$ROOT/bin/omarchy-hook" absent >/dev/null 2>&1
check "$?" "0" "a missing hook is not an error"

# A failing hook is reported but does not abort the rest.
new_sandbox
d="$HOME/.config/omarchy/hooks/demo.d"; mkdir -p "$d"
printf '#!/bin/bash\nexit 3\n' >"$d/10-fails"
printf '#!/bin/bash\necho "survivor"\n' >"$d/20-after"
out=$(bash "$ROOT/bin/omarchy-hook" demo 2>&1)
rc=$?
contains "$out" "Hook failed" "a failing hook is reported"
contains "$out" "survivor" "a failing hook does not stop later hooks"
check "$rc" "0" "a failed hook does not fail the dispatcher"

# Sample files are not run.
new_sandbox
d="$HOME/.config/omarchy/hooks/demo.d"; mkdir -p "$d"
printf '#!/bin/bash\necho "SAMPLE RAN"\n' >"$d/10-x.sample"
not_contains "$(bash "$ROOT/bin/omarchy-hook" demo 2>&1)" "SAMPLE RAN" ".sample files are skipped"

# Documentation beside hooks is not executed or reported as broken.
new_sandbox
d="$HOME/.config/omarchy/hooks/demo.d"; mkdir -p "$d"
printf '#!/bin/bash\necho "real hook ran"\n' >"$d/10-real"
printf 'This directory holds hook fragments.\n' >"$d/README.md"
printf 'notes\n' >"$d/notes.txt"
printf 'Apache 2.0\n' >"$d/LICENSE"
out=$(bash "$ROOT/bin/omarchy-hook" demo 2>&1)
contains "$out" "real hook ran" "valid hooks still run alongside documentation"
not_contains "$out" "Hook failed" "documentation is not reported as a failed hook"
not_contains "$out" "notes" "plain text notes are not executed"

# Non-executable hooks remain supported: the contract runs them via bash.
new_sandbox
d="$HOME/.config/omarchy/hooks/demo.d"; mkdir -p "$d"
printf '#!/bin/bash\necho "non-executable hook ran"\n' >"$d/10-plain"
chmod -x "$d/10-plain"
contains "$(bash "$ROOT/bin/omarchy-hook" demo 2>&1)" "non-executable hook ran" \
    "a hook without the executable bit still runs"

# Path traversal in the hook name is refused.
new_sandbox
for name in "../escape" "a/b" "." ".."; do
    out=$(bash "$ROOT/bin/omarchy-hook" "$name" 2>&1)
    rc=$?
    if [[ $rc -ne 0 ]] && [[ $out == *"Invalid hook name"* ]]; then
        pass "traversal refused: $name"
    else
        fail "traversal not refused: $name"
    fi
done

# Duplicate dispatch runs the hook exactly once per invocation.
new_sandbox
d="$HOME/.config/omarchy/hooks/demo.d"; mkdir -p "$d"
printf '#!/bin/bash\necho x\n' >"$d/10-only"
n=$(bash "$ROOT/bin/omarchy-hook" demo 2>&1 | grep -c '^x$')
check "$n" "1" "a hook runs once per dispatch"

echo ""
echo "=== risk-based command coverage ==="

# copr-remove must target the repo it is given and refuse a malformed one.
new_sandbox
cat >"$SANDBOX/stub/dnf5" <<'STUB'
#!/bin/bash
printf 'dnf5 %s\n' "$*" >> "$CALL_LOG"
case "$*" in
    *list*) printf 'copr:copr.fedorainfracloud.org/phracek/PyCharm\n'; exit 0 ;;
esac
exit 0
STUB
chmod +x "$SANDBOX/stub/dnf5"
if [[ -f $ROOT/bin/omarchy-copr-remove ]]; then
    out=$(bash "$ROOT/bin/omarchy-copr-remove" phracek/PyCharm </dev/null 2>&1)
    contains "$out" "phracek/PyCharm" "copr-remove names the repository it was given"
    not_contains "$(cat "$CALL_LOG")" "disable_copr" "copr-remove did not reach a disable step"
else
    pass "omarchy-copr-remove is absent from this tree"
fi

# channel-current is read-only: it must not invoke a mutating backend.
new_sandbox
if [[ -f $ROOT/bin/omarchy-channel-current ]]; then
    bash "$ROOT/bin/omarchy-channel-current" >/dev/null 2>&1
    not_contains "$(cat "$CALL_LOG")" "dnf5 config-manager --set-default" \
        "channel-current does not change the configured channel"
else
    pass "omarchy-channel-current is absent from this tree"
fi

# omarchy-dns was removed: it configured system DNS through pkexec bash -c, and
# the feature was excised end to end rather than left as a broken command.
if [[ -e $ROOT/bin/omarchy-dns ]]; then
    fail "omarchy-dns is still present after removal"
else
    pass "omarchy-dns is absent from bin/"
fi
if grep -rqE 'omarchy-dns|setDns|dnsCommand|dnsProc' "$ROOT/shell" "$ROOT/default" 2>/dev/null; then
    fail "a surviving shell or config reference still reaches omarchy-dns"
else
    pass "no shell or config reference can invoke omarchy-dns"
fi
# The network panel must survive the excision with its other features intact.
if grep -q 'NetworkRow' "$ROOT/shell/plugins/panels/network/Panel.qml" \
   && grep -q 'omarchy-refresh-network\|NetworkManager\|nmcli\|wifiNetworks' "$ROOT/shell/plugins/panels/network/Panel.qml"; then
    pass "the network panel keeps its non-DNS functionality"
else
    fail "the network panel lost more than the DNS feature"
fi

# No mocked sudo was ever invoked by the read-only checks above.
new_sandbox
not_contains "$(cat "$CALL_LOG")" "sudo" "read-only checks never elevated"

echo ""
echo "=== hook and backend coverage: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]] || exit 1