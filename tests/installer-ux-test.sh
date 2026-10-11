#!/bin/bash
# Installer user-experience tests.
#
# Covers the guided wizard, the CLI surface, component selection and the safety
# guarantees. Every run uses a synthetic HOME under mktemp -d and stubbed
# commands. No test installs Fedarchy on the developer's machine, invokes sudo,
# or runs a real package transaction.
#
# gum is stubbed so the wizard can be driven deterministically: a scripted
# answer file decides what a "user" picks, exactly as a person's keypresses
# would. The production code path is what runs.

set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/scripts/install.sh"
COMPONENTS="$ROOT/scripts/install-components.sh"

PASS=0
FAIL=0
SANDBOX_ROOT=""
ALL_SANDBOXES=()

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

    local stub="$SANDBOX_ROOT/stub"
    mkdir -p "$stub"

    # gum stub: answers come from $GUM_ANSWERS, one per prompt, in order, so a
    # "user" can be scripted deterministically while the real code path runs.
    cat >"$stub/gum" <<'STUB'
#!/bin/bash
if [[ ${1:-} == choose ]]; then
    n=$(cat "$GUM_COUNTER" 2>/dev/null || echo 0); echo $((n + 1)) >"$GUM_COUNTER"
    mapfile -t o <"$GUM_ANSWERS"; printf '%s\n' "${o[$n]}"; exit 0
fi
if [[ ${1:-} == confirm ]]; then
    n=$(cat "$GUM_COUNTER" 2>/dev/null || echo 0); echo $((n + 1)) >"$GUM_COUNTER"
    mapfile -t o <"$GUM_ANSWERS"; a="${o[$n]:-y}"
    if [[ $a == y* ]]; then echo yes; exit 0; fi
    echo no; exit 1
fi
echo yes
STUB
    chmod +x "$stub/gum"
    : >"$SANDBOX_ROOT/gum-answers"
    export GUM_ANSWERS="$SANDBOX_ROOT/gum-answers"
    export GUM_COUNTER="$SANDBOX_ROOT/gum-counter"
    export GUM_CONFIRM_OVERRIDE=""
    : > "$GUM_COUNTER"
    export PATH="$stub:$PATH"

    # Minimal manifest-complete checkout, so the suite stays small on tmpfs.
    local src="$SANDBOX_ROOT/src"
    mkdir -p "$src"/{bin,config/hypr,config/alacritty,default/hypr,scripts,shell,themes}
    : >"$src/config/omarchy_dummy"
    mkdir -p "$src/config/omarchy"
    printf '{"version":1}\n' >"$src/config/omarchy/shell.json"
    printf 'name\tT\n' >"$src/themes/test.theme"
    printf 'theme = "dark"\n' >"$src/config/alacritty/alacritty.toml"
    printf -- '-- binds\n' >"$src/config/hypr/bindings.lua"
    # Mirror the real entrypoint: the commented keybinding flag must precede the
    # require that reads it, and every user module must still be required.
    {
        printf -- '-- Omarchy bootstrap\n'
        printf -- 'dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")\n'
        printf '\n'
        printf -- '-- Disable all Omarchy default bindings.\n'
        printf -- '-- omarchy_default_bindings = false\n'
        printf '\n'
        printf -- '-- Load Omarchy defaults.\n'
        printf -- 'require("default.hypr.omarchy")\n'
        printf '\n'
        printf -- 'require("hypr.monitors")\n'
        printf -- 'require("hypr.input")\n'
        printf -- 'require("hypr.bindings")\n'
        printf -- 'require("hypr.looknfeel")\n'
        printf -- 'require("hypr.autostart")\n'
    } >"$src/config/hypr/hyprland.lua"
    : >"$src/default/hypr/bootstrap.lua"
    : >"$src/default/hypr/helpers.lua"
    : >"$src/default/hypr/autostart.lua"
    mkdir -p "$src/default/wayland-sessions"
    : >"$src/default/wayland-sessions/omarchy.desktop"
    : >"$src/shell/shell.qml"
    : >"$src/bin/omarchy-launch-shell"
    : >"$src/bin/omarchy-restart-shell"
    : >"$src/bin/omarchy-theme-set"
    : >"$src/bin/omarchy-shell"
    chmod +x "$src"/bin/omarchy-*
    cp "$INSTALLER" "$src/scripts/install.sh"
    cp "$COMPONENTS" "$src/scripts/install-components.sh"
    export SRC="$src"
}

