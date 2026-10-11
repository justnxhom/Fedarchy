#!/bin/bash
set -euo pipefail

# Fedarchy installer.
#
# The deployed layout is an OMARCHY_PATH checkout: the launcher, restart helper,
# Hyprland modules and Quickshell config all resolve $OMARCHY_PATH/{bin,default,
# shell}. 'install' copies that tree, 'link' points OMARCHY_PATH back at this
# checkout, and both record the result for the session.
#
# Nothing here needs root. The installer only ever writes inside the invoking
# user's home. Anything genuinely requiring elevation stays inside the omarchy-*
# commands it deploys, where it is visible and separately authorized.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
LOCAL_BIN="${HOME}/.local/bin"

# Configuration destination policy.
#
# The runtime does not follow XDG_CONFIG_HOME. 76 path expressions in bin/ and
# every QML component read ~/.config literally, Hyprland fixes its own config at
# ~/.config/hypr by upstream convention, and qt5ct/qt6ct are written by explicit
# path. Honouring XDG_CONFIG_HOME here would install the config somewhere the
# shell never reads it, so ~/.config is the single source of truth and an
# overridden XDG_CONFIG_HOME is reported rather than silently split from the
# runtime. See docs/ for the full rationale.
CONFIG_HOME="$HOME/.config"
if [[ -n ${XDG_CONFIG_HOME:-} && ${XDG_CONFIG_HOME%/} != "$CONFIG_HOME" ]]; then
    XDG_CONFIG_DIVERGED=1
fi

# Component model: one definition list shared by the wizard, the plan builder,
# --check and the tests, so the offered choices cannot drift from what runs.
# shellcheck source=scripts/install-components.sh
. "$SCRIPT_DIR/install-components.sh"

TARGET="${OMARCHY_PATH:-${DATA_HOME}/fedarchy}"
BACKUP_DIR="${FEDARCHY_BACKUP_DIR:-${CONFIG_HOME}/fedarchy-backups}"
STATE_DIR="${STATE_HOME}/fedarchy"
ENVIRONMENT_FILE="${CONFIG_HOME}/fedarchy/environment"

# --- Installation manifest -------------------------------------------------
# Resource trees copied wholesale into OMARCHY_PATH. Tests, fixtures, docs and
# development tooling are deliberately absent: nothing under $OMARCHY_PATH is
# read at runtime by those, and shipping them would make every upgrade pay for
# files the shell never opens.
DEPLOYED_DIRS=(bin config default scripts shell themes)

# User-owned destinations, deployed outside OMARCHY_PATH.
DEPLOYED_THEMES_DIR="${CONFIG_HOME}/omarchy/themes"
DEPLOYED_SHELL_JSON="${CONFIG_HOME}/omarchy/shell.json"

# Files that must exist for the deployed tree to boot. Checked in the source
# tree before anything is copied, and re-checked in the deployed tree by 'check'.
RUNTIME_CONTRACT=(
    config/omarchy/shell.json
    shell/shell.qml
    bin/omarchy-launch-shell
    bin/omarchy-restart-shell
    default/hypr/bootstrap.lua
    default/hypr/helpers.lua
    default/hypr/autostart.lua
    default/wayland-sessions/omarchy.desktop
)

# Commands the installer itself needs. rsync does the tree sync; realpath
# resolves roots; the rest are used by the checks below.
REQUIRED_COMMANDS=(rsync realpath date cmp readlink)

INSTALLER_VERSION="1.0.0"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

DRY_RUN=0
ASSUME_YES=0

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
plan() { echo -e "  ${NC}$*"; }

# Mutations funnel through here so --dry-run is a real non-mutating execution
# path rather than an install that prints less. Anything that would touch the
# filesystem goes through run_mutating; nothing else may write.
run_mutating() {
    local description="$1"
    shift
    if ((DRY_RUN)); then
        printf '  [dry-run] would %s\n' "$description"
        return 0
    fi
    "$@"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [command]

Commands:
    install     Deploy this checkout to \$OMARCHY_PATH (default: ${DATA_HOME}/fedarchy)
    link        Point \$OMARCHY_PATH at this checkout instead of copying it
    check       Verify the deployed tree against the runtime contract
    rollback    Restore the most recent backup
    uninstall   Remove the deployment and restore the previous tree
    status      Show deployment status
    list        List available backups

Commands and modes:
    install             Install, using --profile / --component to choose what.
    --interactive, -i   Guided installer: pick a profile, adjust it, review, agree.
    --check, --doctor   Read-only diagnostics of a deployed installation.
    --test              Run the installer's own isolated test suites.

Options:
    --profile <name>    Start from a profile: minimal, recommended, preserve or custom.
    --component <id>    Install exactly this component (repeatable).
    --components a,b    Same, comma-separated.
    --dry-run           Work out and print the plan without changing anything.
                        Combines with --interactive to preview a customised install.
    -y, --yes           Authorise mutations without a prompt. It does not bypass
                        preflight, safety checks or required decisions.
    --version, -V       Print the installer version.
    -h, --help          This screen.

Profiles are starting points, not commitments: every component can be added or
removed before anything is installed. Selected components and their required
dependencies are always shown in the plan for review.

Nothing is installed without your agreement, and nothing needs root: this
installer writes only inside your home directory and never installs packages.
Config files that already exist are kept unless you choose to replace them, and
anything replaced is backed up first.

Without --yes, install, link and uninstall print their plan and stop unless
they are given an interactive terminal to confirm on. A non-interactive run with
no --yes exits non-zero rather than assuming consent.

Everything is installed under the invoking user's home. No sudo is used and no
package is installed or removed by this script.
EOF
}

