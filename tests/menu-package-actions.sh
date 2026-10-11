#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MOCK="$TMP/bin"
mkdir -p "$MOCK"
LOG="$TMP/dnf5.log"
INSTALLED="$TMP/installed"

cat > "$MOCK/rpm" <<'RPM'
#!/bin/bash
set -e
if [[ ${1:-} == "-q" && ${2:-} == "--provides" ]]; then
  exit 1
fi
if [[ ${1:-} == "-qa" ]]; then
  if [[ -f "$RPM_INSTALLED" ]]; then
    while IFS= read -r package; do printf '%s\n' "$package"; done < "$RPM_INSTALLED"
  fi
  exit 0
fi
if [[ ${1:-} == "-q" ]]; then
  grep -Fxq -- "$2" "$RPM_INSTALLED" 2>/dev/null
  exit $?
fi
exit 1
RPM

cat > "$MOCK/sudo" <<'SUDO'
#!/bin/bash
exec "$@"
SUDO

cat > "$MOCK/dnf5" <<'DNF5'
#!/bin/bash
printf '%s\n' "$*" >> "$DNF5_LOG"
if [[ ${1:-} == "install" ]]; then
  shift
  while [[ ${1:-} == -* ]]; do shift; done
  touch "$RPM_INSTALLED"
  for package in "$@"; do
    grep -Fxq -- "$package" "$RPM_INSTALLED" || printf '%s\n' "$package" >> "$RPM_INSTALLED"
  done
elif [[ ${1:-} == "remove" ]]; then
  shift
  while [[ ${1:-} == -* ]]; do shift; done
  for package in "$@"; do
    grep -Fvx -- "$package" "$RPM_INSTALLED" > "$RPM_INSTALLED.tmp" 2>/dev/null || :
    mv "$RPM_INSTALLED.tmp" "$RPM_INSTALLED"
  done
fi
DNF5

cat > "$MOCK/omarchy-update-lock" <<'LOCK'
#!/bin/bash
case ${1:-} in
  held) exit 0 ;;
  run-wait|run) shift; exec "$@" ;;
  *) exit 2 ;;
esac
LOCK

cat > "$MOCK/omarchy-hook" <<'HOOK'
#!/bin/bash
printf '%s\n' "$*" >> "$HOOK_LOG"
HOOK

cat > "$MOCK/omarchy-update-dnf" <<'UPDATE_DNF'
#!/bin/bash
printf '%s\n' "$*" >> "$UPDATE_DNF_LOG"
UPDATE_DNF

