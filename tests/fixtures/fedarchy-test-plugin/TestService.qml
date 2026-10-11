import QtQuick
import Quickshell.Io

Item {
  property string status: "ready"

  function ping() {
    return "pong"
  }

  IpcHandler {
    target: "local.fedarchy-test"

    function ping() {
      return "pong"
    }
  }
}
