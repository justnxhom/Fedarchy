import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Warns when an update left binaries rebuilt on disk while the old ones are
// still mapped into running processes. The classic Fedora papercut: dnf5
// succeeds, the files are new, and the running service has not picked them up.
//
// The input is RPM's own rebuild list at /var/run/rpm-rebuilddb.txt, which RPM
// writes after a transaction that rebuilt binaries and removes once they have
// been replaced. That makes this a pure file watch: no polling timer, no
// subprocess, and — importantly — no `dnf5 needs-restarting`, which refreshes
// repository metadata on every run and would hammer the configured mirrors.
//
// A system reboot is a different thing from a service restart and is reported
// separately: a rebuilt kernel or libc means the machine itself wants a
// reboot, which restarting services cannot fix.
BarWidget {
  id: root
  moduleName: "omarchy.needs-restart"

  // Set by omarchy-reboot-required when a reboot is genuinely recommended.
  // Defaults to false so a missing helper is simply "nothing to say".
  property bool rebootRequired: false

  readonly property var entries: root.parsedEntries(root.rebuildText)

  // The file holds one absolute path per line, e.g.
  //   /usr/sbin/sshd
  //   /usr/bin/firefox
  // Duplicate paths can appear when several mappings rebuilt at once.
  function parsedEntries(text) {
    var out = []
    var seen = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "" || seen[line] === true) continue
      seen[line] = true
      out.push(line)
    }
    return out
  }

  readonly property string rebuildText: rebuildFile.text === undefined ? "" : rebuildFile.text

  readonly property bool needsRestart: entries.length > 0
  readonly property bool shouldShow: needsRestart || rebootRequired

  readonly property string tooltip: {
    var lines = []
    if (rebootRequired) {
      lines.push("A reboot is recommended")
      lines.push("Updated system components are still running from memory.")
    }
    if (needsRestart) {
      if (rebootRequired) lines.push("")
      lines.push(entries.length === 1
        ? "1 program is running pre-update code:"
        : entries.length + " programs are running pre-update code:")
      // A long list would make an unusable tooltip; show enough to act on.
      var shown = Math.min(entries.length, 8)
      for (var i = 0; i < shown; i++) lines.push("  " + entries[i])
      if (entries.length > shown) lines.push("  …and " + (entries.length - shown) + " more")
      lines.push("")
      lines.push(rebootRequired
        ? "Click to reboot."
        : "Click to restart the affected services.")
    }
    return lines.join("\n")
  }

  // A reboot and a service restart are different remedies, so the click picks
  // between them rather than always offering the heavier one:
  //   * a reboot is genuinely required  -> reboot
  //   * only stale services             -> restart those services
  //   * ordinary applications           -> explain, change nothing
  // Restarting services is shown in a floating terminal because the work is
  // root, asks for confirmation, and reports per-unit results; running it blind
  // from a bar click would leave the user with no idea what happened.
  function activate() {
    if (!root.bar) return
    if (root.rebootRequired) {
      root.bar.run("omarchy-system-reboot")
      return
    }
    root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-restart-stale")
  }

  // Nothing pending: the slot collapses entirely rather than leaving a gap.
  visible: shouldShow
  implicitWidth: shouldShow ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  // Reboot recommendation comes from the shipped helper, which is a cheap local
  // check rather than a network call.
  Process {
    id: rebootProc
    command: ["omarchy-reboot-required"]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(text || "").trim().toLowerCase()
        root.rebootRequired = (t === "yes" || t === "1" || t === "true" || t === "reboot")
      }
    }
  }

  Timer {
    // Generous: a reboot recommendation only changes when something is
    // installed, and the file watch below catches the rest immediately.
    interval: 1800000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!rebootProc.running) rebootProc.running = true
    }
  }

  // RPM's rebuild list. Watching the file means a new transaction shows up as
  // soon as RPM writes it, with no timer of our own.
  FileView {
    id: rebuildFile
    path: "/var/run/rpm-rebuilddb.txt"
    watchChanges: true
    // The file is absent on a healthy boot and appears only after a rebuild;
    // a missing file is the normal case, not an error.
    printErrors: false
    onFileChanged: reload()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf021"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    foreground: root.rebootRequired && root.bar ? root.bar.urgent : (root.bar ? root.bar.foreground : Color.foreground)
    tooltipText: root.shouldShow ? root.tooltip : ""
    onPressed: root.activate()
  }
}