#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }

write_plugin() {
  local name="$1" id="$2" kinds="$3" entry_points="$4" bar_widget="${5:-null}"
  local dir="$TMPDIR/$name"
  mkdir -p "$dir"
  jq -n --arg id "$id" --argjson kinds "$kinds" --argjson entryPoints "$entry_points" --argjson barWidget "$bar_widget" '{schemaVersion:1,id:$id,name:$id,version:"1.0.0",kinds:$kinds,entryPoints:$entryPoints} + (if $barWidget == null then {} else {barWidget:$barWidget} end)' >"$dir/manifest.json"
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    mkdir -p "$dir/$(dirname "$entry")"
    printf 'import QtQuick\nItem {}\n' >"$dir/$entry"
  done < <(jq -r '.[]' <<<"$entry_points")
  printf '%s\n' "$dir"
}

validate() { OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$1" >/dev/null 2>&1; }
validate_output() { OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$1" 2>&1; }

for pair in 'bar:bar' 'bar-widget:barWidget' 'menu:menu' 'overlay:overlay' 'panel:panel' 'service:service'; do
  kind=${pair%%:*}
  entry=${pair##*:}
  metadata=null
  [[ $kind == bar-widget ]] && metadata='{"displayName":"Widget","description":"Widget","category":"Test","allowMultiple":false}'
  dir=$(write_plugin "valid-$kind" "acme.$kind" "[\"$kind\"]" "{\"$entry\":\"Entry.qml\"}" "$metadata")
  validate "$dir" || fail "validate accepts $kind"
done
pass "validate accepts each supported kind with its required entry point"

dir=$(write_plugin missing-entry acme.missing '["panel"]' '{"service":"Entry.qml"}')
if validate "$dir"; then fail "validate rejects a missing required entry point"; fi
pass "validate rejects missing kind entry points"

dir=$(write_plugin unsafe acme.unsafe '["panel"]' '{"panel":"../Entry.qml"}')
if validate "$dir"; then fail "validate rejects an escaping entry point"; fi
pass "validate rejects escaping relative paths"

dir=$(write_plugin wrong-type acme.wrong '["panel"]' '{"panel":12}')
if validate "$dir"; then fail "validate rejects non-string entry points"; fi
pass "validate rejects invalid field types"

dir=$(write_plugin duplicate-kind acme.duplicate '["panel","panel"]' '{"panel":"Entry.qml"}')
if validate "$dir"; then fail "validate rejects duplicate kinds"; fi
pass "validate rejects duplicate kinds"

dir=$(write_plugin no-multiple acme.single '["bar-widget"]' '{"barWidget":"Entry.qml"}' '{"displayName":"Widget","description":"Widget","category":"Test"}')
if validate "$dir"; then fail "validate requires an explicit allowMultiple value"; fi
pass "validate requires explicit bar-widget allowMultiple"

dir=$(write_plugin reserved omarchy.reserved '["panel"]' '{"panel":"Entry.qml"}')
if validate "$dir"; then fail "validate rejects the reserved namespace"; fi
pass "validate rejects reserved plugin ids"

dir=$(write_plugin symlink acme.symlink '["panel"]' '{"panel":"Entry.qml"}')
ln -s Entry.qml "$dir/Linked.qml"
if validate "$dir"; then fail "validate rejects plugin symlinks"; fi
pass "validate rejects symlinks anywhere in a plugin"
