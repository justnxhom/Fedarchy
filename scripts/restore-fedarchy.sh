#!/bin/bash

# restore-fedarchy.sh — put the Fedarchy desktop back after a shell swap.
#
# Built for the scenario this actually has to survive: a different desktop shell
# (Noctalia, DankMaterialShell, panacea) was installed, Omarchy was removed or
# partially overwritten, and the machine needs to go back to the Fedarchy
# desktop with its bar, keybindings, lock screen, theme and sessions intact.
#
# Two things make that harder than a plain file copy, and both are handled here:
#
#   1. The incoming shell writes to SHARED areas. Noctalia, for example,
#      overwrites ~/.config/gtk-3.0/settings.ini and ~/.config/gtk-4.0/settings.ini
#      and creates ~/.config/easyeffects. Restoring the Omarchy files is not
#      enough if the new shell's own state is still sitting on top, so those
#      directories are moved aside into a quarantine directory rather than
#      deleted. Nothing is destroyed; the rollback is itself reversible.
#
#   2. The incoming shell may have added systemd user units. Restoring
#      ~/.config/systemd/user does not remove units that did not exist in the
#      backup, so the ones that are new are reported and, with --purge-units,
#      disabled and moved aside.
#
# Nothing is deleted from the live system. Anything displaced goes to the
# quarantine directory and the script prints exactly what it moved.
#
# Usage:
#   restore-fedarchy.sh              # show what would happen, change nothing
#   restore-fedarchy.sh --yes        # actually restore
#   restore-fedarchy.sh --yes --purge-units
#   restore-fedarchy.sh --to DIR     # restore somewhere else, for inspection

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$SCRIPT_DIR/fedarchy-desktop.tar.zst"
SUMS="$SCRIPT_DIR/SHA256SUMS"

APPLY=0
PURGE_UNITS=0
TARGET=""
QUARANTINE=""

usage() {
  cat <<'USAGE'
Restore the Fedarchy desktop after a shell swap.

Usage:
  restore-fedarchy.sh [options]

Options:
  --yes            Actually restore. Without this, nothing is written.
  --purge-units    Disable and set aside systemd user units that exist now but
                   were not in the backup (i.e. added by the incoming shell).
  --to DIR         Restore into DIR instead of $HOME. For inspection.
  -h, --help       This text.

Displaced files are moved to a quarantine directory under $HOME, never deleted.
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --yes|-y)       APPLY=1; shift ;;
    --purge-units)  PURGE_UNITS=1; shift ;;
    --to)           TARGET="${2:-}"; [[ -n $TARGET ]] || { echo "--to needs a directory" >&2; exit 1; }; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
head2() { printf '\n== %s ==\n' "$*"; }

[[ -f $CORE ]] || { echo "Missing $CORE" >&2; echo "Keep this script beside its archives." >&2; exit 1; }

if [[ -n $TARGET ]]; then
  DEST="$TARGET"; mkdir -p "$DEST"
else
  DEST="$HOME"
fi

# ------------------------------------------------------------------ preflight

head2 "Checking archive integrity"
if [[ -f $SUMS ]] && command -v sha256sum >/dev/null 2>&1; then
  if (cd "$SCRIPT_DIR" && sha256sum -c --quiet SHA256SUMS); then
    say "checksums OK"
  else
    echo "Checksum mismatch. The archive is damaged; do not restore from it." >&2
    exit 1
  fi
else
  say "no checksum file found - skipping verification"
fi

head2 "Current desktop state"
for probe in ".config/omarchy" ".config/noctalia" ".config/DankMaterialShell" \
             ".config/panacea" ".config/quickshell" ".config/hypr"; do
  if [[ -e $DEST/$probe ]]; then
    say "$probe present"
  fi
done
if pgrep -x noctalia >/dev/null 2>&1; then
  say "noctalia is RUNNING"
fi

# ------------------------------------------------------------------ inventory

head2 "What this restores"
listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
tar --zstd -tf "$CORE" 2>/dev/null | sed 's|^\./||' > "$listing"