run_installer() {
    local mode_args="$1"
    shift
    bash "$SRC/scripts/install.sh" "$@" </dev/null 2>&1
}

echo "=== Fedarchy installer UX tests ==="
echo ""

# --- component model --------------------------------------------------------
echo "[model] component metadata and dependencies"
new_sandbox
out=$(bash -c "source '$COMPONENTS'; component_ids" 2>&1)
check "$(printf '%s\n' "$out" | wc -l)" "7" "seven components are declared"
out=$(bash -c "source '$COMPONENTS'; resolve_dependencies keybindings" 2>&1)
contains "$out" "hypr-config" "keybindings pulls in hypr-config"
contains "$out" "shell" "hypr-config pulls in shell"
contains "$out" "commands" "required components are always included"
out=$(bash -c "source '$COMPONENTS'; resolve_dependencies themes themes" 2>&1)
check "$(printf '%s\n' "$out" | wc -l)" "3" "duplicate input does not duplicate components"
out=$(bash -c "source '$COMPONENTS'; component_label keybindings" 2>&1)
check "$out" "Keyboard shortcuts" "components have plain-language labels"
out=$(bash -c "source '$COMPONENTS'; component_why keybindings" 2>&1)
[[ -n $out ]] && pass "components explain why a user might want them" || fail "no explanation for a component"

# --- profiles ---------------------------------------------------------------
echo ""
echo "[profiles] profile selection produces the right component set"
for profile in minimal recommended preserve; do
    new_sandbox
    out=$(run_installer "" --profile "$profile" --dry-run --yes)
    contains "$out" "Components to install" "profile '$profile' renders a plan"
    check "$?" "0" "profile '$profile' exits 0"
done

new_sandbox
min_plan=$(run_installer "" --profile minimal --dry-run --yes)
not_contains "$min_plan" "Hyprland configuration   Fedarchy" "minimal excludes hypr config"
contains "$min_plan" "Keyboard shortcuts" "minimal lists keybindings as not applied"

new_sandbox
rec_plan=$(run_installer "" --profile recommended --dry-run --yes)
contains "$rec_plan" "Keyboard shortcuts   " "recommended includes keybindings"

new_sandbox
preserve_plan=$(run_installer "" --profile preserve --dry-run --yes)
contains "$preserve_plan" "Application configuration" "preserve includes app configs"

# --- custom component selection --------------------------------------------
echo ""
echo "[custom] explicit component selection"
new_sandbox
out=$(run_installer "" --component themes --dry-run --yes)
contains "$out" "Themes" "an explicit component is installed"
not_contains "$out" "Hyprland configuration   Fedarchy" "an explicit selection does not pull unasked components"

new_sandbox
out=$(run_installer "" --component keybindings --dry-run --yes)
contains "$out" "Hyprland configuration" "a dependency is added transparently"

new_sandbox
out=$(run_installer "" --components themes,app-configs --dry-run --yes)
contains "$out" "Application configuration" "comma-separated component list works"

new_sandbox
out=$(run_installer "" --profile minimal --component themes --dry-run --yes)
contains "$out" "Themes" "a component can be added on top of a profile"

# --- plan quality -----------------------------------------------------------
echo ""
echo "[plan] the plan explains consequences"
new_sandbox
out=$(run_installer "" --profile recommended --dry-run --yes)
contains "$out" "What this changes on your system" "plan lists concrete destinations"
contains "$out" "Not being changed" "plan states what is deliberately untouched"
contains "$out" "Privileged operations" "plan addresses privileged operations"
contains "$out" "never uses sudo" "plan is honest about needing no elevation"
contains "$out" "backed up" "plan states the backup policy"

# --- CLI surface ------------------------------------------------------------
echo ""
echo "[cli] option handling"
new_sandbox
out=$(run_installer "" --help)
contains "$out" "Usage:" "--help works"
new_sandbox
run_installer "" --version >/dev/null
check "$?" "0" "--version exits 0"
new_sandbox
out=$(run_installer "" --version)
contains "$out" "Fedarchy installer" "--version reports the installer version"
new_sandbox
run_installer "" --definitely-not-an-option >/dev/null
check "$?" "1" "unknown option exits non-zero"
new_sandbox
run_installer "" --profile not-a-profile >/dev/null
check "$?" "1" "unknown profile exits non-zero"
new_sandbox
out=$(run_installer "" --check)
[[ -e $OMARCHY_PATH ]] && fail "--check mutated the system" || pass "--check is read-only"
new_sandbox
out=$(run_installer "" --doctor 2>&1)
[[ -e $OMARCHY_PATH ]] && fail "--doctor mutated the system" || pass "--doctor is read-only"

