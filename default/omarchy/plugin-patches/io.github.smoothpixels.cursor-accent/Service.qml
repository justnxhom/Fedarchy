import QtQuick
import Quickshell
import Quickshell.Io

// No UI: the actual work happens in recolor.py, which rebuilds the cursor theme
// from the active Omarchy theme's colors.toml and applies it with
// `hyprctl setcursor`. This service watches the theme marker and re-runs that
// script whenever the theme changes, so switching themes recolors the cursor
// straight away instead of leaving the previous theme's colors in place.
//
// It also re-applies once when the shell (re)loads the plugin, so a fresh
// `omarchy plugin add --enable` or `omarchy-restart-shell` shows the right
// cursor immediately. The plugin's own tools/install-cursor-hook.sh installs
// theme-set/post-boot hooks for the same job; watching the marker is used
// instead because it also covers a theme changed by any other route, and it
// cannot drift out of sync with the shell.
Item {
  id: root

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string themeMarker: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"

  // Guards against redoing the same work: the marker is also read on load, and
  // a theme switch writes several state files in a row.
  property string lastSeenTheme: ""
  property bool checkedOnce: false

  function applyTheme(name) {
    // recolor.py reads the colors from the staged theme and only logs the name,
    // so an unknown name is harmless and still applies the current colors.
    applyProcess.command = ["python3", root.pluginDir + "/recolor.py", String(name || "").trim() || "unknown"]
    applyProcess.running = false
    applyProcess.running = true
  }

  function checkTheme() {
    var theme = String(themeMarkerView.text() || "").trim()
    if (checkedOnce && theme === lastSeenTheme) return
    checkedOnce = true
    lastSeenTheme = theme
    applyTheme(theme)
  }

  Component.onCompleted: themeMarkerView.reload()

  FileView {
    id: themeMarkerView
    path: root.themeMarker
    // Best effort only: `omarchy theme set` replaces this file, and a watch
    // held on the old inode never sees the replacement, so the poll below is
    // what actually makes the cursor follow the theme.
    watchChanges: true
    printErrors: false
    onLoaded: root.checkTheme()
    onLoadFailed: root.checkTheme()
  }

  Timer {
    interval: 1500
    repeat: true
    running: true
    onTriggered: themeMarkerView.reload()
  }

  Process {
    id: applyProcess
    running: false
    stdout: StdioCollector { onStreamFinished: if (text) console.log("cursor-accent:", text.trim()) }
    stderr: StdioCollector { onStreamFinished: if (text) console.warn("cursor-accent:", text.trim()) }
  }
}
