#!/bin/bash

# COPR repository search and add-menu flow (no network, no sudo, no dnf5).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MOCK="$TMP/mock"
mkdir -p "$MOCK"

# Fake COPR fulltext search page with duplicate hits and a non-project link.
cat > "$MOCK/curl" <<'CURL'
#!/bin/bash
printf '%s\n' "$*" > "$CURL_LOG"

case "$*" in
  *"--data-urlencode"*)
    cat "$CURL_PAGE"
    exit 0
    ;;
  *)
    echo "unexpected curl invocation: $*" >&2
    exit 1
    ;;
esac
CURL

cat > "$TMP/search-page.html" <<'PAGE'
<a href="/coprs/atim/starship/">starship</a>
<a href="/coprs/atim/lazygit/">lazygit</a>
<a href="/coprs/atim/starship/">starship again</a>
<a href="/coprs/packages/search/">packages</a>
<a href="/coprs/nett00n/hyprland/">hyprland</a>
PAGE
cat > "$TMP/empty-page.html" <<'PAGE'
<a href="/coprs/packages/search/">packages</a>
PAGE

export CURL_LOG="$TMP/curl.log"
export CURL_PAGE="$TMP/search-page.html"
export OMARCHY_COPR_HOST="https://copr.example.test"
chmod +x "$MOCK/curl"
export PATH="$MOCK:$ROOT/bin:$PATH"

echo "== search extracts owner/name hits =="
output=$(bash "$ROOT/bin/omarchy-copr-search" starship)
expected=$'atim/lazygit\natim/starship\nnett00n/hyprland'
[[ $output == "$expected" ]] || { echo "unexpected results:"; echo "$output"; exit 1; }
grep -q -- "--data-urlencode fulltext=starship" "$CURL_LOG" || {
  echo "search term was not sent as fulltext"
  exit 1
}

echo "== search honors --limit =="
output=$(bash "$ROOT/bin/omarchy-copr-search" starship --limit 2)
[[ $(printf '%s\n' "$output" | wc -l) -eq 2 ]] || { echo "limit ignored"; exit 1; }

echo "== search reports no matches =="
export CURL_PAGE="$TMP/empty-page.html"
output=$(bash "$ROOT/bin/omarchy-copr-search" nothinghere)
grep -q "No COPR projects matched" <<<"$output" || { echo "missing no-match notice"; exit 1; }

echo "== search rejects bad input =="
bash "$ROOT/bin/omarchy-copr-search" >/dev/null 2>&1 && { echo "empty query accepted"; exit 1; }
bash "$ROOT/bin/omarchy-copr-search" --limit 0 starship 2>/dev/null && { echo "zero limit accepted"; exit 1; }

# --- add-menu flow ---
cat > "$MOCK/gum" <<'GUM'
#!/bin/bash
case "$1" in
  input)
    printf '%s\n' "$GUM_INPUT" >> "$GUM_LOG"
    printf '%s\n' "$(sed -n "${GUM_INPUT_INDEX}p" "$GUM_INPUTS")"
    ;;
  choose)
    head -n 1
    ;;
esac
GUM

cat > "$MOCK/omarchy-copr-add" <<'ADD'
#!/bin/bash
printf '%s\n' "$*" > "$ADD_LOG"
ADD

