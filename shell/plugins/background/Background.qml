import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property string currentBackground: ""
  property string displayedBackground: ""
  property int displayedReloads: 0
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  // True while a same-wallpaper re-read is covered by the outgoing frame.
  property bool refetching: false
  property int backgroundVersion: 0
  // Bumped only when the base layer must re-read the file it is showing.
  // backgroundVersion changes on every transition, and it used to drive the
  // base image's cache-busting query, so a plain wallpaper switch re-decoded a
  // full-screen image that was already on screen and already covered by the
  // outgoing frame. Keeping the two apart makes a switch decode only the
  // wallpaper that is actually arriving.
  property int baseContentVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1
  property int revealDuration: 320

  // How the incoming wallpaper takes over the outgoing one.
  //
  // Every one of these is a clip, a transform or an opacity, so the scene graph
  // does the work on the GPU and nothing here decodes or copies the wallpaper
  // an extra time. "random" picks one per switch, the way awww's
  // --transition-type random does. "slide" is the default because it is what
  // this has always done; change it with `omarchy-shell background transition
  // <type>` and it is remembered for the next session.
  property string transitionType: "slide"
  readonly property var transitionTypes: ["fade", "slide", "wipe", "random"]
  // What "random" chooses from: the same list without random itself.
  readonly property var concreteTransitions: ["fade", "slide", "wipe"]
  // Resolved per switch, so "random" can differ each time.
  property string activeTransition: "slide"
  readonly property bool transitionUsesFade: activeTransition === "fade"
  readonly property bool transitionUsesWipe: activeTransition === "wipe"
  readonly property bool transitionSlides: activeTransition === "slide"
  // Unit slide vector for the outgoing direction, one of left/right/top/bottom.
  property real slideX: 1
  property real slideY: 0
  readonly property string transitionStatePath: stateHome + "/omarchy/current/background-transition"

  // Injected by the first-party service loader; used to reach the lock and idle
  // services so playback can stop whenever nothing can see the wallpaper.
  property var shell: null

  // Stop a video wallpaper's decoding whenever it is covered. Qt's FFmpeg
  // engine drives its own clock, so an unseen player keeps decoding until it
  // is told not to — a locked laptop would otherwise decode until it died.
  readonly property var lockService: shell && shell.services ? shell.firstPartyServiceFor("omarchy.lock") : null
  readonly property var idleService: shell && shell.services ? shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property var batteryService: shell && shell.services ? shell.firstPartyServiceFor("omarchy.battery") : null
  readonly property bool lockActive: lockService ? lockService.locked : false
  readonly property bool screensaverActive: idleService ? idleService.screensaverWindowCount > 0 : false
  readonly property bool powerSaverActive: batteryService ? batteryService.powerSaverOnBattery : false
  // A lock or a screensaver covers every output, so it is decided once here.
  // Fullscreen is decided per output below, because it only covers its own.
  readonly property bool sessionObscured: lockActive || screensaverActive

  function isVideo(path) {
    return Util.isVideoPath(path)
  }

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, true)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    const refetchInPlace = finalPath === displayedBackground && path === finalPath
    currentBackground = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false
    refetching = false

    // Video frames are not fed through the image-only reveal stack. Switching
    // instantly also avoids decoding two full videos during a transition.
    if (instant || refetchInPlace || !displayedBackground || isVideo(path) || isVideo(displayedBackground)) {
      // Re-setting the wallpaper that is already on screen re-reads the file
      // under the base layer, which leaves the layer holding nothing until the
      // reloaded image is ready: the desktop flashes black for a few frames.
      // The outgoing frame is already decoded and costs nothing to leave up, so
      // it covers the reload and is dropped once the base reports ready.
      if (refetchInPlace && displayedBackground === finalPath && !isVideo(finalPath)) {
        baseContentVersion += 1
        oldBackground = displayedBackground
        incomingBackground = ""
        refetching = true
        revealProgress = 1
        return
      }
      incomingBackground = ""
      if (displayedBackground === finalPath) displayedReloads += 1
      displayedBackground = finalPath
      // Deliberately not cleared: this frame is the cover for the next reload,
      // and an Image whose source is emptied gives its texture back, so the
      // next switch would spend its first frames with nothing to show.
      oldBackground = finalPath
      revealProgress = 1
      return
    }

    // Prefer the frame that is already on screen: it is decoded and in place,
    // so it covers the frames while the incoming image loads. fromPath can be
    // an older wallpaper that would have to be decoded first.
    oldBackground = displayedBackground || fromPath
    incomingBackground = path
    revealProgress = 0
    resolveTransition()
  }

  // Pick what this switch uses. A slide takes one of the four edge directions
  // at random, the way awww's left/right/top/bottom feel when set to random.
  function resolveTransition() {
    var wanted = String(transitionType || "slide").toLowerCase()
    activeTransition = wanted === "random"
      ? concreteTransitions[Math.floor(Math.random() * concreteTransitions.length)]
      : wanted
    if (concreteTransitions.indexOf(activeTransition) === -1) activeTransition = "slide"
    if (activeTransition !== "slide") return
    var directions = [[1, 0], [-1, 0], [0, 1], [0, -1]]
    var pick = directions[Math.floor(Math.random() * directions.length)]
    slideX = pick[0]
    slideY = pick[1]
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    // Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.revealReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "omarchy-theme-switcher >/dev/null 2>&1"]
    onExited: root.refreshBackground()
  }

  Process {
    id: saveProcess
    running: false
  }

  // The chosen transition, read once at startup so it survives a restart.
  FileView {
    id: savedTransition
    path: root.transitionStatePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var wanted = String(text || "").trim().toLowerCase()
      if (root.transitionTypes.indexOf(wanted) !== -1) root.transitionType = wanted
    }
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): string {
      root.refreshBackground()
      return "ok"
    }

    function set(path: string): string {
      root.setBackground(path, false)
      return "ok"
    }

    function setInstant(path: string): string {
      root.setBackground(path, true)
      return "ok"
    }

    function transition(fromPath: string, path: string): string {
      root.transitionBackground(fromPath, path, path, false, false)
      return "ok"
    }

    // Choose how wallpapers hand over to each other: fade, slide, wipe, random.
    // Remembered in the state directory so it survives a restart, and applied
    // from the next switch onwards. Named setTransition because this handler
    // already has a `transition` used by the theme flow to move between two
    // wallpapers.
    function setTransition(type: string): string {
      var wanted = String(type || "").toLowerCase()
      if (root.transitionTypes.indexOf(wanted) === -1) return "invalid"
      root.transitionType = wanted
      saveProcess.command = ["sh", "-c", 'printf "%s\\n" "$1" >"$2"', "sh", wanted, root.transitionStatePath]
      saveProcess.running = false
      saveProcess.running = true
      return wanted
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): string {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
      return "ok"
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: root.revealDuration
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: {
    savedTransition.reload()
    refreshBackground()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. A still
      // wallpaper costs nothing to keep enabled, and a video one is throttled
      // by pausing playback rather than by parking the layer.
      updatesEnabled: true

      // Pausing every wallpaper for one fullscreen window would freeze the one
      // still on show next to it, which costs a viewer more than it saves. The
      // workspace on show here knows whether a fullscreen window covers it,
      // wherever focus happens to be.
      readonly property var hyprlandMonitor: Hyprland.monitorFor(modelData)
      readonly property var visibleWorkspace: hyprlandMonitor ? hyprlandMonitor.activeWorkspace : null
      readonly property bool fullscreenHere: visibleWorkspace ? visibleWorkspace.hasFullscreen : false

      // A sound track plays from one output only, or every monitor would
      // layer its own copy of it.
      readonly property bool firstScreen: Quickshell.screens.length > 0
        && String(Quickshell.screens[0].name || "") === String(modelData.name || "")

      property bool revealReady: false

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || revealReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || revealReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      BackgroundMedia {
        id: base
        anchors.fill: parent
         path: root.displayedBackground
         version: root.baseContentVersion
         reloads: root.displayedReloads

        playbackEnabled: !root.sessionObscured && !root.powerSaverActive && !panel.fullscreenHere
        audioEnabled: panel.firstScreen
        onReadyChanged: {
          if (ready && root.refetching) {
            root.refetching = false
            // Same invariant as the transition handoff: the frame stays on the
            // wallpaper now displayed, so it is still decoded and covering the
            // next switch.
            root.oldBackground = root.displayedBackground
            return
          }
          if (ready && root.finishingTransition) {
            root.incomingBackground = ""
            // Keep oldBackground on the wallpaper now displayed so the frame
            // stays decoded and can cover the next reload.
            root.oldBackground = root.displayedBackground
            root.finishingTransition = false
          }
        }
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(root.oldBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.oldBackground !== "" && (root.revealProgress < 1 || root.refetching)
        onStatusChanged: panel.maybeStartReveal()
      }

      // The incoming wallpaper. A wipe narrows this layer to a sweeping band
      // while the image inside keeps the full output size and overflows, so the
      // clip is what reveals it. Either way the outgoing frame stays put
      // underneath and nothing ever has to be decoded twice to cover a gap.
      Item {
        id: incomingLayer
        x: 0
        y: 0
        width: root.transitionUsesWipe ? panel.width * root.revealProgress : panel.width
        height: panel.height
        clip: root.transitionUsesWipe
        visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready

        Image {
          id: incomingFrame
          x: 0
          y: 0
          width: panel.width
          height: panel.height
          source: root.imageUrl(root.incomingBackground)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          // Only a crossfade animates the image's own alpha; the other
          // transitions move or clip the layer around it.
          opacity: root.transitionUsesFade ? root.revealProgress : 1
          // A Translate rather than x/y, because the image is sized explicitly
          // here and the transform keeps the two concerns apart.
          transform: Translate {
            x: root.transitionSlides ? (1 - root.revealProgress) * panel.width * root.slideX : 0
            y: root.transitionSlides ? (1 - root.revealProgress) * panel.height * root.slideY : 0
          }
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.revealReady = false
          panel.maybeStartReveal()
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