# --- safety -----------------------------------------------------------------
echo ""
echo "[safety] modes that must never install"
new_sandbox
out=$(run_installer "" --dry-run --yes --profile recommended)
[[ -e $OMARCHY_PATH ]] && fail "--dry-run created the deployment" || pass "--dry-run creates nothing"
[[ -d ${HOME}/.local/bin ]] && fail "--dry-run installed commands" || pass "--dry-run installs no commands"
[[ -d ${HOME}/.config/hypr ]] && fail "--dry-run wrote Hyprland config" || pass "--dry-run writes no Hyprland config"
[[ -d ${HOME}/.config/alacritty ]] && fail "--dry-run wrote app config" || pass "--dry-run writes no app config"
new_sandbox
out=$(run_installer "" --profile recommended </dev/null)
[[ -e $OMARCHY_PATH ]] && fail "non-interactive install without --yes proceeded" || pass "consent is required"
not_contains "$out" "Deployment complete" "a refused install reports no success"

# --- real installation inside the sandbox -----------------------------------
echo ""
echo "[install] component-aware installation"
new_sandbox
run_installer "" --yes --profile recommended >/dev/null
check "$?" "0" "recommended profile installs"
[[ -d ${HOME}/.config/hypr ]] && pass "hypr config installed" || fail "hypr config missing"
[[ -f ${HOME}/.config/omarchy/shell.json ]] && pass "shell.json seeded" || fail "shell.json missing"
[[ -f ${XDG_STATE_HOME}/fedarchy/components ]] && pass "selection recorded" || fail "selection not recorded"
contains "$(cat "${XDG_STATE_HOME}/fedarchy/components" 2>/dev/null)" "keybindings" "recorded selection names the components"

# minimal must NOT install hypr config
new_sandbox
run_installer "" --yes --profile minimal >/dev/null
[[ -d ${HOME}/.config/hypr ]] && fail "minimal installed Hyprland config" || pass "minimal installs no Hyprland config"

# app-configs installs app config, and preserves an existing file
new_sandbox
mkdir -p "${HOME}/.config/alacritty"
printf 'mine = true\n' >"${HOME}/.config/alacritty/alacritty.toml"
run_installer "" --yes --profile preserve >/dev/null
check "$(cat "${HOME}/.config/alacritty/alacritty.toml")" "mine = true" "existing app config preserved"

# keybindings declined must say so, not silently install them
new_sandbox
run_installer "" --yes --component themes >/dev/null
# The installer now writes the flag rather than telling the user to, so the
# plan reports the outcome instead of quoting the line to add by hand.
out=$(run_installer "" --component themes --component hypr-config --dry-run --yes)
contains "$out" "turn Fedarchy's keyboard shortcuts off" "the plan states that keybindings will be switched off"


# --- keybinding choice ------------------------------------------------------
echo ""
echo "[keybindings] the choice is implemented, not just explained"
new_sandbox
run_installer "" --yes --profile recommended >/dev/null
entry="${HOME}/.config/hypr/hyprland.lua"
check "$(grep -cE '^[[:space:]]*omarchy_default_bindings[[:space:]]*=[[:space:]]*false' "$entry")" "0" \
    "accepting keybindings leaves the flag off"
contains "$(cat "$entry")" 'require("default.hypr.omarchy")' "the defaults are still loaded"

new_sandbox
run_installer "" --yes --component themes --component hypr-config >/dev/null
entry="${HOME}/.config/hypr/hyprland.lua"
check "$(grep -cE '^[[:space:]]*omarchy_default_bindings[[:space:]]*=[[:space:]]*false' "$entry")" "1" \
    "declining keybindings enables the flag automatically"
check "$(grep -c 'require("hypr\.' "$entry")" "5" "every module the entrypoint needs is still required"
# The flag must appear before the require that reads it, or it has no effect.
flag_line=$(grep -nE '^[[:space:]]*omarchy_default_bindings[[:space:]]*=[[:space:]]*false' "$entry" | cut -d: -f1)
require_line=$(grep -n 'require("default.hypr.omarchy")' "$entry" | cut -d: -f1)
[[ -n $flag_line && -n $require_line && $flag_line -lt $require_line ]] \
    && pass "the flag is set before the defaults are loaded" \
    || fail "the flag must precede the require that reads it"
