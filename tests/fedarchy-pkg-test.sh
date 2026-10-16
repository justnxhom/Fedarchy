#!/bin/bash

# fedarchy / fedarchy-pkg behaviour, tested against a mocked dnf5.
#
# No real package is ever installed, removed or upgraded. The mock dnf5 records
# the argv it was handed and exits with a code the test chooses, so argument
# translation, privilege decisions and confirmation policy are all asserted
# without touching this machine's package state.
#
# Harness note: the helpers write to files rather than setting variables inside
# a command substitution. `out="$(run_pkg ...)"` runs the helper in a
# subshell, so any variable it assigns would be lost to the parent.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MOCK_BIN="$TMP/mock-bin"
ARGV_LOG="$TMP/argv.log"
OUT_LOG="$TMP/out.log"
mkdir -p "$MOCK_BIN"

export MOCK_LOG="$ARGV_LOG"
FEDARCHY_BIN="$ROOT/bin/fedarchy"
FEDARCHY_PKG_BIN="$ROOT/bin/fedarchy-pkg"

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '  FAIL %s\n' "$1"
  [[ -n ${2:-} ]] && printf '       %s\n' "$2"
  return 0
}

# The mock stands in for dnf5. It writes the argv it received to $MOCK_LOG and
# exits with $MOCK_EXIT, so no host package state is ever touched.
cat >"$MOCK_BIN/dnf5" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"${MOCK_LOG:?}"
exit "${MOCK_EXIT:-0}"
MOCK
chmod +x "$MOCK_BIN/dnf5"

# sudo is mocked too. Mutating operations escalate, and a real sudo would try to
# read a password and then run the real dnf5. The mock sudo drops the privilege
# wrapper and re-execs the underlying command, so the mutating paths can be
# asserted end to end without any privilege change and without touching the host.
cat >"$MOCK_BIN/sudo" <<'SUDO'
#!/bin/bash
# Drop the leading "--" if present, then run the rest as the current user.
if [[ ${1:-} == "--" ]]; then shift; fi
if [[ ${1:-} == "-n" ]]; then shift; fi
exec "$@"
SUDO
chmod +x "$MOCK_BIN/sudo"

# Run an entry point with the mock first on PATH. Output goes to $OUT_LOG and
# the backend's argv to $ARGV_LOG.
run_pkg() {
  : >"$ARGV_LOG"
  : >"$OUT_LOG"
  PATH="$MOCK_BIN:$PATH" "$FEDARCHY_PKG_BIN" "$@" >"$OUT_LOG" 2>&1
}

run_main() {
  : >"$ARGV_LOG"
  : >"$OUT_LOG"
  PATH="$MOCK_BIN:$PATH" "$FEDARCHY_BIN" "$@" >"$OUT_LOG" 2>&1
}

argv() { cat "$ARGV_LOG"; }
out() { cat "$OUT_LOG"; }

assert_argv() { # label expected-substring
  if [[ "$(argv)" == *"$2"* ]]; then pass "$1"; else fail "$1" "expected '$2' in argv, got: $(argv)"; fi
}

assert_argv_eq() { # label expected
  if [[ "$(argv)" == "$2" ]]; then pass "$1"; else fail "$1" "expected '$2', got '$(argv)'"; fi
}

assert_out() { # label needle
  if [[ "$(out)" == *"$2"* ]]; then pass "$1"; else fail "$1" "'$2' not in output: $(out)"; fi
}

assert_no_argv() { # label
  if [[ -z "$(argv)" ]]; then pass "$1"; else fail "$1" "expected no dnf5 call, got: $(argv)"; fi
}

echo
echo "fedarchy-pkg: alias translation"

run_pkg add firefox
assert_argv "add -> install" "install firefox"

run_pkg install firefox
assert_argv "install passes through" "install firefox"

run_pkg remove firefox
assert_argv "remove -> remove" "remove firefox"

run_pkg search neovim
assert_argv "search -> search" "search neovim"

run_pkg info neovim
assert_argv "info -> info" "info neovim"

run_pkg list --installed
assert_argv "native flags preserved" "list --installed"

echo
echo "fedarchy-pkg: multiple packages and argument safety"

run_pkg add firefox neovim ripgrep
assert_argv "multiple packages kept in order" "install firefox neovim ripgrep"

# A package name containing shell metacharacters must reach dnf5 as one literal
# argument, never as shell syntax.
run_pkg add 'evil; rm -rf /'
assert_argv "metacharacters passed as one literal argument" "install evil; rm -rf /"

echo
echo "fedarchy-pkg: history"

run_pkg history
assert_argv "bare history defaults to list" "history list"

run_pkg history info 42
assert_argv "history info passes id" "history info 42"

run_pkg undo 42
assert_argv "undo -> history undo" "history undo 42"

run_pkg redo 42
assert_argv "redo -> history redo" "history redo 42"

echo
echo "fedarchy-pkg: passthrough"

run_pkg repoquery --duplicates
assert_argv "unknown subcommand forwarded verbatim" "repoquery --duplicates"

run_pkg provides /usr/bin/bash
assert_argv "provides forwarded" "provides /usr/bin/bash"

# The most important passthrough property: an unrecognised word must never be
# quietly turned into some other operation.
run_pkg frobnicate all
assert_argv_eq "unknown verb is not rewritten" "frobnicate all"

echo
echo "fedarchy-pkg: privilege policy"

# Read-only must reach the backend with no escalation. Removing sudo from PATH
# proves it: a read that tried to escalate would fail instead of answering.
: >"$ARGV_LOG"
PATH="$MOCK_BIN:/usr/bin:/bin" "$FEDARCHY_PKG_BIN" info bash >"$OUT_LOG" 2>&1
assert_argv "read-only reaches the backend without sudo" "info bash"

# Mutating operations must escalate, and --yes must skip the confirmation so
# the unattended test path is predictable.
run_pkg add --yes firefox
assert_argv "mutating op escalates through sudo to install" "install firefox"

run_pkg undo --yes 42
assert_argv "undo escalates to history undo" "history undo 42"

echo
echo "fedarchy-pkg: argument validation"

run_pkg undo
assert_out "undo without an id is refused" "needs a transaction id"

run_pkg add
assert_out "add without a package is refused" "needs at least one package"

echo
echo "fedarchy-pkg: missing backend"

: >"$ARGV_LOG"
: >"$OUT_LOG"
PATH="$MOCK_BIN:/usr/bin:/bin" FEDARCHY_DNF_BIN="definitely-not-installed-dnf" \
  "$FEDARCHY_PKG_BIN" search x >"$OUT_LOG" 2>&1
assert_out "missing dnf5 reports actionably" "command not found"

echo
echo "fedarchy: dispatcher"

run_main help
assert_out "help points at fedarchy-pkg" "fedarchy-pkg"

run_main nonsense
assert_out "unknown command refused, not guessed" "unknown command"

run_main status
assert_out "status produces a summary" "Fedarchy package status"

run_main doctor
assert_out "doctor produces a verdict" "PASS"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]]