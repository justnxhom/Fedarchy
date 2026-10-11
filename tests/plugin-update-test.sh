#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }

manifest() {
  jq -n '{schemaVersion:1,id:"acme.sample",name:"Sample",version:"1.0.0",kinds:["panel"],entryPoints:{panel:"Panel.qml"}}'
}

repo="$TMPDIR/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.name Test
git -C "$repo" config user.email test@example.com
manifest >"$repo/manifest.json"
printf 'import QtQuick\nItem {}\n' >"$repo/Panel.qml"
git -C "$repo" add .
git -C "$repo" commit -qm initial
remote="$TMPDIR/remote.git"
git clone -q --bare "$repo" "$remote"
git -C "$repo" remote add origin "$remote"
git -C "$repo" push -q -u origin HEAD

home="$TMPDIR/home"
plugin="$home/.config/omarchy/plugins/acme.sample"
git clone -q "$remote" "$plugin"
mkdir -p "$TMPDIR/bin"
cat >"$TMPDIR/bin/omarchy-shell" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$TMPDIR/bin/omarchy-shell"

run_update() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$TMPDIR/bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-plugin-update" acme.sample --yes
}

printf 'local change\n' >>"$plugin/Panel.qml"
if run_update >/dev/null 2>&1; then
  fail "update rejects a dirty worktree"
fi
[[ $(git -C "$plugin" rev-parse HEAD) == $(git -C "$repo" rev-parse HEAD) ]] \
  || fail "dirty update changed HEAD"
pass "update rejects a dirty worktree before fetching"

git -C "$plugin" restore -- Panel.qml
invalid="$TMPDIR/invalid"
git clone -q "$remote" "$invalid"
git -C "$invalid" config user.name Test
git -C "$invalid" config user.email test@example.com
manifest | jq '.version = ""' >"$invalid/manifest.json"
git -C "$invalid" add manifest.json
git -C "$invalid" commit -qm invalid
git -C "$invalid" push -q origin HEAD
before=$(git -C "$plugin" rev-parse HEAD)
if run_update >/dev/null 2>&1; then
  fail "update rejects a manifest that fails validation"
fi
[[ $(git -C "$plugin" rev-parse HEAD) == "$before" ]] \
  || fail "validation failure did not restore the previous version"
OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$plugin" >/dev/null \
  || fail "validation rollback left an invalid plugin"
pass "update restores the previous valid version after validation failure"