source_root() { realpath -e "$PROJECT_ROOT"; }
target_root() { realpath -m "${TARGET%/}"; }

# --- Preflight --------------------------------------------------------------

preflight_os() {
    local id=""
    [[ -r /etc/os-release ]] || { error "Cannot read /etc/os-release"; return 1; }
    # shellcheck disable=SC1091
    id=$(. /etc/os-release && printf '%s' "${ID:-}")
    case "$id" in
        fedora|rawhide) info "Distribution: ${PRETTY_NAME:-$id} (supported)";;
        *)
            error "Fedarchy targets Fedora; /etc/os-release reports '${id:-unknown}'."
            error "Continuing anyway would risk breaking a system this installer does not model."
            return 1
            ;;
    esac
}

preflight_privilege() {
    if ((EUID == 0)); then
        warn "Running as root. Fedarchy installs into your own home and never"
        warn "needs elevation; running as root will create root-owned files in it."
    else
        info "Running as $(id -un) (uid ${EUID}); no elevation required."
    fi
}

preflight_commands() {
    local missing=()
    local command
    for command in "${REQUIRED_COMMANDS[@]}"; do
        command -v "$command" >/dev/null 2>&1 || missing+=("$command")
    done
    if ((${#missing[@]} > 0)); then
        error "Missing required command(s): ${missing[*]}"
        error "Fedora installs them with: sudo dnf5 install ${missing[*]}"
        return 1
    fi
    info "Required commands present."
}

preflight_source() {
    local root missing=()
    root=$(source_root)
    local asset
    for asset in "${DEPLOYED_DIRS[@]}"; do
        [[ -d $root/$asset ]] || missing+=("$asset/")
    done
    for path in "${RUNTIME_CONTRACT[@]}"; do
        [[ -e $root/$path ]] || missing+=("$path")
    done
    if ((${#missing[@]} > 0)); then
        error "Not a usable Fedarchy checkout: ${root} is missing ${missing[*]}"
        return 1
    fi
    info "Source tree complete: $root"
}

# Refuse to write through a symlink that points outside the target root. A
# destination symlink left by an earlier install or by the user would otherwise
# redirect rsync's writes to an unrelated directory.
preflight_target_safety() {
    local resolved=$1
    local asset link target
    if [[ -L $resolved && ! -d $resolved ]]; then
        error "OMARCHY_PATH is a symlink to a non-directory: $resolved"
        return 1
    fi
    for asset in "${DEPLOYED_DIRS[@]}"; do
        link="${resolved}/${asset}"
        [[ -L $link ]] || continue
        target=$(readlink -f "$link" 2>/dev/null || printf '%s' "$link")
        case "$target" in
            "$resolved"/*|"$resolved") ;;
            *)
                error "Destination ${link} is a symlink pointing outside the install root:"
                error "  -> $target"
                error "Refusing to write through it. Remove or correct the link first."
                return 1
                ;;
        esac
    done
    return 0
}

preflight_space() {
    local resolved=$1
    local needed_kb available_kb
    needed_kb=$(du -sk "$(source_root)" 2>/dev/null | cut -f1)
    available_kb=$(df -Pk "$(dirname "$resolved")" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -z ${needed_kb:-} || -z ${available_kb:-} ]]; then
        return 0
    fi
    if ((available_kb < needed_kb)); then
        error "Not enough free space: need ${needed_kb}K, have ${available_kb}K"
        return 1
    fi
    info "Free space sufficient (${available_kb}K available, ${needed_kb}K needed)."
}

preflight_distinct_target() {
    local source resolved
    source=$(source_root)
    resolved=$(target_root)
    if [[ $resolved == "$source" ]]; then
        error "OMARCHY_PATH resolves to this checkout (${resolved})."
        error "Use '$(basename "$0") link' to run from the source tree, or unset OMARCHY_PATH to deploy a copy."
        return 1
    fi
}

preflight_xdg() {
    if [[ ${XDG_CONFIG_DIVERGED:-0} == 1 ]]; then
        warn "XDG_CONFIG_HOME is set to '${XDG_CONFIG_HOME}' but the runtime reads ${CONFIG_HOME}."
        warn "Fedarchy config will be installed where the shell actually looks for it."
    fi
}

preflight() {
    local resolved=$1
    local failed=0
    echo ""
    info "Preflight"
    plan ""
    preflight_os || failed=1
    preflight_privilege || failed=1
    preflight_commands || failed=1
    preflight_source || failed=1
    preflight_distinct_target || failed=1
    preflight_target_safety "$resolved" || failed=1
    preflight_space "$resolved" || failed=1
    preflight_xdg
    return $((failed > 0))
}

# --- Authorisation ----------------------------------------------------------

# Returns 0 when the caller may mutate. An interactive terminal prompts; a
# non-interactive one refuses. Empty input is not consent.
authorise() {
    local action="$1"
    if ((ASSUME_YES)); then
        info "Authorised by --yes: ${action}"
        return 0
    fi
    if [[ ! -t 0 ]]; then
        error "Refusing to ${action}: not an interactive terminal and no --yes given."
        return 1
    fi
    printf '\n%s\n' "About to ${action}. Continue? [y/N] "
    local reply=""
    IFS= read -r reply || return 1
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) info "Cancelled; nothing was changed."; return 1 ;;
    esac
}

# --- Deployment -------------------------------------------------------------

backup_target() {
    local resolved="$1"
    local backup="$BACKUP_DIR/fedarchy-$(date +%Y%m%d-%H%M%S)"

    [[ -e $resolved || -L $resolved ]] || return 0

    run_mutating "create a backup of the current deployment at ${backup}" \
        mkdir -p "$BACKUP_DIR"
    if ((DRY_RUN)); then
        printf '  [dry-run] would %s\n' "record ${backup} in ${STATE_DIR}/last-backup"
        return 0
    fi
    if [[ -L $resolved ]]; then
        ln -s "$(readlink -f "$resolved")" "$backup"
    else
        info "Creating backup: ${backup}"
        cp -a "$resolved" "$backup"
    fi
    printf '%s\n' "$backup" >"${STATE_DIR}/last-backup"
    info "Backup created."
}

# rsync --delete would remove files the user dropped into the deployed tree.
# Those are removed only into the backup that was just taken, never silently.
deploy_tree() {
    local source resolved asset
    source=$(source_root)
    resolved=$(target_root)

    for asset in "${DEPLOYED_DIRS[@]}"; do
        [[ -d $source/$asset ]] || { error "Source directory is missing: ${source}/${asset}"; return 1; }
        preflight_target_safety "$resolved" || return 1
        run_mutating "sync ${asset}/ into ${resolved}/${asset}/" \
            mkdir -p "${resolved}/${asset}"
        run_mutating "sync ${source}/${asset}/ -> ${resolved}/${asset}/" \
            rsync -a --delete "${source}/${asset}/" "${resolved}/${asset}/"
    done
}

deploy_bin_scripts() {
    local script name
    local source; source=$(source_root)
    run_mutating "create ${LOCAL_BIN}" mkdir -p "$LOCAL_BIN"
    for script in "$source"/bin/omarchy "$source"/bin/omarchy-*; do
        [[ -f $script ]] || continue
        name=$(basename "$script")
        if ((DRY_RUN)); then
            printf '  [dry-run] would install command %s -> %s\n' "$name" "${LOCAL_BIN}/${name}"
            continue
        fi
        cp "$script" "${LOCAL_BIN}/${name}"
        chmod +x "${LOCAL_BIN}/${name}"
    done
}

write_environment() {
    local resolved="$1"
    run_mutating "write the session environment file ${ENVIRONMENT_FILE}" \
        mkdir -p "$(dirname "$ENVIRONMENT_FILE")"
    ((DRY_RUN)) && return 0
    {
        printf '# Written by scripts/install.sh. Sourced by the Hyprland session.\n'
        printf "export OMARCHY_PATH='%s'\n" "${resolved//\'/\'\\\'\'}"
        printf 'export PATH="$OMARCHY_PATH/bin:$PATH"\n'
    } >"$ENVIRONMENT_FILE"
}

deploy_themes() {
    local source; source=$(source_root)
    run_mutating "sync themes/ into ${DEPLOYED_THEMES_DIR}" mkdir -p "$DEPLOYED_THEMES_DIR"
    run_mutating "sync themes -> ${DEPLOYED_THEMES_DIR}" \
        rsync -a "${source}/themes/" "${DEPLOYED_THEMES_DIR}/"
}

# The user's shell.json is authoritative once they have customised it, so an
# existing one is never overwritten. The template only seeds a missing file.
deploy_user_config() {
    run_mutating "create ${CONFIG_HOME}/omarchy" mkdir -p "${CONFIG_HOME}/omarchy"
    if [[ -f $DEPLOYED_SHELL_JSON ]]; then
        run_mutating "leave the existing ${DEPLOYED_SHELL_JSON} untouched" true
        warn "Existing config kept: ${DEPLOYED_SHELL_JSON}"
    else
        run_mutating "seed ${DEPLOYED_SHELL_JSON} from the shipped template" \
            cp "$(source_root)/config/omarchy/shell.json" "$DEPLOYED_SHELL_JSON"
    fi
}

# Persisted so `status` and `--check` can report what this installation
# included rather than guessing from the filesystem.
record_selection() {
    run_mutating "record the selected components in ${STATE_DIR}" mkdir -p "$STATE_DIR"
    ((DRY_RUN)) && return 0
    printf '%s\n' "${SELECTION[@]}" >"${STATE_DIR}/components"
    printf '%s\n' "${PROFILE_NAME:-custom}" >"${STATE_DIR}/profile"
}

record_deployment() {
    local mode="$1" resolved="$2"
    run_mutating "record deployment state under ${STATE_DIR}" mkdir -p "$STATE_DIR"
    ((DRY_RUN)) && return 0
    printf '%s\n' "$(source_root)" >"${STATE_DIR}/source-path"
    printf '%s\n' "$resolved" >"${STATE_DIR}/target-path"
    printf '%s\n' "$mode" >"${STATE_DIR}/deploy-mode"
    date -Iseconds >"${STATE_DIR}/last-deploy"
    printf 'Fedarchy deployed in %s mode from %s\n' "$mode" "$(source_root)" >"${STATE_DIR}/last-deploy-info"
}

# --- Plan rendering ---------------------------------------------------------

print_plan() {
    local resolved="$1" mode="$2"
    echo ""
    info "Planned actions (${mode})"
    plan "deploy ${DEPLOYED_DIRS[*]} -> ${resolved}"
    plan "install commands ${LOCAL_BIN}/omarchy*"
    plan "sync themes -> ${DEPLOYED_THEMES_DIR}"
    if [[ -f $DEPLOYED_SHELL_JSON ]]; then
        plan "keep existing ${DEPLOYED_SHELL_JSON}"
    else
        plan "seed ${DEPLOYED_SHELL_JSON}"
    fi
    plan "write ${ENVIRONMENT_FILE}"
    if [[ -e $resolved || -L $resolved ]]; then
        plan "back up the current deployment first"
    fi
    echo ""
}

summary() {
    local mode="$1"
    echo ""
    info "=== Deployment complete (${mode}) ==="
    info "OMARCHY_PATH: $(target_root)"
    info "Session environment file: ${ENVIRONMENT_FILE}"
    info "To restart the shell: omarchy-restart-shell"
    info "To rollback: $(basename "$0") rollback"
    info "To uninstall: $(basename "$0") uninstall"
    warn "Log out and back in (or reboot) so the session picks up the new OMARCHY_PATH."
}

# --- Commands ---------------------------------------------------------------

cmd_install() {
    local resolved; resolved=$(target_root)
    echo "=== Fedarchy Installer ==="
    echo ""
    info "Source: $(source_root)"
    info "Target: ${resolved}"

    preflight "$resolved" || { echo ""; error "Preflight failed; nothing was changed."; return 1; }

    print_plan "$resolved" deploy
    # `||` rather than `if !`: bash resets $? when `!` inverts the test, so the
    # refusal would return 0 and let a cancelled install look successful.
    if ((${#SELECTION[@]} == 0)); then
        # Non-interactive callers that did not name a profile get the
        # recommended set rather than an empty, broken install.
        select_components $(profile_components recommended)
    fi
    print_component_plan "$resolved"
    authorise "install Fedarchy to ${resolved}" || return $?

    backup_target "$resolved"
    info "Deploying Fedarchy tree..."
    deploy_tree
    info "Deploying user config..."
    deploy_user_config
    info "Deploying commands..."
    deploy_bin_scripts
    info "Deploying selected components..."
    deploy_themes_component
    deploy_hypr_config
    deploy_app_configs
    write_environment "$resolved"
    record_deployment deploy "$resolved"
    record_selection
    summary deploy
}

cmd_link() {
    local source resolved
    source=$(source_root)
    resolved=$(target_root)
    echo "=== Fedarchy Source Link ==="
    echo ""
    info "Source: ${source}"
    info "Target: ${resolved}"

    preflight "$resolved" || { echo ""; error "Preflight failed; nothing was changed."; return 1; }

    print_plan "$resolved" link
    authorise "point ${resolved} at ${source}" || return $?

    if [[ -L $resolved ]]; then
        if [[ $(readlink -f "$resolved") == "$source" ]]; then
            info "Already linked to this checkout."
        else
            warn "Replacing an existing link: $(readlink -f "$resolved")"
            run_mutating "replace the existing symlink ${resolved}" rm -f "$resolved"
            ((DRY_RUN)) || ln -s "$source" "$resolved"
        fi
    elif [[ -d $resolved ]]; then
        backup_target "$resolved"
        run_mutating "remove the previous deployment ${resolved}" rm -rf "$resolved"
        ((DRY_RUN)) || ln -s "$source" "$resolved"
    else
        run_mutating "symlink ${resolved} -> ${source}" mkdir -p "$(dirname "$resolved")"
        ((DRY_RUN)) || ln -s "$source" "$resolved"
    fi

    deploy_themes
    deploy_user_config
    deploy_bin_scripts
    write_environment "$resolved"
    record_deployment link "$resolved"
    summary link
}

cmd_check() {
    local resolved path missing=0
    resolved=$(target_root)
    echo "=== Fedarchy Deployment Check ==="
    echo ""
    if [[ ! -e $resolved ]]; then
        error "Not deployed: ${resolved}"
        return 1
    fi
    info "Target: ${resolved}"
    if [[ -L $TARGET ]]; then
        info "Mode: link -> $(readlink -f "$TARGET")"
    else
        info "Mode: deployed copy"
    fi
    for path in "${RUNTIME_CONTRACT[@]}"; do
        if [[ -e $resolved/$path ]]; then
            info "OK      $path"
        else
            error "MISSING $path"
            missing=$((missing + 1))
        fi
    done
    if [[ -f ${LOCAL_BIN}/omarchy-shell ]]; then
        info "OK      ${LOCAL_BIN}/omarchy-shell"
    else
        error "MISSING ${LOCAL_BIN}/omarchy-shell"
        missing=$((missing + 1))
    fi
    if [[ -f $ENVIRONMENT_FILE ]]; then
        info "OK      ${ENVIRONMENT_FILE}"
    else
        warn "No session environment file at ${ENVIRONMENT_FILE}"
    fi
    echo ""
    if ((missing > 0)); then
        error "${missing} runtime path(s) missing from ${resolved}"
        return 1
    fi
    info "Deployment matches the runtime contract."
}

cmd_rollback() {
    local backup
    echo "=== Fedarchy Rollback ==="
    echo ""
    if [[ ! -f ${STATE_DIR}/last-backup ]]; then
        error "No backup found. Cannot rollback."
        return 1
    fi
    backup=$(cat "${STATE_DIR}/last-backup")
    if [[ ! -e $backup ]]; then
        error "Backup is gone: ${backup}"
        return 1
    fi
    authorise "replace ${TARGET} with the backup at ${backup}" || return $?
    info "Rolling back to: ${backup}"
    rm -rf "$TARGET"
    cp -a "$backup" "$TARGET"
    info "Rollback complete."
    info "Restart the shell to apply."
}

cmd_uninstall() {
    local backup name resolved; resolved=$(target_root)
    echo "=== Fedarchy Uninstall ==="
    echo ""
    print_plan "$resolved" uninstall
    authorise "remove the deployment at ${resolved}" || return $?

    if [[ -L $resolved ]]; then
        info "Removing link: ${resolved} -> $(readlink -f "$resolved")"
        rm -f "$resolved"
    elif [[ -d $resolved ]]; then
        info "Removing deployment: ${resolved}"
        rm -rf "$resolved"
    fi

    if [[ -f ${STATE_DIR}/deployed-bins ]]; then
        while IFS= read -r name; do
            [[ -n $name ]] || continue
            [[ -e ${LOCAL_BIN}/$name ]] || continue
            if cmp -s "${LOCAL_BIN}/$name" "$(source_root)/bin/$name" 2>/dev/null; then
                rm -f "${LOCAL_BIN}/$name"
                info "Removed ${name}"
            else
                warn "Left ${name}: it differs from the checkout copy"
            fi
        done <"${STATE_DIR}/deployed-bins"
        rm -f "${STATE_DIR}/deployed-bins"
    fi

    rm -f "$ENVIRONMENT_FILE"
    info "Removed ${ENVIRONMENT_FILE}"

    if [[ -f ${STATE_DIR}/last-backup ]]; then
        backup=$(cat "${STATE_DIR}/last-backup")
        if [[ -d $backup ]]; then
            cp -a "$backup" "$resolved"
            info "Previous deployment restored from: ${backup}"
        fi
    else
        warn "No backup recorded; the previous deployment was not restored."
    fi

    info "Fedarchy uninstalled."
    info "Backups are kept in ${BACKUP_DIR}."
}

cmd_status() {
    local resolved; resolved=$(target_root)
    echo "=== Fedarchy Status ==="
    echo ""
    [[ -f ${STATE_DIR}/last-deploy ]] && info "Last deployed: $(cat "${STATE_DIR}/last-deploy")" || warn "Not yet deployed."
    if [[ -f ${STATE_DIR}/source-path ]]; then info "Source: $(cat "${STATE_DIR}/source-path")"; fi
    if [[ -f ${STATE_DIR}/deploy-mode ]]; then info "Mode: $(cat "${STATE_DIR}/deploy-mode")"; fi
    if [[ -e $resolved ]]; then
        info "Target exists: ${resolved}"
        if [[ -L $resolved ]]; then info "Link target: $(readlink -f "$resolved")"; fi
    else
        warn "Target not found: ${resolved}"
    fi
    if [[ -f ${STATE_DIR}/last-backup ]]; then info "Backup: $(cat "${STATE_DIR}/last-backup")"; fi
    if [[ -f $ENVIRONMENT_FILE ]]; then
        info "Session environment: ${ENVIRONMENT_FILE}"
    else
        warn "No session environment file; the session still uses its own OMARCHY_PATH."
    fi
    return 0
}

cmd_list() {
    local backup count=0
    echo "=== Fedarchy Backups ==="
    echo ""
    if [[ ! -d $BACKUP_DIR ]]; then
        warn "No backups found."
        return 0
    fi
    for backup in "$BACKUP_DIR"/fedarchy-*; do
        [[ -e $backup ]] || continue
        echo "  $(basename "$backup")"
        count=$((count + 1))
    done
    if ((count == 0)); then
        warn "No backups found."
    else
        info "${count} backup(s) found. Backups are never pruned automatically."
    fi
}

# --- Component selection ----------------------------------------------------

# Selected component ids, expanded to include dependencies and required parts.
SELECTION=()
PROFILE_NAME=""

has_component() {
    local want="$1" id
    local id
    for id in ${SELECTION[@]:-}; do
        if [[ $id == "$want" ]]; then
            return 0
        fi
    done
    return 1
}

select_components() {
    SELECTION=($(resolve_dependencies "$@"))
}

# --- Component-aware deployment --------------------------------------------
#
# Each component deploys only its own files. Nothing here runs for a component
# the user did not choose, which is what makes a partial install actually
# partial rather than merely quieter.

# Conflict policy for a user configuration file:
#   keep    leave the user's file alone (default)
#   seed    copy the template only when nothing is there yet
#   replace back up the user's file, then install the template
# Backups are named to the second, so two operations in the same second would
# otherwise produce the same path and the second `cp` would silently overwrite
# the first -- losing the very file the earlier backup existed to preserve.
unique_backup() {
    local target="$1" candidate n=1
    candidate="${target}.fedarchy-backup-$(date +%Y%m%d-%H%M%S)"
    while [[ -e $candidate ]]; do
        candidate="${target}.fedarchy-backup-$(date +%Y%m%d-%H%M%S)-${n}"
        n=$((n + 1))
    done
    printf '%s\n' "$candidate"
}

conflict_apply() {
    local source_file="$1" dest_file="$2" policy="${3:-keep}" label="${4:-$2}"

    if [[ ! -e $dest_file ]]; then
        run_mutating "install ${label}" mkdir -p "$(dirname "$dest_file")"
        run_mutating "install ${label} from the shipped template" cp "$source_file" "$dest_file"
        return 0
    fi

    if cmp -s "$source_file" "$dest_file"; then
        plan "keep ${label} (already identical to the template)"
        return 0
    fi

    case "$policy" in
        seed)
            plan "keep your existing ${label}"
            warn "Kept your ${label}; the shipped template was not applied."
            ;;
        replace)
            local backup
            backup=$(unique_backup "$dest_file")
            run_mutating "back up ${label} to ${backup}" cp -a "$dest_file" "$backup"
            run_mutating "replace ${label} with the template" cp "$source_file" "$dest_file"
            ;;
        *)
            plan "keep your existing ${label}"
            ;;
    esac
}

deploy_hypr_config() {
    local source rel dest
    source=$(source_root)/config/hypr
    has_component hypr-config || return 0

    if [[ ! -d $source ]]; then
        # This checkout has no Hyprland templates. Skip the component rather than
        # abandoning an install whose other parts are fine; say so plainly.
        warn "No Hyprland configuration templates in this checkout; skipping that component."
        return 0
    fi

    for rel in "$source"/*; do
        [[ -f $rel ]] || continue
        dest="${CONFIG_HOME}/hypr/$(basename "$rel")"
        # hyprland.lua is the entrypoint that requires the other modules, so it
        # is the one file whose replacement can change how the session starts.
        if [[ $(basename "$rel") == "hyprland.lua" ]]; then
            # Compare modulo the keybinding flag. This file is the one destination
            # the installer edits itself, so treating that edit as drift would
            # back up and rewrite the entrypoint on every re-install, undoing and
            # redoing the same change each time.
            if [[ -f $dest ]] && diff -q <(sed 's/^[[:space:]]*omarchy_default_bindings[[:space:]]*=[[:space:]]*false/-- omarchy_default_bindings = false/' "$dest") "$rel" >/dev/null 2>&1; then
                plan "keep Hyprland entrypoint (matches the template apart from the keybinding setting)"
            else
                conflict_apply "$rel" "$dest" replace "Hyprland entrypoint"
            fi
        else
            conflict_apply "$rel" "$dest" keep "Hyprland $(basename "$rel")"
        fi
    done

    apply_keybinding_choice
}

# Declining Fedarchy's keybindings has to reach Hyprland as a global set before
# the defaults are loaded: default/hypr/omarchy.lua wraps every default binding in
# `if _G.omarchy_default_bindings ~= false`, and the user's entrypoint reads the
# flag above its require("default.hypr.omarchy").
#
# The flag ships commented out in the template, so enabling that one line is the
# whole change. It keeps every module import and every other module intact --
# the entrypoint still requires monitors, input, bindings, looknfeel and
# autostart, and hypr/bindings.lua remains available for the user's own
# overrides. Nothing is removed; the defaults simply stop being defined.
KEYBINDING_FLAG_LINE='omarchy_default_bindings = false'

apply_keybinding_choice() {
    local entry="${CONFIG_HOME}/hypr/hyprland.lua"

    if ! has_component hypr-config; then
        return 0    # no Hyprland config installed, so there is nothing to set
    fi
    if has_component keybindings; then
        plan "keep Fedarchy's keyboard shortcuts"
        return 0
    fi

    plan "turn Fedarchy's keyboard shortcuts off in ${entry}"

    if [[ ! -f $entry ]]; then
        warn "No Hyprland entrypoint at ${entry}; keybindings were left untouched."
        return 0
    fi

    # Already switched off, whether we wrote it or the user did.
    if grep -qE '^[[:space:]]*omarchy_default_bindings[[:space:]]*=[[:space:]]*false' "$entry"; then
        plan "keyboard shortcuts already disabled; no change needed"
        return 0
    fi

    if ! grep -qF -- "-- ${KEYBINDING_FLAG_LINE}" "$entry"; then
        warn "Cannot apply the keybinding choice automatically."
        warn "${entry} has no commented '${KEYBINDING_FLAG_LINE}' line to enable."
        warn "Add it above the require(\"default.hypr.omarchy\") call by hand."
        return 0
    fi

    local backup
    backup=$(unique_backup "$entry")
    run_mutating "back up ${entry} to ${backup}" cp -a "$entry" "$backup"
    if ((DRY_RUN)); then
        return 0
    fi

    # Enable the shipped line in place. Anchored to the commented form so a
    # second run has nothing left to match, and the surrounding text is untouched.
    if ! sed -i "0,/^[[:space:]]*--[[:space:]]*${KEYBINDING_FLAG_LINE//./\\.}\$/s//${KEYBINDING_FLAG_LINE}/" "$entry"; then
        error "Could not update ${entry}"
        return 1
    fi
    info "Fedarchy's default keybindings are switched off for you."
    info "Backup: ${backup}"
}

deploy_app_configs() {
    local source dir rel dest count=0
    source=$(source_root)/config
    has_component app-configs || return 0

    # hypr and omarchy have their own component with its own conflict policy, and
    # shell.json is handled by deploy_user_config.
    for dir in "$source"/*/; do
        dir="${dir%/}"
        local name; name=$(basename "$dir")
        case "$name" in
            hypr|omarchy|autostart) continue ;;
        esac
        [[ -d $dir ]] || continue
        for rel in "$dir"/*; do
            [[ -f $rel ]] || continue
            dest="${CONFIG_HOME}/${name}/$(basename "$rel")"
            conflict_apply "$rel" "$dest" keep "${name} configuration"
            count=$((count + 1))
        done
    done
    if ((count > 0)); then
        info "Applied ${count} application configuration file(s)."
    fi
    return 0
}

deploy_themes_component() {
    has_component themes || { plan "skip themes (not selected)"; return 0; }
    deploy_themes
}

# --- Plan rendering ---------------------------------------------------------

# Renders the full plan, grouped so a consequential system-level action is not
# buried among routine file copies.
print_component_plan() {
    local resolved="$1" id note

    echo ""
    info "Installation plan"
    echo ""

    echo "  ${BOLD}Components to install${NC}"
    for id in "${SELECTION[@]}"; do
        printf '    %-26s %s\n' "$(component_label "$id")" "$(component_desc "$id")"
    done

    echo ""
    echo "  ${BOLD}What this changes on your system${NC}"
    printf '    %-26s %s\n' "Fedarchy files" "$resolved"
    printf '    %-26s %s\n' "Commands" "${LOCAL_BIN}/omarchy*"
    for id in "${SELECTION[@]}"; do
        case "$id" in
            themes) printf '    %-26s %s\n' "Theme files" "$DEPLOYED_THEMES_DIR" ;;
            hypr-config|keybindings) printf '    %-26s %s\n' "Hyprland config" "${CONFIG_HOME}/hypr" ;;
            app-configs) printf '    %-26s %s\n' "App config" "${CONFIG_HOME}/<app>" ;;
        esac
    done
    printf '    %-26s %s\n' "Session environment" "$ENVIRONMENT_FILE"

    local skipped=0
    for id in $(component_ids); do
        if has_component "$id"; then
            continue
        fi
        skipped=$((skipped + 1))
        :
    done
    if ((skipped > 0)); then
        echo ""
        echo "  ${BOLD}Not being changed${NC}"
        for id in $(component_ids); do
            has_component "$id" && continue
            :
            note=$(component_skipped_note "$id" 2>/dev/null || true)
            printf '    %-26s %s\n' "$(component_label "$id")" "${note:-left at your current setting}"
        done
    fi

    echo ""
    echo "  ${BOLD}Your existing files${NC}"
    echo "    Config files that already exist are never overwritten silently."
    echo "    Anything replaced is backed up next to the original first."
    echo ""
    echo "  ${BOLD}Privileged operations${NC}"
    echo "    None. This installer never uses sudo and never installs packages."
    echo "    Any system change a deployed command makes is separate and asks you then."
    echo ""
}

# --- Interactive wizard -----------------------------------------------------

# gum has no multiselect, so optional components are chosen with a loop of
# yes/no questions. Kept short: the profiles do the bulk of the work, and the
# loop only asks about what the profile left out.
wizard_choose_components() {
    local id label selected dep
    for id in $(component_ids); do
        # Under `set -e` a false `test && action` aborts the whole function, so
        # membership tests must invert rather than short-circuit.
        if component_required "$id"; then
            continue
        fi
        label=$(component_label "$id")
        selected=0
        local suggested=0
        local candidate
        for candidate in ${PROFILE_SET[@]:-}; do
            if [[ $candidate == "$id" ]]; then
                suggested=1
                break
            fi
        done
        if ((suggested)); then
            selected=1
        fi

        # Every optional component is asked about. Suppressing the question when
        # a dependency is not yet selected made the answer depend on evaluation
        # order; dependencies are resolved after the loop and any component they
        # pull in is announced, so nothing is added quietly.

        printf '\n  %s\n' "$label"
        printf '    %s\n' "$(component_desc "$id")"
        printf '    %s\n' "$(component_why "$id")"
        dep=$(component_depends "$id")
        if [[ -n $dep ]]; then
            printf '    %s\n' "(also needs: $(component_label "$dep"))"
        fi

        if ((selected)); then
            printf '    [%s]\n' "${DIM}currently selected${NC}"
            gum confirm --default=true "Include ${label}?" && selected=1 || selected=0
        else
            gum confirm --default=false "Include ${label}?" && selected=1 || selected=0
        fi

        if ((selected)); then
            COMPONENT_PICKS+=("$id")
        fi
    done
}


# Hyprland software and Hyprland configuration are separate decisions, and the
# default is to leave both alone.
wizard_hyprland() {
    printf '\n  %s\n' "Hyprland"
    cat <<'TXT'
    Fedarchy can work with a Hyprland you already have. It never replaces or
    upgrades Hyprland, and never changes your repositories.

    Nothing about Hyprland is touched unless you choose to install Fedarchy's
    Hyprland configuration, and that is asked separately below.
TXT
    printf '    Detected: %s\n' "$(hyprland_version 2>/dev/null || printf 'Hyprland not detected')"
}

hyprland_version() {
    hyprctl version 2>/dev/null | head -1 | cut -c1-60
}

cmd_interactive() {
    local choice profile

    printf '%s\n' "${BOLD}=============================================${NC}"
    printf '%s\n' "${BOLD}  Fedarchy installer${NC}"
    printf '%s\n' "${BOLD}=============================================${NC}"
    cat <<'TXT'

  Fedarchy is a complete Fedora desktop: a shell with panels, widgets and
  notifications, plus a set of command-line tools that manage it.

  You choose what gets installed. Nothing is applied until you have reviewed
  a summary and agreed to it, and your existing settings are kept unless you
  say otherwise.

TXT

    if ((DRY_RUN)); then
        printf '  %sDRY RUN — nothing will be written to your system.%s\n' "$YELLOW" "$NC"
        printf '\n'
    fi

    printf '  How would you like to start?\n\n'
    choice=$(gum choose --header "Installation profile" \
        "Recommended  — the full Fedarchy experience" \
        "Minimal       — the shell, commands and themes only" \
        "Keep my setup — Fedarchy tools without its desktop configuration" \
        "Custom        — pick each component yourself") || {
        printf '\n  Cancelled. Nothing was changed.\n\n'; return 0; }

    case "$choice" in
        Recommended*) profile="recommended" ;;
        Minimal*)     profile="minimal" ;;
        "Keep my"*)   profile="preserve" ;;
        Custom*)      profile="" ;;
    esac
    PROFILE_NAME="${profile:-custom}"

    PROFILE_SET=()
    COMPONENT_PICKS=()
    if [[ -n $profile ]]; then
        local id
        while IFS= read -r id; do PROFILE_SET+=("$id"); done < <(profile_components "$profile")
    fi

    wizard_hyprland

    printf '\n  Choose any additional components.\n'
    wizard_choose_components

    # Report anything the user's choices pulled in indirectly, rather than
    # silently adding it to the plan.
    local requested=" ${COMPONENT_PICKS[*]:-} " id added=""
    while IFS= read -r id; do
        [[ -n $id ]] || continue
        [[ $requested == *" $id "* ]] || added+=" $id"
    done < <(resolve_dependencies "${COMPONENT_PICKS[@]:-}")
    for id in $added; do
        printf '  Note: %s is also required by something you selected.\n' "$(component_label "$id")"
    done

    select_components "${COMPONENT_PICKS[@]}"

    printf '\n'
    authorise "install Fedarchy to $(target_root)" || return $?

    cmd_install
}

# --- Entry point ------------------------------------------------------------

command="install"
profile=""
components=()
while (($#)); do
    case "$1" in
        --dry-run)  DRY_RUN=1 ;;
        -y|--yes)   ASSUME_YES=1 ;;
        --interactive|-i) command="interactive" ;;
        --profile)  shift; profile="$1" ;;
        --profile=*) profile="${1#*=}" ;;
        --component) shift; components+=("$1") ;;
        --component=*) components+=("${1#*=}") ;;
        --components) shift; IFS=, read -r -a components <<<"$1" ;;
        --check|--doctor) command="check" ;;
        --test)     command="test" ;;
        --version|-V) printf 'Fedarchy installer %s\n' "$INSTALLER_VERSION"; exit 0 ;;
        -h|--help)  usage; exit 0 ;;
        --)         shift; command="${1:-install}"; break ;;
        -*)         error "Unknown option: $1"; usage; exit 1 ;;
        *)          command="$1" ;;
    esac
    shift
done

if [[ -n $profile ]]; then
    if ! profile_components "$profile" >/dev/null; then
        error "Unknown profile: ${profile}. Choose from: minimal, recommended, preserve, custom."
        exit 1
    fi
    PROFILE_NAME="$profile"
    select_components $(profile_components "$profile")
elif ((${#components[@]} > 0)); then
    PROFILE_NAME="custom"
    select_components "${components[@]}"
fi

# --test runs the real isolated suites; it never installs anything.
if [[ $command == "test" ]]; then
    echo "=== Fedarchy installer self-test ==="
    echo "(isolated: temporary directories and stubbed commands only)"
    echo ""
    rc=0
    for suite in installer-test.sh installer-ux-test.sh; do
        printf -- "--- %s ---\n" "$suite"
        if timeout 2400 bash "$(dirname "${BASH_SOURCE[0]}")/../tests/$suite"; then
            printf -- "--- %s: OK ---\n\n" "$suite"
        else
            printf -- "--- %s: FAILED ---\n\n" "$suite"
            rc=1
        fi
    done
    exit $rc
fi

((DRY_RUN)) && echo "=== Fedarchy Installer (dry run — nothing will be modified) ==="

case "$command" in
    interactive) cmd_interactive ;;
    install)    cmd_install ;;
    link)       cmd_link ;;
    check)      cmd_check ;;
    rollback)   cmd_rollback ;;
    uninstall)  cmd_uninstall ;;
    status)     cmd_status ;;
    list)       cmd_list ;;
    *)          error "Unknown command: $command"; usage; exit 1 ;;
esac