import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// A dot per workspace, with the focused one carrying a wider pill.
//
// The slots are a fixed size on purpose. When the focused slot used to grow, the
// row re-flowed underneath the animation and the dots beside it drifted twice —
// once for the collapsing slot, once for the expanding one — which read as a
// wobble. Nothing here changes size now: the slots never move, and a single
// shared pill glides between them, so the only thing on screen in motion is the
// pill itself.
BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  readonly property int glideDuration: 250
  readonly property int tintDuration: 200
  readonly property int motionType: Easing.OutCubic
  readonly property real dotSize: Style.spaceReal(10)
  readonly property real dotPitch: Style.spaceReal(22)
  // The pill is exactly one pitch wide, so it fills its own slot and never
  // reaches a neighbouring dot — pillOverhand stays 0 and only matters if the
  // pill is ever made wider than the pitch.
  readonly property real pillWidth: Style.spaceReal(22)
  readonly property real pillHeight: Style.spaceReal(12)
  readonly property real pillOverhang: Math.max(0, (root.pillWidth - root.dotPitch) / 2)
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // Fixed geometry: a dot pitch each, so the row cannot reflow.
  readonly property real slotWidth: root.vertical ? root.barSize : root.dotPitch
  readonly property real slotHeight: root.vertical ? root.dotPitch : root.barSize

  property bool ready: false
  readonly property int focusedIndex: {
    var focused = Hyprland.focusedWorkspace
    if (focused === null) return -1
    return root.workspaceIds().indexOf(focused.id)
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  Component.onCompleted: ready = true

  implicitWidth: grid.implicitWidth + (root.vertical ? 0 : root.pillOverhang * 2) + trailingGap
  implicitHeight: grid.implicitHeight + (root.vertical ? root.pillOverhang * 2 : 0)

  // Under the slots, so a slot's hit area stays on top and the row never has to
  // repaint around the pill.
  Rectangle {
    id: pill
    visible: root.ready && root.focusedIndex >= 0 && root.focusedIndex < root.workspaceIds().length
    width: root.vertical ? root.pillHeight : root.pillWidth
    height: root.vertical ? root.pillWidth : root.pillHeight
    radius: Math.min(width, height) / 2
    color: Color.accent

    x: root.focusedIndex * root.slotWidth + (root.vertical ? (root.barSize - width) / 2 : root.pillOverhang)
    y: root.vertical
      ? root.focusedIndex * root.slotHeight + root.pillOverhang
      : (root.barSize - height) / 2

    Behavior on x {
      NumberAnimation { duration: root.glideDuration; easing.type: root.motionType }
    }

    Behavior on y {
      NumberAnimation { duration: root.glideDuration; easing.type: root.motionType }
    }
  }

  Grid {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    spacing: 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: slot
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.slotWidth
        fixedHeight: root.slotHeight
        tooltipText: "Workspace " + modelData
        onPressed: function(which) {
          if (which === Qt.LeftButton) root.focusWorkspace(modelData)
        }

        // A plain circle, stepping aside for the pill when this slot is focused.
        Rectangle {
          anchors.centerIn: parent
          width: root.dotSize
          height: root.dotSize
          radius: width / 2
          color: root.bar ? root.bar.barForeground : Color.foreground
          opacity: slot.focused ? 0 : (slot.occupied ? 0.72 : 0.34)

          Behavior on opacity {
            NumberAnimation { duration: root.tintDuration; easing.type: root.motionType }
          }
        }
      }
    }
  }
}
