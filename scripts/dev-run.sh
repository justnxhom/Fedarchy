#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

export QSG_RENDER_LOOP=threaded
export QML_XHR_ALLOW_FILE_READ=1
export OMARCHY_PATH="${PROJECT_ROOT}"
export PATH="${PROJECT_ROOT}/bin:${PATH}"
export QT_LOGGING_RULES="kf.iconthemes=false;quickshell.desktopentry=false"

echo "Starting Fedarchy in development mode..."
echo "Project root: ${PROJECT_ROOT}"
echo "OMARCHY_PATH: ${OMARCHY_PATH}"

if command -v systemd-cat >/dev/null 2>&1; then
  exec systemd-cat -t fedarchy-dev-shell -- quickshell -p "${PROJECT_ROOT}/shell" "$@"
fi

exec quickshell -p "${PROJECT_ROOT}/shell" "$@"