[[ -n $(ls "${HOME}/.config/hypr/" | grep backup) ]] && pass "the entrypoint was backed up before being changed" \
    || fail "no backup made before enabling the flag"

new_sandbox
run_installer "" --yes --component themes --component hypr-config >/dev/null
before=$(ls "${HOME}/.config/hypr/" | grep -c backup)
run_installer "" --yes --component themes --component hypr-config >/dev/null
after=$(ls "${HOME}/.config/hypr/" | grep -c backup)
check "$after" "$before" "re-installing is idempotent and adds no further backup"

new_sandbox
run_installer "" --yes --component themes --component hypr-config --dry-run >/dev/null
[[ -f ${HOME}/.config/hypr/hyprland.lua ]] && fail "dry-run wrote the keybinding setting" \
    || pass "dry-run writes no keybinding setting"
out=$(run_installer "" --profile recommended --dry-run --yes)
contains "$out" "keyboard shortcuts" "the plan states the keybinding outcome"

new_sandbox
out=$(run_installer "" --profile recommended </dev/null)
[[ -f ${HOME}/.config/hypr/hyprland.lua ]] && fail "a cancelled install changed the keybindings" \
    || pass "cancelling before confirmation changes nothing"

# Declining must not touch a user's own entrypoint when they keep it.
new_sandbox
mkdir -p "${HOME}/.config/hypr"
cp "$SRC/config/hypr/hyprland.lua" "${HOME}/.config/hypr/hyprland.lua"
printf '%s\n' "-- marker: user customised" >> "${HOME}/.config/hypr/hyprland.lua"
run_installer "" --yes --component themes --component hypr-config >/dev/null
# The entrypoint is replaced so the keybinding choice can be applied to it, so
# the user's customisation has to survive in the backup rather than in place.
# Two backups can exist: one from replacing the entrypoint, one from enabling
# the flag. The user's own content has to be in at least one of them.
if grep -ql "marker: user customised" "${HOME}"/.config/hypr/hyprland.lua.fedarchy-backup-* 2>/dev/null; then
    pass "the customised entrypoint is preserved in its backup"
else
    fail "the customised entrypoint is preserved in its backup"
fi
if compgen -G "${HOME}/.config/hypr/hyprland.lua.fedarchy-backup-*" >/dev/null; then
    pass "the customised entrypoint has a backup"
else
    fail "no backup for the customised entrypoint"
fi

new_sandbox
out=$(run_installer "" --component themes --component hypr-config --dry-run --yes)
not_contains "$out" "Cannot apply" "the documented path applies cleanly"

# --- conflict handling ------------------------------------------------------
echo ""
echo "[conflict] existing configuration is protected"
new_sandbox
mkdir -p "${HOME}/.config/hypr"
printf "%s\n" "-- my own entrypoint" >"${HOME}/.config/hypr/hyprland.lua"
run_installer "" --yes --profile recommended >/dev/null
backup_file=$(find "${HOME}/.config/hypr" -name 'hyprland.lua.fedarchy-backup-*' | head -1)
[[ -n $backup_file ]] && pass "entrypoint replacement was backed up" || fail "no backup made before replacing"
# The user's original content must live in the backup; the live file now holds
# the template.
contains "$(cat "$backup_file" 2>/dev/null)" "my own entrypoint" "the backup preserves the user's original file"
not_contains "$(cat "${HOME}/.config/hypr/hyprland.lua")" "my own entrypoint" "the replaced file now holds the template"

# identical file is left alone, not churned
new_sandbox
run_installer "" --yes --profile recommended >/dev/null
before=$(stat -c %Y "${HOME}/.config/omarchy/shell.json")
sleep 1
run_installer "" --yes --profile recommended >/dev/null
after=$(stat -c %Y "${HOME}/.config/omarchy/shell.json")
check "$after" "$before" "re-install does not rewrite an identical file"

# --- wizard -----------------------------------------------------------------
echo ""
echo "[wizard] guided installation"
new_sandbox
printf 'Recommended  — the full Fedarchy experience\ny\ny\ny\ny\ny\ny\n' >"$GUM_ANSWERS"
out=$(run_installer "" --interactive --dry-run --yes)
contains "$out" "Fedarchy installer" "wizard shows a welcome screen"
contains "$out" "You choose what gets installed" "wizard states the user is in control"
contains "$out" "Components to install" "wizard renders the plan"
[[ -e $OMARCHY_PATH ]] && fail "interactive dry-run created the deployment" || pass "interactive dry-run changes nothing"

