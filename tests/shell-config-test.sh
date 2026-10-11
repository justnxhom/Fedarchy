#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }

home="$TMPDIR/home"
mkdir -p "$home/.config/omarchy" "$TMPDIR/bin"
cat >"$TMPDIR/bin/omarchy-shell" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$TMPDIR/bin/omarchy-shell"
cat >"$home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "unrelated": {"keep": true},
  "bar": {"custom": "kept", "layout": {"left": [], "center": [], "right": []}},
  "plugins": []
}
JSON

HOME="$home" OMARCHY_PATH="$ROOT" PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-bar" position bottom >/dev/null
jq -e '.unrelated.keep == true and .bar.custom == "kept" and .bar.position == "bottom"' \
  "$home/.config/omarchy/shell.json" >/dev/null || fail "bar mutation dropped unrelated config"
[[ -f $home/.config/omarchy/shell.json.bak ]] || fail "config commit did not preserve a backup"
pass "bar config mutation preserves unrelated keys and keeps a backup"

for position in top left right bottom; do
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-bar" position "$position" >/dev/null &
done
wait
jq -e '.version == 1 and .unrelated.keep == true and (.bar.position | IN("top", "bottom", "left", "right"))' \
  "$home/.config/omarchy/shell.json" >/dev/null || fail "parallel config mutations produced invalid JSON"
pass "serialized shell config commits remain valid under concurrent writers"
