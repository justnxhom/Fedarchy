#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MOCK="$TMP/bin"
mkdir -p "$MOCK" "$TMP/home/.config/alacritty" "$TMP/home/.config/kitty" "$TMP/home/.config/ghostty" "$TMP/run"
printf '%s\n' 'font = "old"' >"$TMP/home/.config/alacritty/alacritty.toml"
printf '%s\n' 'font_family old' >"$TMP/home/.config/kitty/kitty.conf"
printf '%s\n' 'font-family = "old"' >"$TMP/home/.config/ghostty/config"
export HOME="$TMP/home"
export XDG_RUNTIME_DIR="$TMP/run"
export CALL_LOG="$TMP/calls.log"
export PATH="$MOCK:$ROOT/bin:$PATH"
printf '#!/bin/bash\nprintf "%%s\\n" '\''Odd \\ Font'\''\n' >"$MOCK/fc-list"
printf '#!/bin/bash\nprintf "fc-cache\\n" >>"$CALL_LOG"\n' >"$MOCK/fc-cache"
printf '#!/bin/bash\nprintf "%%s\\n" '\''Odd \\ Font'\''\n' >"$MOCK/fc-match"
printf '#!/bin/bash\nexit 1\n' >"$MOCK/pgrep"
printf '#!/bin/bash\nprintf "hook %%s\\n" "$*" >>"$CALL_LOG"\n' >"$MOCK/omarchy-hook"
printf '#!/bin/bash\nexit 0\n' >"$MOCK/omarchy-notification-send"
chmod +x "$MOCK"/*

bash "$ROOT/bin/omarchy-font-set" 'Odd \ Font'
grep -Fq 'family = "Odd \\ Font"' "$HOME/.config/alacritty/alacritty.toml"
grep -Fq 'font_family "Odd \\ Font"' "$HOME/.config/kitty/kitty.conf"
grep -Fq 'font-family = "Odd \\ Font"' "$HOME/.config/ghostty/config"
grep -Fq '<string>Odd \ Font</string>' "$HOME/.config/fontconfig/fonts.conf"
if bash "$ROOT/bin/omarchy-font-set" 'odd \ font' >/dev/null 2>&1; then
  exit 1
fi
printf '%s\n' "mocked font tests passed"