new_sandbox
printf 'Minimal       — the shell, commands and themes only\nn\nn\nn\nn\n' >"$GUM_ANSWERS"
out=$(run_installer "" --interactive --dry-run --yes)
contains "$out" "Components to install" "minimal wizard path produces a plan"

new_sandbox
printf 'Keep my setup — Fedarchy tools without its desktop configuration\nn\nn\nn\n' >"$GUM_ANSWERS"
out=$(run_installer "" --interactive --dry-run --yes)
contains "$out" "Components to install" "preserve wizard path produces a plan"

# declining an optional component must not re-enable it
new_sandbox
printf 'Recommended  — the full Fedarchy experience\nn\nn\nn\nn\nn\nn\n' >"$GUM_ANSWERS"
out=$(run_installer "" --interactive --dry-run --yes)
# Check the install list specifically: a declined component is still named in
# the "Not being changed" section, which is the point of that section.
install_list=$(sed -n '/Components to install/,/^$/p' <<<"$out")
not_contains "$install_list" "Keyboard shortcuts" "declining in the wizard removes it from the plan"
contains "$out" "Keyboard shortcuts" "a declined component is still explained"

# the wizard must never be what runs unattended
new_sandbox
out=$(run_installer "" --interactive </dev/null)
[[ -e $OMARCHY_PATH ]] && fail "unattended wizard installed something" || pass "unattended wizard installs nothing"

# --- portability ------------------------------------------------------------
echo ""
echo "[portability] relocation, spaces and alternate cwd"
new_sandbox
moved="$SANDBOX_ROOT/moved tree"
mkdir -p "$moved"
cp -a "$SRC/." "$moved/"
out=$(cd / && HOME="$SANDBOX_ROOT/home2" XDG_DATA_HOME="$SANDBOX_ROOT/home2/.local/share" \
      XDG_STATE_HOME="$SANDBOX_ROOT/home2/.local/state" OMARCHY_PATH="$SANDBOX_ROOT/home2/d" \
      bash "$moved/scripts/install.sh" --yes --profile minimal 2>&1)
check "$?" "0" "installs from a relocated path with spaces, run from /"

# --- self-test mode ---------------------------------------------------------
echo ""
echo "[--test] runs real checks without installing"
new_sandbox
out=$(run_installer "" --test 2>&1)
contains "$out" "installer self-test" "--test announces itself"
contains "$out" "installer-test.sh" "--test actually executes a suite"
new_sandbox
out=$(run_installer "" --test 2>&1)
[[ -e $OMARCHY_PATH ]] && fail "--test installed something" || pass "--test installs nothing"


# --- missing payload disposition --------------------------------------------
echo ""
echo "[payload] absent install/ references fail honestly"
# OEM provisioning was removed rather than left as a broken feature, so the
# assertions are about absence: the commands are gone and nothing reintroduces
# the payload they expected.
for cmd in omarchy-provision-owner omarchy-provision-user omarchy-provision-first-run \
           omarchy-apply-hardware omarchy-apply-system omarchy-system-factory-reset \
           omarchy-system-factory-reset-finish omarchy-drive-password omarchy-drive-select \
           omarchy-hibernation-setup omarchy-hibernation-remove omarchy-refresh-limine \
           omarchy-snapshot; do
    if [[ -e "$ROOT/bin/$cmd" ]]; then
        fail "$cmd is still present after removal"
    fi
done
pass "every removed OEM / disk / boot command is absent from bin/"
[[ -d "$ROOT/install" ]] && fail "an install/ directory was fabricated" || pass "no dummy install/ tree exists"
if grep -rqE "omarchy-(provision-|apply-hardware|apply-system|factory-reset|drive-password|drive-select|hibernation-setup|hibernation-remove|refresh-limine)" "$ROOT/default" "$ROOT/bin" 2>/dev/null; then
    fail "a surviving config or command still references a removed operation"
else
    pass "no surviving config or command references a removed operation"
fi

# --- cleanup ---------------------------------------------------------------
cleanup_all() {
    local d
    for d in "${ALL_SANDBOXES[@]:-}"; do
        [[ -n $d && -d $d ]] && rm -rf "$d"
    done
}
trap cleanup_all EXIT
cleanup_all

echo ""
echo "=== installer UX tests: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]] || exit 1