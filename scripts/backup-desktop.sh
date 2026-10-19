#!/bin/bash

# backup-desktop.sh — snapshot the Fedarchy desktop into a restorable archive.
#
# Built so the snapshot survives a desktop-shell swap. A shell replacement does
# not only add its own config directory; it also overwrites shared areas that
# belong to the desktop as a whole:
#
#   * ~/.config/hypr                  the compositor config: autostart, binds,
#                                     window rules, environment
#   * ~/.config/systemd/user         user units, including the shell's own
#   * ~/.config/omarchy              the shell being replaced
#   * ~/.config/gtk-3.0, gtk-4.0     theme settings, overwritten by Noctalia
#   * ~/.config/kdeglobals           colours, overwritten by Noctalia
#   * ~/.config/easyeffects          created by Noctalia
#   * ~/.config/hyprlock             the lock screen
#   * ~/.config/sddm                 user-installed login themes
#   * ~/.icons, ~/.local/share/icons, ~/.local/share/fonts
#
# The old archive covered only the first four. This covers the rest.
#
# Deliberately NOT included: application data that a shell swap does not touch
# and that is expensive - ~/.config/mozilla, VSCodium, net.imput.helium,
# flatpak, the browser and IDE caches. Those are the user's files, not the
# desktop's, and they are not what "roll back the shell" means.
#
# Usage: bash scripts/backup-desktop.sh [label]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${1:-}"
STAMP="$(date +%Y%m%d-%H%M%S)"
SUFFIX="${LABEL:+-$LABEL}"
ARCHIVE="$HOME/Fedarchy-archive-$STAMP$SUFFIX"

mkdir -p "$ARCHIVE"
chmod 700 "$ARCHIVE"

echo "Fedarchy desktop backup"
echo "  target: $ARCHIVE"
echo "  date:   $(date -Is)"
echo

# ---------------------------------------------------------------- path list

# Grouped by why it is included. A path that does not exist is skipped, so the
# same list works on any machine.
PATHS=(
  # -- the compositor and session: what a shell swap rewrites first ----------
  ".config/hypr"
  ".config/systemd/user"
  ".config/environment.d"

  # -- the shell itself -------------------------------------------------------
  ".config/omarchy"
  ".config/quickshell"
  ".local/state/omarchy"

  # -- lock screen and login -------------------------------------------------
  ".config/hyprlock"
  ".config/sddm"

  # -- appearance: areas a new shell OVERWRITES ------------------------------
  ".config/gtk-3.0/settings.ini"
  ".config/gtk-4.0/settings.ini"
  ".config/kdeglobals"
  ".config/kglobalshortcutsrc"
  ".config/easyeffects"
  ".config/fontconfig"
  ".config/theme-switcher"
  ".icons"
  ".local/share/icons"
  ".local/share/fonts"

  # -- shared app config -----------------------------------------------------
  ".config/kitty"
  ".config/foot"
  ".config/ghostty"
  ".config/rofi"
  ".config/alacritty"

  # -- the project itself ----------------------------------------------------
  "Fedarchy"
  "Fedarchy-release-candidate-20261011-153859"
)

echo "Collecting..."
present=()
missing=()
for p in "${PATHS[@]}"; do
  if [[ -e "$HOME/$p" ]]; then
    present+=("$p")
    printf '  %-46s %s\n' "$p" "$(du -sh --apparent-size "$HOME/$p" 2>/dev/null | cut -f1)"
  else
    missing+=("$p")
  fi
done

# The deployed commands. Listed explicitly so unrelated scripts in ~/.local/bin
# are never swept into the archive.
binlist="$ARCHIVE/.bin-files"
ls -1 "$HOME/.local/bin" 2>/dev/null \
  | grep -E '^(omarchy|fedarchy)(-|$)' \
  | sed 's|^|.local/bin/|' > "$binlist"
if [[ -s $binlist ]]; then
  present+=(".local/bin")
  printf '  %-46s %s\n' ".local/bin (omarchy/fedarchy only)" "$(wc -l < "$binlist") commands"
fi

echo
echo "  not present, skipped: ${#missing[@]}"
for m in "${missing[@]}"; do printf '    %s\n' "$m"; done

# ---------------------------------------------------------------- archive

echo
echo "Building archive..."
cd "$HOME"

tar_args=()
for p in "${present[@]}"; do
  if [[ $p == ".local/bin" ]]; then
    # explicit file list, not the whole directory
    while read -r f; do tar_args+=("$f"); done < "$binlist"
  else
    tar_args+=("$p")
  fi
done

tar --zstd -cf "$ARCHIVE/fedarchy-desktop.tar.zst" "${tar_args[@]}"
rm -f "$binlist"

# ---------------------------------------------------------------- inventory

