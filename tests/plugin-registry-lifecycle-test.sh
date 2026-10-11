#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v quickshell >/dev/null 2>&1 || { echo 'ok - quickshell unavailable; skipping plugin registry lifecycle test # SKIP'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo 'ok - jq unavailable; skipping plugin registry lifecycle test # SKIP'; exit 0; }

TMPDIR=$(mktemp -d)
pid=""
cleanup() {
  if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

cat >"$TMPDIR/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Commons
import "services"

Item {
  id: root
  property string resultPath: Quickshell.env("OMARCHY_TEST_RESULT")
  property var config: ({ version: 1, bar: { layout: { left: [], center: [], right: [] } }, plugins: [] })
  property var failures: []

  function fail(message) { failures.push(String(message)) }
  function check(value, message) { if (!value) fail(message) }
  function block(kind, source, value) {
    return "===" + kind + "::" + source + "===\n" + (typeof value == "string" ? value : JSON.stringify(value)) + "\n=== EOM ===\n"
  }
  function manifest(id, kinds, entryPoints, widget) {
    var value = { schemaVersion: 1, id: id, name: id, version: "1.0.0", kinds: kinds, entryPoints: entryPoints }
    if (widget) value.barWidget = widget
    return value
  }
  function writeResult() {
    var payload = JSON.stringify({ ok: failures.length === 0, failures: failures, ids: Object.keys(registry.installedPlugins).sort(), scanError: registry.lastScanError })
    var quote = function(value) { return "'" + String(value).replace(/'/g, "'\\''") + "'" }
    Quickshell.execDetached(["bash", "-c", "printf '%s' " + quote(payload) + " > " + quote(root.resultPath)])
  }
  PluginRegistry {
    id: registry
    firstPartyDir: ""
    pluginsDir: Quickshell.env("HOME") + "/.config/omarchy/plugins"
    shellConfigProvider: function() { return root.config }
    shellConfigMutator: function(mutator) { var next = JSON.parse(JSON.stringify(root.config)); mutator(next); root.config = next }
  }
  Timer {
    running: true
    interval: 100
    onTriggered: {
      var widgetMeta = { displayName: "Widget", description: "Widget", category: "Test", allowMultiple: false }
      var first = manifest("omarchy.auth", ["service"], { service: "Service.qml" })
      first.omarchy = { capabilities: ["authentication"] }
      var clone = manifest("acme.clone", ["service"], { service: "Service.qml" })
      clone.omarchy = { clonedFrom: "omarchy.auth" }
      var good = manifest("acme.good", ["panel"], { panel: "Panel.qml" })
      var widget = manifest("acme.widget", ["bar-widget"], { barWidget: "Widget.qml" }, widgetMeta)
      var bad = manifest("acme.bad", ["panel"], { panel: "../Panel.qml" })
      var scan = block("firstparty", "/first/auth", first) + block("thirdparty", "/third/clone", clone) + block("thirdparty", "/third/good", good) + block("thirdparty", "/third/widget", widget) + block("thirdparty", "/third/bad", bad) + block("thirdparty", "/third/duplicate", manifest("omarchy.auth", ["panel"], { panel: "Panel.qml" })) + block("thirdparty", "/third/broken", "{")
      check(registry.parseScanOutput(scan), "valid scan is accepted")
      check(registry.installedPlugins["acme.good"] !== undefined, "valid plugin survives broken neighbors")
      check(registry.installedPlugins["acme.widget"] !== undefined, "bar-widget entry point is accepted")
      check(registry.installedPlugins["acme.clone"].__hostCapabilities.length === 0, "clone cannot inherit capabilities")
      check(registry.installedPlugins["omarchy.auth"].__hostCapabilities.length === 1, "first-party capability is trusted")
      check(registry.parseScanOutput("", false) === false, "failed scan is rejected")
      check(registry.installedPlugins["acme.good"] !== undefined, "failed scan preserves registry")
      check(registry.lastScanError.length > 0, "failed scan records an error")
      root.writeResult()
      Qt.quit()
    }
  }
}
QML
mkdir -p "$TMPDIR/home"
ln -s "$ROOT/shell/services" "$TMPDIR/services"
ln -s "$ROOT/shell/Commons" "$TMPDIR/Commons"
result="$TMPDIR/result.json"
OMARCHY_TEST_RESULT="$result" HOME="$TMPDIR/home" QML2_IMPORT_PATH="$ROOT/shell" QML_IMPORT_PATH="$ROOT/shell" \
  quickshell -p "$TMPDIR" --no-color >"$TMPDIR/log" 2>&1 &
pid=$!
for _ in {1..50}; do
  [[ -s $result ]] && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.1
done
[[ -s $result ]] || { cat "$TMPDIR/log" >&2; echo 'not ok - plugin registry lifecycle test timed out' >&2; exit 1; }
jq -e '.ok == true' "$result" >/dev/null || { jq . "$result" >&2; cat "$TMPDIR/log" >&2; echo 'not ok - plugin registry lifecycle test' >&2; exit 1; }
echo 'ok - plugin registry scan and capability lifecycle checks pass'
