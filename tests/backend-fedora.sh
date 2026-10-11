#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MOCK="$TMP/bin"
mkdir -p "$MOCK"
export PATH="$MOCK:$ROOT/bin:/usr/bin:/bin"

status=0
output=""
run() {
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
}
assert_status() {
  [[ $status == "$1" ]] || { printf 'expected status %s, got %s\n%s\n' "$1" "$status" "$output" >&2; exit 1; }
}
assert_contains() {
  [[ $output == *"$1"* ]] || { printf 'missing %q in output:\n%s\n' "$1" "$output" >&2; exit 1; }
}
assert_not_contains() {
  [[ $output != *"$1"* ]] || { printf 'unexpected %q in output:\n%s\n' "$1" "$output" >&2; exit 1; }
}
assert_file() {
  [[ -f $1 ]] || { printf 'missing file: %s\n' "$1" >&2; exit 1; }
}
assert_empty_file() {
  [[ ! -s $1 ]] || { printf 'file is not empty: %s\n%s\n' "$1" "$(<"$1")" >&2; exit 1; }
}
reset_mocks() {
  rm -f "$MOCK"/*
}

cat > "$MOCK/sudo" <<'MOCK_SUDO'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$SUDO_LOG"
if [[ ${1:-} == install || ${1:-} == cp ]]; then
  exit 0
fi
exec "$@"
MOCK_SUDO
chmod +x "$MOCK/sudo"

cat > "$MOCK/dnf5" <<'MOCK_DNF'
#!/bin/bash
printf '%s\n' "$*" >> "$DNF_LOG"
case ${1:-} in
  copr)
    [[ ${DNF_COPR_FAIL:-0} != 1 ]]
    ;;
  install|remove)
    if [[ ${PKG_OP_FAIL:-0} == 1 ]]; then
      exit 7
    fi
    ;;
  repoquery)
    [[ ${QUERY_FAIL:-0} != 1 ]] || exit 7
    printf 'demo-package\n'
    ;;
  autoremove)
    # AUTOREMOVE_MODE covers the three states omarchy-update-orphan-pkgs must
    # tell apart: nothing to remove, a real orphan listing (which --assumeno
    # declines with a non-zero status), and a failed query.
    case ${AUTOREMOVE_MODE:-nothing} in
      orphans)
        printf 'Removing unused dependencies:\norphan-demo.x86_64\n'
        exit 1
        ;;
      fail)
        printf "Error: Failed to download metadata for repo 'updates'\n" >&2
        exit 1
        ;;
      *)
        printf 'Nothing to do.\n'
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
MOCK_DNF
chmod +x "$MOCK/dnf5"

cat > "$MOCK/rpm" <<'MOCK_RPM'
#!/bin/bash
if [[ ${1:-} == -qa ]]; then
  [[ ${RPM_QUERY_FAIL:-0} != 1 ]] || exit 7
  printf 'demo-package\n'
  exit 0
fi
if [[ ${1:-} == -q ]]; then
  [[ ${RPM_PRESENT:-0} == 1 ]] || exit 1
  exit 0
fi
exit 0
MOCK_RPM
chmod +x "$MOCK/rpm"

cat > "$MOCK/fzf" <<'MOCK_FZF'
#!/bin/bash
case ${FZF_MODE:-select} in
  cancel) exit 130 ;;
  *) printf 'demo-package\n' ;;
esac
MOCK_FZF
chmod +x "$MOCK/fzf"

cat > "$MOCK/omarchy-pkg-add" <<'MOCK_PKG_ADD'
#!/bin/bash
[[ ${PKG_OP_FAIL:-0} != 1 ]] || exit 9
MOCK_PKG_ADD
chmod +x "$MOCK/omarchy-pkg-add"

cat > "$MOCK/omarchy-pkg-drop" <<'MOCK_PKG_DROP'
#!/bin/bash
[[ ${PKG_OP_FAIL:-0} != 1 ]] || exit 9
MOCK_PKG_DROP
chmod +x "$MOCK/omarchy-pkg-drop"

cat > "$MOCK/omarchy-update-lock" <<'MOCK_LOCK'
#!/bin/bash
case ${1:-} in
  held) exit 0 ;;
  run|run-wait) shift; exec "$@" ;;
  *) exit 2 ;;
esac
MOCK_LOCK
chmod +x "$MOCK/omarchy-update-lock"

cat > "$MOCK/omarchy-show-done" <<'MOCK_DONE'
#!/bin/bash
printf '%s\n' "$*" >> "$DONE_LOG"
MOCK_DONE
chmod +x "$MOCK/omarchy-show-done"

cat > "$MOCK/omarchy-sudo-keepalive" <<'MOCK_KEEPALIVE'
#!/bin/bash
return 0
MOCK_KEEPALIVE
chmod +x "$MOCK/omarchy-sudo-keepalive"

cat > "$MOCK/omarchy-theme-set-browser" <<'MOCK_BROWSER_THEME'
#!/bin/bash
exit 0
MOCK_BROWSER_THEME
chmod +x "$MOCK/omarchy-theme-set-browser"

cat > "$MOCK/omarchy-cmd-missing" <<'MOCK_CMD_MISSING'
#!/bin/bash
exit 1
MOCK_CMD_MISSING
chmod +x "$MOCK/omarchy-cmd-missing"

cat > "$MOCK/fwupdmgr" <<'MOCK_FWUPDMGR'
#!/bin/bash
printf '%s\n' "$*"
MOCK_FWUPDMGR
chmod +x "$MOCK/fwupdmgr"

cat > "$MOCK/omarchy-update-dnf" <<'MOCK_UPDATE_DNF'
#!/bin/bash
printf '%s\n' "$*" >> "$UPDATE_DNF_LOG"
MOCK_UPDATE_DNF
chmod +x "$MOCK/omarchy-update-dnf"

cat > "$MOCK/omarchy-copr-list" <<'MOCK_COPR_LIST'
#!/bin/bash
printf 'copr:copr.fedorainfracloud.org:owner/name\n'
MOCK_COPR_LIST
chmod +x "$MOCK/omarchy-copr-list"

cat > "$MOCK/omarchy-copr-disable" <<'MOCK_COPR_DISABLE'
#!/bin/bash
printf '%s\n' "$*" >> "$COPR_DISABLE_LOG"
MOCK_COPR_DISABLE
chmod +x "$MOCK/omarchy-copr-disable"

cat > "$MOCK/gum" <<'MOCK_GUM'
#!/bin/bash
case ${1:-} in
  choose) printf 'copr:copr.fedorainfracloud.org:owner/name\n' ;;
  confirm) exit 1 ;;
esac
MOCK_GUM
chmod +x "$MOCK/gum"

cat > "$MOCK/pgrep" <<'MOCK_PGREP'
#!/bin/bash
if [[ ${MIGRATE_PGREP_MODE:-finish} == always ]]; then
  printf '1234\n'
  exit 0
fi
if [[ ! -f $PGREP_COUNT ]]; then
  printf '1234\n'
  : > "$PGREP_COUNT"
  exit 0
fi
exit 1
MOCK_PGREP
chmod +x "$MOCK/pgrep"

cat > "$MOCK/sleep" <<'MOCK_SLEEP'
#!/bin/bash
exit 0
MOCK_SLEEP
chmod +x "$MOCK/sleep"

cat > "$MOCK/omarchy-notification-dismiss" <<'MOCK_DISMISS'
#!/bin/bash
exit 0
MOCK_DISMISS
chmod +x "$MOCK/omarchy-notification-dismiss"

cat > "$MOCK/omarchy-update-confirm" <<'MOCK_CONFIRM'
#!/bin/bash
exit 1
MOCK_CONFIRM
chmod +x "$MOCK/omarchy-update-confirm"

cat > "$MOCK/omarchy-update-requires-free-space" <<'MOCK_SPACE'
#!/bin/bash
exit 0
MOCK_SPACE
chmod +x "$MOCK/omarchy-update-requires-free-space"

cat > "$MOCK/omarchy-update-stay-awake" <<'MOCK_AWAKE'
#!/bin/bash
exit 0
MOCK_AWAKE
chmod +x "$MOCK/omarchy-update-stay-awake"

cat > "$MOCK/flatpak" <<'MOCK_FLATPAK'
#!/bin/bash
exit 7
MOCK_FLATPAK
chmod +x "$MOCK/flatpak"

for command in systemctl dropbox-cli tailscale mise omarchy-plugin-enable omarchy-plugin-disable omarchy-webapp-install omarchy-webapp-remove; do
  cat > "$MOCK/$command" <<MOCK_COMMAND
#!/bin/bash
exit 0
MOCK_COMMAND
  chmod +x "$MOCK/$command"
done

export SUDO_LOG="$TMP/sudo.log"
export DNF_LOG="$TMP/dnf.log"
export DONE_LOG="$TMP/done.log"
export UPDATE_DNF_LOG="$TMP/update-dnf.log"
export COPR_DISABLE_LOG="$TMP/copr-disable.log"
export PGREP_COUNT="$TMP/pgrep-count"

run env OMARCHY_UPDATE_LOGGED=1 bash "$ROOT/bin/omarchy-update"
assert_status 1
assert_contains "Update cancelled."

mkdir -p "$TMP/migrations/migrations" "$TMP/migrations-state"
printf '#!/bin/bash\nexit 0\n' > "$TMP/migrations/migrations/001-test.sh"
chmod +x "$TMP/migrations/migrations/001-test.sh"
run env OMARCHY_PATH="$TMP/migrations" OMARCHY_MIGRATION_STATE="$TMP/migrations-state" MIGRATE_PGREP_MODE=finish bash "$ROOT/bin/omarchy-migrate"
assert_status 0
assert_file "$TMP/migrations-state/001-test.sh"
rm -f "$TMP/migrations-state/001-test.sh"
run env OMARCHY_PATH="$TMP/migrations" OMARCHY_MIGRATION_STATE="$TMP/migrations-state" MIGRATE_PGREP_MODE=always bash "$ROOT/bin/omarchy-migrate"
assert_status 1
assert_not_contains "Running migration"
assert_file "$TMP/migrations/migrations/001-test.sh"
run env OMARCHY_PATH="$TMP/migrations" OMARCHY_MIGRATION_STATE="$TMP/migrations-state" bash "$ROOT/bin/omarchy-migrate" --pending
assert_status 0
assert_contains "001-test.sh"
touch "$TMP/migrations-state/001-test.sh"
run env OMARCHY_PATH="$TMP/migrations" OMARCHY_MIGRATION_STATE="$TMP/migrations-state" bash "$ROOT/bin/omarchy-migrate" --pending
assert_status 1

run bash "$ROOT/bin/omarchy-copr-disable-menu"
assert_status 0
assert_file "$TMP/copr-disable.log"
grep -Fxq owner/name "$TMP/copr-disable.log"

run env DNF_COPR_FAIL=1 OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-channel-set" stable
assert_status 1
assert_contains "channel switch did not complete"

run bash "$ROOT/bin/omarchy-update-firmware"
assert_status 0
assert_contains "refresh --force"
assert_contains "update"
assert_not_contains "/boot/EFI/arch"

printf 'dracut: FATAL: failed to create initramfs image\n' > "$TMP/update.log"
run env OMARCHY_UPDATE_LOG="$TMP/update.log" bash "$ROOT/bin/omarchy-update-analyze-logs"
assert_status 1
assert_contains "Fedora initramfs generation failed"
rm -f "$TMP/update.log"
run env OMARCHY_UPDATE_LOG="$TMP/update.log" bash "$ROOT/bin/omarchy-update-analyze-logs"
assert_status 1
assert_contains "missing or unreadable"
printf 'dracut: Generating initramfs image\n' > "$TMP/update.log"
run env OMARCHY_UPDATE_LOG="$TMP/update.log" bash "$ROOT/bin/omarchy-update-analyze-logs"
assert_status 0

run bash "$ROOT/bin/omarchy-pkg-add"
assert_status 1
run bash "$ROOT/bin/omarchy-pkg-drop"
assert_status 1

run env QUERY_FAIL=1 bash "$ROOT/bin/omarchy-pkg-install"
assert_status 1
assert_contains "Package query failed"
run env FZF_MODE=cancel bash "$ROOT/bin/omarchy-pkg-install"
assert_status 130
assert_contains "Package selection cancelled"
run env RPM_QUERY_FAIL=1 bash "$ROOT/bin/omarchy-pkg-remove"
assert_status 1
assert_contains "Package query failed"
run env FZF_MODE=cancel bash "$ROOT/bin/omarchy-pkg-remove"
assert_status 130
assert_contains "Package selection cancelled"
: > "$DONE_LOG"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-pkg-install"
assert_status 123
assert_not_contains "0"
assert_empty_file "$DONE_LOG"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-pkg-remove"
assert_status 123
assert_empty_file "$DONE_LOG"

run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-install-service-dropbox"
assert_status 9
assert_not_contains "Adding Dropbox"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-remove-service-dropbox"
assert_status 9
assert_not_contains "Dropbox has been removed"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-install-service-tailscale"
assert_status 9
assert_not_contains "Starting Tailscale"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-remove-service-tailscale"
assert_status 9
assert_not_contains "Tailscale has been removed"
run env PKG_OP_FAIL=1 RPM_PRESENT=0 bash "$ROOT/bin/omarchy-install-service-once"
assert_status 7
assert_not_contains "Enabling ONCE"
run env PKG_OP_FAIL=1 RPM_PRESENT=0 bash "$ROOT/bin/omarchy-install-service-nordvpn"
assert_status 7
assert_not_contains "Enabling NordVPN"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-install-dev-env" php
assert_status 9
assert_not_contains "Added Composer"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-remove-dev-env" php
assert_status 9
assert_not_contains "Done!"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-install-gaming-heroic"
assert_status 9
assert_not_contains "gtk-launch"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-remove-gaming-heroic"
assert_status 9
assert_not_contains "has been removed"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-install-ai-t3-code"
assert_status 9
assert_not_contains "Matching T3 Code"
run env PKG_OP_FAIL=1 bash "$ROOT/bin/omarchy-remove-ai-t3-code"
assert_status 9
assert_not_contains "has been removed"

run env OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-install-browser" firefox
assert_status 0
assert_contains "Firefox browser installed"
[[ $(grep -Fc 'browser-policy.sh' "$ROOT/bin/omarchy-install-browser") == 0 ]]
grep -q 'omarchy-pkg-add firefox' "$ROOT/bin/omarchy-install-browser"
grep -q 'flatpak install -y flathub io.github.nickvision.zen' "$ROOT/bin/omarchy-install-browser"

mkdir -p "$TMP/reinstall/install"
printf '# packages\n demo-package \nother-package\n' > "$TMP/reinstall/install/omarchy-base.packages"
: > "$UPDATE_DNF_LOG"
run env OMARCHY_PATH="$TMP/reinstall" bash "$ROOT/bin/omarchy-reinstall-pkgs"
assert_status 0
grep -Fxq "distro-sync -y" "$UPDATE_DNF_LOG"
grep -Fxq "install -y --skip-broken demo-package other-package" "$UPDATE_DNF_LOG"
rm -f "$TMP/reinstall/install/omarchy-base.packages"
: > "$UPDATE_DNF_LOG"
run env OMARCHY_PATH="$TMP/reinstall" bash "$ROOT/bin/omarchy-reinstall-pkgs"
assert_status 1
assert_empty_file "$TMP/update-dnf.log"
printf 'bad package name with spaces\n' > "$TMP/reinstall/install/omarchy-base.packages"
run env OMARCHY_PATH="$TMP/reinstall" bash "$ROOT/bin/omarchy-reinstall-pkgs"
assert_status 1
assert_empty_file "$TMP/update-dnf.log"

unset XDG_RUNTIME_DIR XDG_STATE_HOME
export HOME="$TMP/home"
mkdir -p "$HOME"
run bash "$ROOT/bin/omarchy-update-lock" run true
assert_status 0
assert_file "$HOME/.local/state/omarchy/locks/omarchy-update.lock"
[[ $(grep -Fc '${XDG_RUNTIME_DIR:-/tmp}' "$ROOT/bin/omarchy-update-lock") == 0 ]]
[[ $(grep -Fc '${XDG_RUNTIME_DIR:-/tmp}' "$ROOT/bin/omarchy-system-lock") == 0 ]]

# Orphan review must not report a failed query as a list of orphans, and
  # must not offer to remove packages it never enumerated.
  AUTOREMOVE_MODE=fail run bash "$ROOT/bin/omarchy-update-orphan-pkgs"
  assert_status 1
  assert_contains "Could not check for orphaned packages"
  assert_not_contains "Orphaned packages found"
  AUTOREMOVE_MODE=nothing run bash "$ROOT/bin/omarchy-update-orphan-pkgs"
  assert_status 0
  assert_not_contains "Orphaned packages found"
  # A real listing still reaches the review flow even though --assumeno declines
  # it with a non-zero exit status.
  AUTOREMOVE_MODE=orphans run bash "$ROOT/bin/omarchy-update-orphan-pkgs"
  assert_status 0
  assert_contains "Orphaned packages found"

  printf '%s\n' "backend mocked tests passed"
