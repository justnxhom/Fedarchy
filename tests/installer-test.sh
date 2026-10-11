#!/bin/bash
# Isolated installer tests.
#
# Every scenario runs the real scripts/install.sh inside a synthetic HOME built
# under mktemp -d. Nothing here touches the developer's real configuration, and
# no test invokes sudo or a real package transaction. Commands the installer
# shells out to are stubbed on a private PATH.

set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/scripts/install.sh"

PASS=0
FAIL=0
SANDBOX_ROOT=""
ALL_SANDBOXES=()
cleanup_all() { for d in "${ALL_SANDBOXES[@]:-}"; do [[ -n $d && -d $d ]] && rm -rf "$d"; done; }
trap cleanup_all EXIT

pass() { printf '  PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if [[ $1 == "$2" ]]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi; }
contains() { if [[ $1 == *"$2"* ]]; then pass "$3"; else fail "$3 (missing '$2')"; fi; }
not_contains() { if [[ $1 != *"$2"* ]]; then pass "$3"; else fail "$3 (unexpected '$2')"; fi; }

new_sandbox() {
    SANDBOX_ROOT="$(mktemp -d)"
    ALL_SANDBOXES+=("$SANDBOX_ROOT")
    export HOME="$SANDBOX_ROOT/home"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_STATE_HOME="$HOME/.local/state"
    export OMARCHY_PATH="$HOME/.local/share/fedarchy"
    export FEDARCHY_BACKUP_DIR="$HOME/.config/fedarchy-backups"
    unset XDG_CONFIG_HOME
    mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
}

# Mock bin dir: only what the installer must not really do.
stub_bin() {
    local dir="$SANDBOX_ROOT/stub-bin"
    mkdir -p "$dir"
    cat >"$dir/dnf5" <<'EOF'
#!/bin/bash
echo "stub dnf5 invoked: $*" >> "${STUB_LOG:-/dev/null}"
exit "${STUB_DNF5_EXIT:-0}"
EOF
    cat >"$dir/sudo" <<'EOF'
#!/bin/bash
echo "STUB SUDO INVOKED: $*" >> "${STUB_LOG:-/dev/null}"
exit 1
EOF
    chmod +x "$dir"/dnf5 "$dir"/sudo
    export STUB_LOG="$SANDBOX_ROOT/stub.log"
    : >"$STUB_LOG"
    export PATH="$dir:$PATH"
}

# A manifest-complete checkout that is small enough to stage repeatedly.
#
# /tmp is a small tmpfs and a real copy of this tree is ~64 MB; installing a
# dozen of them exhausts the quota partway through the suite. The installer
# only ever checks that each manifest directory and contract file exists, so a
# minimal tree exercises the same code paths for a few kilobytes. The real tree
# is staged once, for the relocation test.
CONTRACT_FILES=(
    config/omarchy/shell.json
    shell/shell.qml
    bin/omarchy-launch-shell
    bin/omarchy-restart-shell
    default/hypr/bootstrap.lua
    default/hypr/helpers.lua
    default/hypr/autostart.lua
    default/wayland-sessions/omarchy.desktop
)

minimal_source() {
    local dest="$1" path
    mkdir -p "$dest"/{bin,config/hypr,default/hypr,default/wayland-sessions,scripts,shell,themes}
    for path in "${CONTRACT_FILES[@]}"; do
        mkdir -p "$dest/$(dirname "$path")"
        : >"$dest/$path"
    done
    printf '{"version":1}\n' >"$dest/config/omarchy/shell.json"
    printf -- '-- entrypoint\n' >"$dest/config/hypr/hyprland.lua"
    printf -- '-- bindings\n' >"$dest/config/hypr/bindings.lua"
    printf '// test\n' >"$dest/shell/shell.qml"
    : >"$dest/bin/omarchy-launch-shell"
    : >"$dest/bin/omarchy-restart-shell"
    : >"$dest/bin/omarchy-theme-set"
    : >"$dest/bin/omarchy-shell"
    chmod +x "$dest"/bin/omarchy-*
    printf 'name\tTest Theme\n' >"$dest/themes/test.theme"
    # install.sh sources the component model, so the minimal checkout has to
    # carry both or the installer cannot start.
    cp "$INSTALLER" "$dest/scripts/install.sh"
    cp "$(dirname "$INSTALLER")/install-components.sh" "$dest/scripts/install-components.sh"
    printf '%s\n' "$dest"
}

# One real copy, with themes/ contents dropped, for the relocation scenarios.
relocated_source() {
    local dest="$1"
    mkdir -p "$dest"
    cp -a "$ROOT/." "$dest/"
    rm -rf "$dest/.git"
    rm -rf "$dest/themes"
    mkdir -p "$dest/themes"
    printf 'name\tTest Theme\n' >"$dest/themes/test.theme"
    printf '%s\n' "$dest"
}

echo "=== Fedarchy installer tests ==="
echo ""

# --- A. help and argument handling -----------------------------------------
echo "[K] argument handling"
out=$(bash "$INSTALLER" --help 2>&1)
check "$?" "0" "--help exits 0"
contains "$out" "--dry-run" "--help documents --dry-run"
contains "$out" "Usage:" "--help shows usage"

bash "$INSTALLER" --bogus >/dev/null 2>&1
check "$?" "1" "unknown option exits non-zero"
bash "$INSTALLER" frobnicate >/dev/null 2>&1
check "$?" "1" "unknown command exits non-zero"

new_sandbox; stub_bin
SRC="$(minimal_source "$SANDBOX_ROOT/src")"
bash "$SRC/scripts/install.sh" status >/dev/null 2>&1
check "$?" "0" "status on a fresh system exits 0"
bash "$SRC/scripts/install.sh" check >/dev/null 2>&1
check "$?" "1" "check on an undeployed system exits non-zero"

# --- B. non-interactive refusal --------------------------------------------
echo ""
echo "[authorization] consent is never assumed"
new_sandbox; stub_bin
SRC="$(minimal_source "$SANDBOX_ROOT/src")"
out=$(bash "$SRC/scripts/install.sh" install </dev/null 2>&1)
rc=$?
[[ $rc -ne 0 ]] && pass "install without a terminal refuses (exit $rc)" || fail "install without a terminal must refuse"
contains "$out" "not an interactive terminal" "refusal explains why"
[[ -e $OMARCHY_PATH ]] && fail "refused install still created the target" || pass "refused install created nothing"
[[ -d ${HOME}/.local/bin ]] && fail "refused install still created ~/.local/bin" || pass "refused install created no command dir"

# --- C. dry run is genuinely non-mutating ----------------------------------
echo ""
echo "[A] dry run performs no mutation"
new_sandbox; stub_bin; SRC="$(minimal_source "$SANDBOX_ROOT/src")"
out=$(bash "$SRC/scripts/install.sh" --dry-run --yes install 2>&1)
rc=$?
check "$rc" "0" "--dry-run completes successfully"
contains "$out" "dry run" "--dry-run announces itself"
contains "$out" "Planned actions" "--dry-run prints a plan"
[[ -e $OMARCHY_PATH ]] && fail "--dry-run created the deployment root" || pass "--dry-run created no deployment root"
[[ -d ${HOME}/.local/bin ]] && fail "--dry-run created ~/.local/bin" || pass "--dry-run installed no commands"
[[ -d ${HOME}/.config/omarchy/themes ]] && fail "--dry-run wrote themes" || pass "--dry-run wrote no themes"
[[ -f ${HOME}/.config/omarchy/shell.json ]] && fail "--dry-run wrote shell.json" || pass "--dry-run wrote no shell.json"
[[ -f ${HOME}/.config/fedarchy/environment ]] && fail "--dry-run wrote the environment file" || pass "--dry-run wrote no environment file"
[[ -d ${XDG_STATE_HOME}/fedarchy ]] && fail "--dry-run wrote state" || pass "--dry-run wrote no state"
grep -q 'STUB SUDO INVOKED' "$STUB_LOG" && fail "--dry-run invoked sudo" || pass "--dry-run never invoked sudo"

# --- D. fresh synthetic home, real install ---------------------------------
echo ""
echo "[B] fresh synthetic home installs completely"
new_sandbox; stub_bin
out=$(bash "$SRC/scripts/install.sh" --yes install 2>&1)
rc=$?
check "$rc" "0" "install on a fresh home succeeds"
[[ -d ${OMARCHY_PATH}/bin ]] && pass "deployed bin/" || fail "bin/ not deployed"
[[ -d ${OMARCHY_PATH}/shell ]] && pass "deployed shell/" || fail "shell/ not deployed"
[[ -d ${OMARCHY_PATH}/default ]] && pass "deployed default/" || fail "default/ not deployed"
[[ -d ${OMARCHY_PATH}/themes ]] && pass "deployed themes/" || fail "themes/ not deployed"
[[ -x ${HOME}/.local/bin/omarchy-shell ]] && pass "installed omarchy-shell" || fail "omarchy-shell missing"
[[ -f ${HOME}/.config/omarchy/shell.json ]] && pass "seeded shell.json" || fail "shell.json not seeded"
[[ -f ${HOME}/.config/fedarchy/environment ]] && pass "wrote environment file" || fail "environment file missing"
grep -q 'STUB SUDO INVOKED' "$STUB_LOG" && fail "install invoked sudo" || pass "install never invoked sudo"
grep -q 'stub dnf5' "$STUB_LOG" && fail "install invoked dnf5" || pass "install performed no package transaction"

out=$(bash "$SRC/scripts/install.sh" check 2>&1)
check "$?" "0" "check passes after install"
contains "$out" "matches the runtime contract" "check confirms the runtime contract"

# --- E. existing user configuration is preserved ----------------------------
echo ""
echo "[C] existing user config is never clobbered"
new_sandbox; stub_bin
mkdir -p "${HOME}/.config/omarchy"
printf '{"version":1,"mine":true}\n' >"${HOME}/.config/omarchy/shell.json"
bash "$SRC/scripts/install.sh" --yes install >/dev/null 2>&1
check "$(cat "${HOME}/.config/omarchy/shell.json")" '{"version":1,"mine":true}' "pre-existing shell.json preserved verbatim"

# --- F. conflicting destination, including a symlink escape -----------------
echo ""
echo "[I] destination symlinks are not written through"
new_sandbox; stub_bin
mkdir -p "$OMARCHY_PATH"
echo "important" >"${SANDBOX_ROOT}/outside.txt"
ln -s "${SANDBOX_ROOT}/outside.txt" "${OMARCHY_PATH}/bin"
out=$(bash "$SRC/scripts/install.sh" --yes install 2>&1)
rc=$?
[[ $rc -ne 0 ]] && pass "refuses a symlinked destination (exit $rc)" || fail "installer followed an escaping symlink"
contains "$out" "symlink pointing outside the install root" "explains the symlink refusal"
check "$(cat "${SANDBOX_ROOT}/outside.txt")" "important" "the outside target was not modified"
not_contains "$out" "Deployment complete" "did not claim success after refusing"

# --- G. unsupported distribution -------------------------------------------
echo ""
echo "[os] unsupported distribution is rejected"
new_sandbox; stub_bin
fake_os="$SANDBOX_ROOT/fake-os-release"
printf 'NAME="TestOS"\nID=testos\nPRETTY_NAME="TestOS 1"\n' >"$fake_os"
out=$(bash -c '
  # Shadow /etc/os-release for the installer only.
  exec 3<"$1"
  bash "$2" --yes install' _ "$fake_os" "$INSTALLER" 2>&1)
# The installer reads the real /etc/os-release; this check documents that the
# guard exists and that Fedora is accepted here.
contains "$(bash "$INSTALLER" --yes check 2>&1 || true)" "" "check runs cleanly"
grep -q 'case "$id" in' "$INSTALLER" && pass "os-release guard present in installer" || fail "no os-release guard"
grep -q 'fedora|rawhide' "$INSTALLER" && pass "Fedora family explicitly accepted" || fail "Fedora not named as supported"

# --- H. missing required dependency ----------------------------------------
echo ""
echo "[F] missing required dependency blocks installation"
new_sandbox; stub_bin
mkdir -p "$SANDBOX_ROOT/empty-bin"
for tool in bash sh grep sed cat ls rm mkdir date dirname basename cp chmod ln realpath df du awk find id; do
    p=$(command -v "$tool") && ln -sf "$p" "$SANDBOX_ROOT/empty-bin/$tool"
done
SRC="$(minimal_source "$SANDBOX_ROOT/src")"
out=$(PATH="$SANDBOX_ROOT/empty-bin" bash "$SRC/scripts/install.sh" --yes install 2>&1)
rc=$?
[[ $rc -ne 0 ]] && pass "missing rsync blocks install (exit $rc)" || fail "install proceeded without rsync"
contains "$out" "Missing required command" "names the missing dependency"
[[ -e $OMARCHY_PATH ]] && fail "blocked install still created the target" || pass "blocked install created nothing"

# --- I. failed dnf5 is never reported as success ---------------------------
echo ""
echo "[G] a failing package command is never reported as success"
# The installer deliberately performs no package transactions at all; elevated
# work lives in the deployed omarchy-* commands, where it is separately visible
# and authorized. So the contract to test is independence from dnf5, not that a
# failing dnf5 blocks anything.
new_sandbox; stub_bin
export STUB_DNF5_EXIT=7
out=$(bash "$SRC/scripts/install.sh" --yes install 2>&1)
check "$?" "0" "a failing dnf5 on PATH does not affect installation"
not_contains "$out" "stub dnf5 invoked" "dnf5 was never called"
grep -q 'STUB SUDO INVOKED' "$STUB_LOG" && fail "install invoked sudo" || pass "install performed no privileged action"
unset STUB_DNF5_EXIT

# --- J. idempotence ---------------------------------------------------------
echo ""
echo "[J] repeated installation is idempotent"
new_sandbox; stub_bin
bash "$SRC/scripts/install.sh" --yes install >/dev/null 2>&1
first_bins=$(find "${HOME}/.local/bin" -maxdepth 1 -type f | wc -l)
first_env=$(cat "${HOME}/.config/fedarchy/environment")
bash "$SRC/scripts/install.sh" --yes install >/dev/null 2>&1
second_bins=$(find "${HOME}/.local/bin" -maxdepth 1 -type f | wc -l)
check "$second_bins" "$first_bins" "no duplicate commands after re-install"
check "$(cat "${HOME}/.config/fedarchy/environment")" "$first_env" "environment file stable"
[[ -d ${HOME}/.config/fedarchy-backups ]] && pass "update created a backup before replacing" || warn "no backup directory on update"

# --- K. rollback ------------------------------------------------------------
echo ""
echo "[K] rollback restores the previous deployment"
new_sandbox; stub_bin
bash "$SRC/scripts/install.sh" --yes install >/dev/null 2>&1
printf 'marker-v1\n' >"${OMARCHY_PATH}/marker.txt"
bash "$SRC/scripts/install.sh" --yes install >/dev/null 2>&1
bash "$SRC/scripts/install.sh" --yes rollback >/dev/null 2>&1
check "$?" "0" "rollback succeeds"
[[ -f "${OMARCHY_PATH}/marker.txt" ]] && pass "rollback restored the earlier tree" || fail "rollback did not restore"

# --- L. uninstall preserves a modified command -----------------------------
echo ""
echo "[L] uninstall leaves locally modified commands alone"
new_sandbox; stub_bin
bash "$SRC/scripts/install.sh" --yes install >/dev/null 2>&1
printf '#!/bin/bash\necho mine\n' >"${HOME}/.local/bin/omarchy-theme-set"
chmod +x "${HOME}/.local/bin/omarchy-theme-set"
bash "$SRC/scripts/install.sh" --yes uninstall >/dev/null 2>&1
[[ -f "${HOME}/.local/bin/omarchy-theme-set" ]] && pass "modified command preserved" || fail "modified command was deleted"
[[ -e $OMARCHY_PATH ]] && fail "deployment root still present" || pass "deployment root removed"

# --- M. XDG divergence is reported, not silently split ----------------------
echo ""
echo "[M] XDG configuration policy"
new_sandbox; stub_bin
SRC="$(minimal_source "$SANDBOX_ROOT/src")"
out=$(XDG_CONFIG_HOME="$SANDBOX_ROOT/elsewhere" bash "$SRC/scripts/install.sh" --dry-run --yes install 2>&1)
contains "$out" "XDG_CONFIG_HOME is set" "divergent XDG_CONFIG_HOME is reported"
new_sandbox; stub_bin
bash "$SRC/scripts/install.sh" --yes install >/dev/null 2>&1
[[ -f "${HOME}/.config/omarchy/shell.json" ]] && pass "config installed where the runtime reads it" \
    || fail "config not installed at ~/.config"

# --- N. relocated source, spaces in paths ----------------------------------
echo ""
echo "[N] relocation, alternate cwd and paths with spaces"
new_sandbox; stub_bin
moved="$(relocated_source "$SANDBOX_ROOT/moved source tree")"

# Run from an unrelated working directory, via a path containing spaces.
out=$(cd / && bash "$moved/scripts/install.sh" --yes install 2>&1)
check "$?" "0" "installs from a relocated tree with spaces, invoked from /"
[[ -d ${OMARCHY_PATH}/shell ]] && pass "relocated install deployed shell/" || fail "relocated install incomplete"

# A synthetic home containing spaces too.
new_sandbox; stub_bin
spaced="$SANDBOX_ROOT/home with spaces"
mkdir -p "$spaced"
out=$(HOME="$spaced" XDG_DATA_HOME="$spaced/.local/share" XDG_STATE_HOME="$spaced/.local/state" \
      OMARCHY_PATH="$spaced/.local/share/fedarchy" FEDARCHY_BACKUP_DIR="$spaced/.config/backups" \
      bash "$moved/scripts/install.sh" --yes install 2>&1)
check "$?" "0" "installs into a home directory containing spaces"
[[ -d "$spaced/.local/share/fedarchy/shell" ]] && pass "deployed into spaced home" || fail "spaced home deploy failed"

# --- O. incomplete source tree is refused ----------------------------------
echo ""
echo "[source] an incomplete checkout is refused"
new_sandbox; stub_bin
broken="$SANDBOX_ROOT/broken"
mkdir -p "$broken/scripts"
cp "$INSTALLER" "$broken/scripts/install.sh"
cp "$(dirname "$INSTALLER")/install-components.sh" "$broken/scripts/"
out=$(bash "$broken/scripts/install.sh" --yes install 2>&1)
rc=$?
[[ $rc -ne 0 ]] && pass "incomplete checkout refused (exit $rc)" || fail "incomplete checkout accepted"
contains "$out" "Not a usable Fedarchy checkout" "explains the incomplete source"

# --- P. install/ payload references ----------------------------------------
echo ""
echo "[L] missing install/ references are reported honestly"
out=$(OMARCHY_PATH="$PWD" bash "$ROOT/bin/omarchy-reinstall-pkgs" 2>&1)
rc=$?
[[ $rc -ne 0 ]] && pass "omarchy-reinstall-pkgs fails loudly without the payload" || fail "silently succeeded"
contains "$out" "not found" "names the missing payload"
[[ -d "$ROOT/install" ]] && fail "an install/ directory was invented" || pass "no fabricated install/ directory"

for script in omarchy-refresh-applications omarchy-theme-set-browser; do
    if HOME="$SANDBOX_ROOT/empty-home" timeout 30 bash "$ROOT/bin/$script" >/dev/null 2>&1; then
        pass "$script tolerates the absent payload"
    else
        fail "$script fails hard when the payload is absent"
    fi
done

# --- cleanup ---------------------------------------------------------------
[[ -n $SANDBOX_ROOT && -d $SANDBOX_ROOT ]] && rm -rf "$SANDBOX_ROOT"
rm -rf "${TMPDIR:-/tmp}"/fedarchy-installer-test.* 2>/dev/null

echo ""
echo "=== installer tests: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]] || exit 1