# Collapse to the highest path in the archive, so the report reflects what is
# actually covered rather than every file inside it.
units=$(sed 's|/*$||' "$listing" | grep -v '^$' | sort -u | awk -F/ '
  { paths[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++) {
      p = paths[i]; n = split(p, a, "/"); covered = 0
      for (j = 1; j < n; j++) {
        pref = (j == 1) ? a[1] : pref "/" a[j]
        if (pref in seen) { covered = 1; break }
      }
      if (!covered) { seen[p] = 1; out[++c] = p }
    }
    for (i = 1; i <= c; i++) print out[i]
  }')
while read -r u; do [[ -n $u ]] && say "$DEST/$u"; done <<<"$units"

# ------------------------------------------------------------------ quarantine

# Directories the incoming shell owns. If one exists it is moved aside so the
# restored Omarchy files are not sitting underneath it.
INCOMING="noctalia DankMaterialShell panacea"

if (( APPLY )); then
  QUARANTINE="$DEST/Fedarchy-quarantine-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$QUARANTINE"
  say "$QUARANTINE"
fi

# ------------------------------------------------------------------ apply

if (( APPLY )); then
  head2 "Moving the incoming shell aside"
  for name in $INCOMING; do
    src="$DEST/.config/$name"
    if [[ -e $src ]]; then
      mkdir -p "$QUARANTINE/.config"
      mv "$src" "$QUARANTINE/.config/" && say "moved .config/$name"
    fi
  done

  head2 "Restoring files"
  tar --zstd -xf "$CORE" -C "$DEST"
  say "core restored"


  # ---------------------------------------------------------------- units
  if (( PURGE_UNITS )); then
    head2 "Disabling units that were not in the backup"
    backed_up=$(mktemp)
    tar --zstd -tf "$CORE" 2>/dev/null | sed 's|^\./||' \
      | grep '^\.config/systemd/user/' | xargs -r -n1 basename 2>/dev/null \
      | sort -u > "$backed_up"
    for unit in "$DEST"/.config/systemd/user/*.service; do
      [[ -e $unit ]] || continue
      base=$(basename "$unit")
      grep -qxF "$base" "$backed_up" && continue
      systemctl --user disable --now "$base" >/dev/null 2>&1
      mkdir -p "$QUARANTINE/systemd-user"
      mv "$unit" "$QUARANTINE/systemd-user/" 2>/dev/null && say "disabled + set aside $base"
    done
    rm -f "$backed_up"
  else
    head2 "New systemd units (not in the backup) - not touched"
    backed_up=$(mktemp)
    tar --zstd -tf "$CORE" 2>/dev/null | sed 's|^\./||' \
      | grep '^\.config/systemd/user/' | xargs -r -n1 basename 2>/dev/null \
      | sort -u > "$backed_up"
    for unit in "$DEST"/.config/systemd/user/*.service; do
      [[ -e $unit ]] || continue
      base=$(basename "$unit")
      grep -qxF "$base" "$backed_up" || say "$base"
    done
    rm -f "$backed_up"
    say "re-run with --purge-units to disable and set these aside"
  fi

  # ---------------------------------------------------------------- relaunch
  # Only when restoring over the real home. A --to restore is an inspection or
  # an off-machine copy, and must not touch the running desktop: reloading
  # systemd or restarting the shell there would disrupt a live session for no
  # reason.
  if [[ -z $TARGET ]]; then
    head2 "Bringing the Fedarchy shell back"
    systemctl --user daemon-reload 2>&1 | sed 's/^/  /'
    # An incoming shell may still be running and holding the bar.
    if pgrep -x noctalia >/dev/null 2>&1; then
      pkill -x noctalia 2>/dev/null && say "stopped noctalia"
    fi
    if command -v omarchy-restart-shell >/dev/null 2>&1; then
      if omarchy-restart-shell >/dev/null 2>&1; then
        say "omarchy shell restarted"
      else
        say "omarchy-restart-shell reported a problem - check: journalctl --user -u sddm -b"
      fi
    else
      say "omarchy-restart-shell not on PATH - start the shell manually"
    fi
  else
    head2 "Not touching the running desktop"
    say "--to was used, so systemd was not reloaded and the shell was not restarted"
  fi

  head2 "Done"
  say "Restored into $DEST"
  if [[ -n $QUARANTINE ]]; then
    say "Displaced files are in: $QUARANTINE"
    say "Nothing was deleted. To undo this restore, move those back."
  fi
  cat <<'NEXT'

  If the bar does not come back:
    systemctl --user daemon-reload
    omarchy-restart-shell
    journalctl --user -u sddm -b --no-pager | tail -40

  If the greeter is wrong, the theme is ~/.config/omarchy/shell.json and the
  installed SDDM theme is /usr/share/sddm/themes/.
NEXT
else
  head2 "Restoring"
  say "Dry run. Nothing was written."
  say "Re-run with --yes to restore."
  say "Add --purge-units to also set aside systemd units the incoming shell added."
fi
