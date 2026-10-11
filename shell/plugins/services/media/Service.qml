import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "MediaModel.js" as MediaModel

Item {
  id: root

  property var shell: null
  property string preferredPlayerKey: ""
  property var playerStartedAt: ({})
  property var pendingTrackOsd: null
  property int trackOsdSerial: 0
  property int playSerial: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }
  readonly property var sourcePlayers: orderedSourcePlayers()
  readonly property var sourceCyclePlayers: orderedCycleSourcePlayers()
  readonly property var activePlayer: selectActivePlayer()
  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string identity: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "") : ""

  function isProxyPlayer(player) {
    return MediaModel.isProxyPlayer(player)
  }

  function hasMetadata(player) {
    return MediaModel.hasMetadata(player)
  }

  function hasTrackMetadata(player) {
    return MediaModel.hasTrackMetadata(player)
  }

  function playerCanControl(player) {
    return MediaModel.playerCanControl(player)
  }

  function capabilityFor(player, action) {
    return MediaModel.capabilityFor(player, action)
  }

  function canHandleAction(player, action) {
    return MediaModel.canHandleAction(player, action)
  }

  function isKnownPlayer(player) {
    return MediaModel.isKnownPlayer(player, players)
  }

  function canCycleSource(player) {
    return MediaModel.canCycleSource(player)
  }

  function nodeProps(node) {
    return MediaModel.nodeProps(node)
  }

  function isPlaybackStream(node) {
    return MediaModel.isPlaybackStream(node)
  }

  function streamLabelKey(label) {
    return MediaModel.streamLabelKey(label)
  }

  function rawStreamLabel(node) {
    return MediaModel.rawStreamLabel(node)
  }

  function playerAppLabel(player) {
    return MediaModel.playerAppLabel(player)
  }

  function playerHasPlaybackStream(player) {
    return MediaModel.playerHasPlaybackStream(player, playbackStreams)
  }

  function playerKey(player) {
    return MediaModel.playerKey(player)
  }

  function playerForKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (playerKey(p) === key) return p
    }
    return null
  }

  function livePlayer(player) {
    if (!player) return null
    var resolved = playerForKey(playerKey(player))
    return resolved || null
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playerStartedAt[key] : undefined
    return value === undefined ? fallback : value
  }

  function syncPlayingOrder() {
    if (!playOrderDirty) return

    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playerStartedAt[key] === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = playerStartedAt[key]
      }
    }

    if (preferredPlayerKey && !alive[preferredPlayerKey]) preferredPlayerKey = ""

    playSerial = serial
    playerStartedAt = next
    playOrderDirty = false
  }

  function orderedSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (hasMetadata(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      if (a.isPlaying && b.isPlaying) {
        var orderDelta = playerOrder(a, 1000) - playerOrder(b, 1000)
        if (orderDelta !== 0) return orderDelta
      }
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function orderedCycleSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (canCycleSource(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function oldestPlayingPlayer(requirePlaybackStream) {
    var oldest = null
    var oldestOrder = 0
    var playingProxy = null
    var proxyOrder = 0

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxyPlayer = isProxyPlayer(p)
      if (p.isPlaying) {
        if (requirePlaybackStream && !playerHasPlaybackStream(p)) continue

        var order = playerOrder(p, i + 1000)
        if (!proxyPlayer && (!oldest || order < oldestOrder)) {
          oldest = p
          oldestOrder = order
        } else if (proxyPlayer && (!playingProxy || order < proxyOrder)) {
          playingProxy = p
          proxyOrder = order
        }
      }
    }

    return oldest || playingProxy || null
  }

  function selectActivePlayer() {
    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var streamPlayer = null
    var streamProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxy = isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && hasMetadata(p)) preferred = p

      if (playerHasPlaybackStream(p)) {
        if (!proxy && !streamPlayer) streamPlayer = p
        else if (proxy && !streamProxy) streamProxy = p
      } else if (hasTrackMetadata(p)) {
        if (!proxy && !trackPlayer) trackPlayer = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (playerCanControl(p)) {
        if (!proxy && !controllablePlayer) controllablePlayer = p
        else if (proxy && !controllableProxy) controllableProxy = p
      } else if (hasMetadata(p)) {
        if (!proxy && !identityPlayer) identityPlayer = p
        else if (proxy && !identityProxy) identityProxy = p
      }
    }

    if (preferred && preferred.isPlaying) return preferred
    var streamCandidate = streamPlayer || streamProxy
    var streamPreferred = preferred && playerHasPlaybackStream(preferred) ? preferred : null
    return oldestPlayingPlayer(true) || oldestPlayingPlayer(false) || streamPreferred || streamCandidate || preferred || trackPlayer || trackProxy || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
  }

  function labelFor(player) {
    return MediaModel.labelFor(player)
  }

  function osdMessage(player, fallback) {
    return MediaModel.osdMessage(player, fallback)
  }

  function trackSignature(player) {
    return MediaModel.trackSignature(player)
  }

  function showOsd(actionLabel, iconName, player, fallbackLabel) {
    if (!shell) return
    var subject = player ? livePlayer(player) : activePlayer
    if (player && !subject) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: iconName || "media",
      message: osdMessage(subject, fallbackLabel || actionLabel)
    }))
  }

  function scheduleShowOsd(actionLabel, iconName, player, label) {
    var key = playerKey(player)
    Qt.callLater(function() {
      var live = key ? playerForKey(key) : null
      if (key && !live) return
      root.showOsd(actionLabel, iconName, live, label)
    })
  }

  function scheduleOsd(actionLabel, iconName, player, waitForTrackChange, beforeTrackSignature) {
    var label = player ? osdMessage(player, actionLabel) : actionLabel
    if (waitForTrackChange) {
      pendingTrackOsd = {
        actionLabel: actionLabel,
        iconName: iconName,
        playerKey: playerKey(player),
        label: label,
        before: beforeTrackSignature
      }
      trackOsdSignalsChanged()
    } else {
      scheduleShowOsd(actionLabel, iconName, player, label)
    }
  }

  function trackOsdSignalsChanged() {
    if (!pendingTrackOsd) return
    var serial = ++trackOsdSerial
    Qt.callLater(function() {
      if (serial === trackOsdSerial) root.flushPendingTrackOsd()
    })
  }

  function flushPendingTrackOsd() {
    var pending = pendingTrackOsd
    if (!pending) return

    var player = playerForKey(pending.playerKey)
    if (!player) {
      cancelPendingTrackOsd()
      return
    }

    if (!MediaModel.trackChanged(pending.before, player)) return

    cancelPendingTrackOsd()
    root.showOsd(pending.actionLabel, pending.iconName, player, pending.label)
  }

  function cancelPendingTrackOsd() {
    pendingTrackOsd = null
    trackOsdSerial += 1
  }

  function selectPlayer(key) {
    var player = playerForKey(key)
    if (!player || !hasMetadata(player)) return false
    preferredPlayerKey = playerKey(player)
    return true
  }

  function playPlayer(player) {
    if (!player) return false
    var capability = capabilityFor(player, "play")
    if (capability === "play") {
      player.play()
      return true
    }
    if (capability === "toggle" && !player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }

  function pausePlayer(player) {
    if (!player) return false
    if (player.canPause) {
      player.pause()
      return true
    }
    if (player.canTogglePlaying && player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }

  function switchSource(delta, transferPlayback, showFeedback) {
    var list = sourceCyclePlayers
    if (!list || list.length === 0) return false

    var activeKey = playerKey(activePlayer)
    var index = 0
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === activeKey) {
        index = i
        break
      }
    }

    index = (index + delta + list.length) % list.length
    var current = livePlayer(activePlayer)
    var next = livePlayer(list[index])
    if (!next) return false

    var currentWasPlaying = current && current.isPlaying
    var currentKey = playerKey(current)
    var nextKey = playerKey(next)

    preferredPlayerKey = nextKey

    if (transferPlayback && currentWasPlaying && nextKey !== currentKey) {
      var nextWasPlaying = next.isPlaying
      var nextStarted = nextWasPlaying || playPlayer(next)
      if (nextStarted) pausePlayer(current)
    }

    if (showFeedback !== false) {
      var feedbackKey = nextKey
      Qt.callLater(function() {
        var feedbackPlayer = root.playerForKey(feedbackKey)
        if (feedbackPlayer) root.showOsd("Source", "media-source", feedbackPlayer)
      })
    }

    return true
  }

  function playerForAction(action, targetKey) {
    return MediaModel.routeAction(players, action, {
      targetKey: String(targetKey || ""),
      activeKey: playerKey(activePlayer),
      hasStream: function(player) { return root.playerHasPlaybackStream(player) },
      orderOf: function(player) { return root.playerOrder(player, 1000) }
    })
  }

  function runAction(action, showFeedback, targetKey) {
    var player = playerForAction(action, targetKey)
    if (!player) {
      if (showFeedback !== false && players.length > 0) root.showOsd(actionLabelFor(action), iconNameFor(action), null)
      return false
    }

    var key = playerKey(player)
    var capability = capabilityFor(player, action)
    var actionLabel = actionLabelFor(action, player, capability)
    var iconName = iconNameFor(action, player)
    var beforeTrackSignature = trackSignature(player)
    var handled = false

    if (action === "next" && capability === "next") {
      player.next()
      handled = true
    } else if (action === "previous" && capability === "previous") {
      player.previous()
      handled = true
    } else if (action === "play" && capability === "play") {
      player.play()
      handled = true
    } else if (action === "play" && capability === "toggle" && !player.isPlaying) {
      player.togglePlaying()
      handled = true
    } else if (action === "pause" && capability === "pause") {
      player.pause()
      handled = true
    } else if (action === "pause" && capability === "toggle" && player.isPlaying) {
      player.togglePlaying()
      handled = true
    } else if (action === "playPause" && capability === "playPause") {
      if (player.isPlaying && player.canPause) {
        player.pause()
      } else if (!player.isPlaying && player.canPlay) {
        player.play()
      } else {
        return false
      }
      handled = true
    } else if (action === "playPause" && capability === "toggle") {
      player.togglePlaying()
      handled = true
    }

    if (!handled) {
      if (showFeedback !== false) root.showOsd(actionLabel, iconName, player)
      return false
    }

    if (key) preferredPlayerKey = key
    if (showFeedback !== false)
      scheduleOsd(actionLabel, iconName, player, action === "next" || action === "previous", beforeTrackSignature)
    return true
  }

  function actionLabelFor(action, player, capability) {
    if (action === "next") return "Next"
    if (action === "previous") return "Previous"
    if (action === "play") return "Play"
    if (action === "pause") return "Pause"
    if (action === "playPause") {
      if (player && capability) return player.isPlaying ? "Pause" : "Play"
      return "Play/pause"
    }
    return "Play/pause"
  }

  function iconNameFor(action, player) {
    if (action === "next") return "media-next"
    if (action === "previous") return "media-previous"
    if (action === "play") return "media-play"
    if (action === "pause") return "media-pause"
    if (action === "playPause") return player && player.isPlaying ? "media-pause" : "media-play"
    return "media"
  }

  // Recompute play-order reactively instead of polling every 500ms.
  // syncPlayingOrder only depends on the set of players and each player's
  // isPlaying state: onPlayersChanged covers players appearing/disappearing,
  // and the Instantiator wires isPlayingChanged for each live player.
  property bool playOrderDirty: true

  function markPlayOrderDirty() {
    playOrderDirty = true
    root.syncPlayingOrder()
  }

  Component.onCompleted: root.markPlayOrderDirty()
  onPlayersChanged: {
    if (pendingTrackOsd) {
      if (playerForKey(pendingTrackOsd.playerKey)) trackOsdSignalsChanged()
      else cancelPendingTrackOsd()
    }
    root.markPlayOrderDirty()
  }

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.markPlayOrderDirty() }
      function onTrackTitleChanged() { root.trackOsdSignalsChanged() }
      function onTrackArtistChanged() { root.trackOsdSignalsChanged() }
      function onTrackAlbumChanged() { root.trackOsdSignalsChanged() }
      function onTrackArtUrlChanged() { root.trackOsdSignalsChanged() }
    }
  }

  PwObjectTracker { objects: root.playbackStreams }

  function statusJson() {
    var p = activePlayer
    return JSON.stringify({
      hasPlayer: p !== null,
      hasMedia: root.hasMedia,
      playing: p ? !!p.isPlaying : false,
      identity: p ? (p.identity || "") : "",
      desktopEntry: p ? (p.desktopEntry || "") : "",
      title: p ? (p.trackTitle || "") : "",
      artist: p ? (p.trackArtist || "") : "",
      album: p && p.trackAlbum ? p.trackAlbum : "",
      artUrl: p && p.trackArtUrl ? p.trackArtUrl : "",
      canGoNext: p ? !!p.canGoNext : false,
      canGoPrevious: p ? !!p.canGoPrevious : false,
      canTogglePlaying: p ? !!p.canTogglePlaying : false
    })
  }

  function ipcActionResult(action) {
    if (players.length === 0) return "no-player"
    return runAction(action, true) ? "ok" : "unhandled"
  }

  function ipcSourceResult(delta, transferPlayback) {
    if (players.length === 0) return "no-player"
    return switchSource(delta, transferPlayback, true) ? "ok" : "unhandled"
  }

  IpcHandler {
    target: "media"

    function status(): string {
      return root.statusJson()
    }

    function playPause(): string {
      return root.ipcActionResult("playPause")
    }

    function next(): string {
      return root.ipcActionResult("next")
    }

    function previous(): string {
      return root.ipcActionResult("previous")
    }

    function play(): string {
      return root.ipcActionResult("play")
    }

    function pause(): string {
      return root.ipcActionResult("pause")
    }

    function sourceNext(): string {
      return root.ipcSourceResult(1, false)
    }

    function sourcePrevious(): string {
      return root.ipcSourceResult(-1, false)
    }

    function sourceSwitch(): string {
      return root.ipcSourceResult(1, true)
    }

    function sourceSwitchPrevious(): string {
      return root.ipcSourceResult(-1, true)
    }

    function ping(): string {
      return "ok"
    }
  }
}