chmod +x "$MOCK"/*
export RPM_INSTALLED="$INSTALLED"
export DNF5_LOG="$LOG"
export HOOK_LOG="$TMP/hook.log"
export UPDATE_DNF_LOG="$TMP/update-dnf.log"
export PATH="$MOCK:$ROOT/bin:$PATH"
: > "$INSTALLED"

bash "$ROOT/bin/omarchy-pkg-add" fedora-demo
[[ "$(cat "$LOG")" == "install -y fedora-demo" ]]
: > "$LOG"
bash "$ROOT/bin/omarchy-pkg-add" fedora-demo
[[ ! -s "$LOG" ]]
bash "$ROOT/bin/omarchy-pkg-drop" fedora-demo
[[ "$(cat "$LOG")" == "remove -y fedora-demo" ]]
[[ ! -s "$INSTALLED" ]]

bash "$ROOT/bin/omarchy-update-system-pkgs"
[[ "$(cat "$HOOK_LOG")" == "pre-refresh-dnf" ]]
[[ "$(cat "$UPDATE_DNF_LOG")" == "upgrade --refresh --allowerasing -y" ]]

node - "$ROOT" > "$TMP/action-env" <<'NODE'
const root = process.argv[2]
const model = require(root + "/shell/plugins/menu/MenuModel.js")
process.stdout.write(model.actionEnvironment("/tmp/fedarchy-runtime"))
NODE
cat > "$MOCK/env-marker" <<'MARKER'
#!/bin/bash
printf '%s\n' "$OMARCHY_PATH|$PATH"
MARKER
chmod +x "$MOCK/env-marker"
actual=$(bash -lc "$(cat "$TMP/action-env")env-marker")
[[ "$actual" == "/tmp/fedarchy-runtime|/tmp/fedarchy-runtime/bin:"* ]]

cat > "$MOCK/omarchy-restart-gum" <<'GUM'
#!/bin/bash
:
GUM
cat > "$MOCK/omarchy-show-logo" <<'LOGO'
#!/bin/bash
:
LOGO
cat > "$MOCK/omarchy-show-done" <<'DONE'
#!/bin/bash
exit 0
DONE
cat > "$MOCK/kitty" <<'KITTY'
#!/bin/bash
printf '%s\n' "$*" > "$KITTY_LOG"
exit 0
KITTY
chmod +x "$MOCK"/omarchy-restart-gum "$MOCK"/omarchy-show-logo "$MOCK"/omarchy-show-done "$MOCK"/kitty
export KITTY_LOG="$TMP/kitty.log"
PATH="$MOCK:/usr/bin:/bin" bash "$ROOT/bin/omarchy-launch-kitty-with-presentation" "printf action-ok > '$TMP/action-proof'"
[[ -s "$KITTY_LOG" ]]
grep -Fq -- "--app-id=org.omarchy.terminal" "$KITTY_LOG"
: > "$KITTY_LOG"
PATH="$MOCK:/usr/bin:/bin" bash "$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "printf action-ok > '$TMP/floating-action-proof'"
[[ -s "$KITTY_LOG" ]]
grep -Fq -- "--app-id=org.omarchy.terminal" "$KITTY_LOG"

node - "$ROOT" <<'NODE'
const fs = require("fs")
const root = process.argv[2]
const model = require(root + "/shell/plugins/menu/MenuModel.js")
const raw = fs.readFileSync(root + "/default/omarchy/omarchy-menu.jsonc", "utf8")
const items = model.parseMenuJsonc(raw)
if (!items.length) throw new Error("default menu did not parse")
const inline = model.parseMenuJsonc('{"root":{"label":"Root"}, // comment\n "child":{"label":"Child"},}')
if (inline.length !== 2 || !inline.some(item => item.id === "child")) throw new Error("inline JSONC comments are not supported")
const serialized = JSON.stringify(items)
for (const name of ["omarchy-emacs", "xpadneo-dkms", "omarchy-pkg-present vim\"", "omarchy-pkg-add zed omazed", "php-sqlite xdebug", "python-protobuf umu-launcher"]) {
  if (serialized.includes(name)) throw new Error("stale Fedora menu entry: " + name)
}
for (const id of ["install", "remove", "update"]) {
  if (!items.some(item => item.id === id)) throw new Error("missing menu section: " + id)
}
if (!items.some(item => item.id === "setup" && item.parent === "root") ||
    !items.some(item => item.id === "setup.sources" && item.parent === "setup")) {
  throw new Error("Fedarchy Sources must be nested under Setup")
}
if (items.some(item => item.id === "sources")) throw new Error("Fedarchy Sources must not remain in the root menu")
const menuQml = fs.readFileSync(root + "/shell/plugins/menu/Menu.qml", "utf8")
if (!menuQml.includes('section === "install" || section === "remove" || section === "update"') ||
    !menuQml.includes('"omarchy-launch-kitty-with-presentation"')) {
  throw new Error("Install, Remove, and Update actions are not structurally routed through Kitty")
}
for (const file of ["bin/omarchy-install-dev-env", "bin/omarchy-remove-dev-env", "bin/omarchy-install-gaming-lutris", "bin/omarchy-remove-gaming-lutris", "bin/omarchy-install-gaming-xbox-controllers", "bin/omarchy-remove-gaming-xbox-controllers", "bin/omarchy-install-editor-zed"]) {
  const source = fs.readFileSync(root + "/" + file, "utf8")
  for (const name of ["xpadneo-dkms", "omazed", "python-protobuf"]) {
    if (source.includes(name)) throw new Error("stale Fedora package in " + file + ": " + name)
  }
}
NODE

printf '%s\n' "mocked menu package tests passed"