chmod +x "$MOCK"/*
export GUM_LOG="$TMP/gum.log"
export GUM_INPUTS="$TMP/gum-inputs"
export ADD_LOG="$TMP/copr-add.log"
: > "$GUM_LOG"

echo "== add-menu searches and enables a picked project =="
printf '%s\n' "hyprland" "" > "$GUM_INPUTS"
export GUM_INPUT_INDEX=1
export CURL_PAGE="$TMP/search-page.html"
bash "$ROOT/bin/omarchy-copr-add-menu" >/dev/null
grep -qx "atim/lazygit" "$ADD_LOG" || { echo "search result was not enabled"; cat "$ADD_LOG"; exit 1; }

echo "== add-menu accepts a direct owner/name =="
printf '%s\n' "atim/starship" "" > "$GUM_INPUTS"
export GUM_INPUT_INDEX=1
bash "$ROOT/bin/omarchy-copr-add-menu" >/dev/null
grep -qx "atim/starship" "$ADD_LOG" || { echo "direct COPR id not passed through"; exit 1; }

echo "== add-menu falls back to manual entry =="
printf '%s\n' "zzznothing" "brycensranch/gpu-screen-recorder-git" > "$GUM_INPUTS"
export GUM_INPUT_INDEX=2
export CURL_PAGE="$TMP/empty-page.html"
bash "$ROOT/bin/omarchy-copr-add-menu" >/dev/null
grep -qx "brycensranch/gpu-screen-recorder-git" "$ADD_LOG" || { echo "manual entry not used"; exit 1; }

# --- disable/enable-menu flow -------------------------------------------------
#
# The picker hands the selection to dnf5 as owner/name, but the two listings do not
# agree on a shape: --enabled prints dnf5's fully qualified colon-separated id
# (copr:host:owner:name) while --disabled and the plain listing print
# host/owner/name with a trailing marker. Stripping the prefix and host from the
# first leaves "owner:name", which has no slash in it -- so a check for a slash
# rejects every repository and the menu can never disable or enable anything.
echo "== disable-menu converts the --enabled listing to owner/name =="
cat > "$MOCK/omarchy-copr-list" <<'LIST'
#!/bin/bash
case "${1:-}" in
  --enabled)  printf 'copr:copr.fedorainfracloud.org:atim:himalaya\n' ;;
  --disabled) printf 'copr.fedorainfracloud.org/avengemedia/danklinux (disabled)\n' ;;
  *)          printf 'copr.fedorainfracloud.org/avengemedia/danklinux (disabled)\n' ;;
esac
LIST

cat > "$MOCK/omarchy-copr-disable" <<'DIS'
#!/bin/bash
printf '%s\n' "$*" > "$DIS_LOG"
DIS

cat > "$MOCK/omarchy-copr-enable" <<'EN'
#!/bin/bash
printf '%s\n' "$*" > "$EN_LOG"
EN

chmod +x "$MOCK"/*
export DIS_LOG="$TMP/copr-disable.log"
export EN_LOG="$TMP/copr-enable.log"

# Output and exit status are captured rather than discarded. Under `set -e` an
# unexpected non-zero exit aborts the whole file with a bare status and no
# indication of which step failed, which is how a real fault here once looked like
# a passing suite.
: > "$DIS_LOG"
if ! out=$(bash "$ROOT/bin/omarchy-copr-disable-menu" 2>&1); then
  echo "disable-menu exited non-zero"; echo "$out"; exit 1
fi
grep -qx "atim/himalaya" "$DIS_LOG" \
  || { echo "disable-menu did not produce owner/name from the colon listing"; \
       echo "  got: $(cat "$DIS_LOG")"; echo "$out"; exit 1; }

: > "$EN_LOG"
if ! out=$(bash "$ROOT/bin/omarchy-copr-enable-menu" 2>&1); then
  echo "enable-menu exited non-zero"; echo "$out"; exit 1
fi
grep -qx "avengemedia/danklinux" "$EN_LOG" \
  || { echo "enable-menu did not produce owner/name from the slash listing"; \
       echo "  got: $(cat "$EN_LOG")"; echo "$out"; exit 1; }
echo "== enable-menu converts the --disabled listing to owner/name =="

echo "== a selection that is already owner/name is passed through =="
cat > "$MOCK/omarchy-copr-list" <<'LIST2'
#!/bin/bash
printf 'atim/himalaya\n'
LIST2
chmod +x "$MOCK/omarchy-copr-list"
: > "$DIS_LOG"
bash "$ROOT/bin/omarchy-copr-disable-menu" >/dev/null
grep -qx "atim/himalaya" "$DIS_LOG" \
  || { echo "bare owner/name was mangled"; echo "  got: $(cat "$DIS_LOG")"; exit 1; }

echo "== a malformed selection is refused rather than passed to dnf5 =="
cat > "$MOCK/omarchy-copr-list" <<'LIST3'
#!/bin/bash
printf 'copr:\n'
LIST3
chmod +x "$MOCK/omarchy-copr-list"
: > "$DIS_LOG"
# The script exits non-zero here on purpose, so the status is swallowed: under
# `set -e` a bare assignment aborts the test file and reports nothing.
output=$(bash "$ROOT/bin/omarchy-copr-disable-menu" 2>&1 || true)
[ ! -s "$DIS_LOG" ] || { echo "a malformed selection reached dnf5"; exit 1; }
grep -q "Unable to parse" <<<"$output" || { echo "malformed selection not reported"; exit 1; }

echo "== both menu items are registered =="
grep -q '"setup.sources.copr.disable"' "$ROOT/default/omarchy/omarchy-menu.jsonc" \
  || { echo "disable menu item missing"; exit 1; }
grep -q '"setup.sources.copr.enable"' "$ROOT/default/omarchy/omarchy-menu.jsonc" \
  || { echo "enable menu item missing"; exit 1; }
[ -x "$ROOT/bin/omarchy-copr-enable" ] || { echo "omarchy-copr-enable is not executable"; exit 1; }

echo "== add-menu cancels cleanly =="
: > "$ADD_LOG"
printf '%s\n' "" "" > "$GUM_INPUTS"
export GUM_INPUT_INDEX=1
output=$(bash "$ROOT/bin/omarchy-copr-add-menu")
grep -q "Cancelled" <<<"$output" || { echo "cancel not reported"; exit 1; }
[[ ! -s $ADD_LOG ]] || { echo "cancel enabled a repo"; exit 1; }

echo "== add-menu rejects a malformed manual entry =="
printf '%s\n' "not-a-copr" "alsobad" > "$GUM_INPUTS"
export GUM_INPUT_INDEX=2
export CURL_PAGE="$TMP/empty-page.html"
bash "$ROOT/bin/omarchy-copr-add-menu" 2>/dev/null && { echo "invalid manual entry accepted"; exit 1; }

echo "== add-menu help still works =="
bash "$ROOT/bin/omarchy-copr-add" 2>/dev/null && { echo "missing arg check broken"; exit 1; }

echo "all copr search tests passed"