echo
echo "Writing the system inventory..."
{
  echo "Fedarchy desktop inventory"
  echo "captured: $(date -Is)"
  echo "host:     $(uname -srm)"
  echo
  . /etc/os-release 2>/dev/null
  echo "os:       ${PRETTY_NAME:-unknown}"
  echo
  echo "== compositor =="
  hyprctl version 2>/dev/null | head -2 | sed 's/^/  /' || true
  echo
  echo "== bar layout (shell.json) =="
  python3 - <<'PY' 2>/dev/null
import json, os
p = os.path.expanduser("~/.config/omarchy/shell.json")
try:
    b = json.load(open(p))["bar"]
    print("  position     :", b.get("position"))
    print("  transparent  :", b.get("transparent"))
    print("  centerAnchor :", b.get("centerAnchor"))
    print("  centerOffset :", b.get("centerOffset"))
    for s in ("left", "center", "right"):
        print(f"  {s:6}      :", " ".join(x["id"] for x in b["layout"][s]))
except Exception as e:
    print("  (unavailable:", e, ")")
PY
  echo
  echo "== installed SDDM themes =="
  ls -1 /usr/share/sddm/themes 2>/dev/null | sed 's/^/  /' || true
  grep -n '^Current=' /etc/sddm.conf 2>/dev/null | tail -1 | sed 's/^/  active: /' || true
  echo
  echo "== GRUB =="
  grep -E '^GRUB_(THEME|TIMEOUT|DEFAULT|CMDLINE_LINUX|ENABLE_BLSCFG|DISABLE_RECOVERY)' /etc/default/grub 2>/dev/null | sed 's/^/  /' || true
  echo "  secure boot: $(mokutil --sb-state 2>&1)"
  echo
  echo "== systemd user units =="
  systemctl --user list-unit-files --no-pager 2>/dev/null | awk 'NR>1 && $1!="" {print "  "$1" "$2}' | head -40 || true
  echo
  echo "== enabled COPR repositories =="
  dnf5 copr list 2>/dev/null | grep -v '(disabled)' | sed 's/^/  /' || true
  echo
  echo "== enabled dnf5 repositories =="
  dnf5 --quiet repoinfo --enabled 2>/dev/null | awk '/^Repository id/ {print "  "$3}' | head -20 || true
  echo
  echo "== installed packages (name only) =="
  rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' 2>/dev/null | sort | sed 's/^/  /' || true
  echo
  echo "== hyprland bindings and rules (reference) =="
  grep -rhnE '^\s*(bind|bind[a-z]*|unbind|windowrule|env|exec-once)\b' \
    "$HOME/.config/hypr" 2>/dev/null | head -60 | sed 's/^/  /' || true
} > "$ARCHIVE/SYSTEM-INVENTORY.txt"

# ---------------------------------------------------------------- restore script

cp "$PROJECT_ROOT/scripts/restore-fedarchy.sh" "$ARCHIVE/restore-fedarchy.sh"
chmod +x "$ARCHIVE/restore-fedarchy.sh"

# ---------------------------------------------------------------- readme

cat > "$ARCHIVE/README.md" <<'ARCHIVE_README_EOF'
# Fedarchy desktop backup

Taken: __STAMP__

A snapshot of the parts of this machine that make up the *desktop*, as opposed
to your application data. It is built to survive a desktop-shell swap: swap in
Noctalia (or anything else), remove Omarchy, and this archive is what puts the
Fedarchy desktop back.

## Contents

| file | |
|---|---|
| fedarchy-desktop.tar.zst | the restorable snapshot |
| restore-fedarchy.sh | the restore script |
| SYSTEM-INVENTORY.txt | packages, COPRs, units, bar layout, hyprland binds |
| SHA256SUMS | integrity check |

## Restoring

    bash restore-fedarchy.sh              # dry run, changes nothing
    bash restore-fedarchy.sh --yes        # restore
    bash restore-fedarchy.sh --yes --purge-units

The restore is itself reversible. Anything it displaces goes into
~/Fedarchy-quarantine-<timestamp>/ rather than being deleted, and the script
prints exactly what it moved.

## What is deliberately not here

Application data that a shell swap does not touch: ~/.config/mozilla,
VSCodium, net.imput.helium, flatpak, browser and IDE caches. Those are your
files, not the desktop's. A shell swap does not damage them, and "roll back the
desktop" does not mean restoring them.
ARCHIVE_README_EOF

# ---------------------------------------------------------------- checksums

cd "$ARCHIVE"
sha256sum fedarchy-desktop.tar.zst 2>/dev/null > SHA256SUMS
sha256sum restore-fedarchy.sh >> SHA256SUMS

# ---------------------------------------------------------------- done

echo
echo "Done."
ls -lh "$ARCHIVE" | sed 's/^/  /'
echo
echo "  total: $(du -sh --apparent-size "$ARCHIVE" | cut -f1)"
echo
echo "To restore:"
echo "  bash $ARCHIVE/restore-fedarchy.sh          # dry run"
echo "  bash $ARCHIVE/restore-fedarchy.sh --yes    # restore"
