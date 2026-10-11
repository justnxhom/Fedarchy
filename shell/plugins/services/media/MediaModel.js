function isProxyPlayer(player) {
  var dbusName = String(player && player.dbusName || "").toLowerCase()
  var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function hasMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
}

function hasTrackMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.trackAlbum || player.trackArtUrl))
}

function playerCanControl(player) {
  return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause || player.canGoNext || player.canGoPrevious))
}

function capabilityFor(player, action) {
  if (!player) return ""

  switch (action) {
    case "next":
      return player.canGoNext ? "next" : ""
    case "previous":
      return player.canGoPrevious ? "previous" : ""
    case "play":
      if (player.canPlay) return "play"
      return player.canTogglePlaying ? "toggle" : ""
    case "pause":
      if (player.canPause) return "pause"
      return player.canTogglePlaying ? "toggle" : ""
    case "playPause":
      if (player.canPlay || player.canPause) return "playPause"
      return player.canTogglePlaying ? "toggle" : ""
  }

  return ""
}

function canHandleAction(player, action) {
  var capability = capabilityFor(player, action)
  if (!capability) return false

  if (action === "play") return !player.isPlaying
  if (action === "pause") return !!player.isPlaying
  if (action === "playPause") {
    if (player.isPlaying) return player.canPause || player.canTogglePlaying
    return !!player.canPlay || !!player.canTogglePlaying
  }

  return true
}

function canCycleSource(player) {
  return !!(player && hasMetadata(player) && (player.isPlaying || player.canPlay))
}

function isKnownPlayer(player, players) {
  if (!player) return false

  var list = Array.isArray(players) ? players : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] === player) return true
  }

  return false
}

function rankActionCandidates(players, action, context) {
  var list = Array.isArray(players) ? players : []
  var settings = context || {}
  var targetKey = String(settings.targetKey || "")
  var activeKey = String(settings.activeKey || "")
  var hasStream = typeof settings.hasStream === "function" ? settings.hasStream : function() { return false }
  var orderOf = typeof settings.orderOf === "function" ? settings.orderOf : function() { return 1000 }
  var scored = []

  for (var i = 0; i < list.length; i++) {
    var player = list[i]
    if (!canHandleAction(player, action)) continue

    var key = playerKey(player)
    var stream = hasStream(player) ? 1 : 0
    var playing = player.isPlaying ? 1 : 0
    var proxy = isProxyPlayer(player) ? 1 : 0
    var targeted = targetKey && key === targetKey ? 0 : 1
    var active = activeKey && key === activeKey ? 0 : 1
    var order = orderOf(player)

    scored.push({
      player: player,
      targeted: targeted,
      active: active,
      playing: playing,
      stream: stream,
      proxy: proxy,
      order: order,
      label: labelFor(player)
    })
  }

  scored.sort(function(a, b) {
    if (a.targeted !== b.targeted) return a.targeted - b.targeted
    if (a.active !== b.active) return a.active - b.active
    if (a.playing !== b.playing) return b.playing - a.playing
    if (a.stream !== b.stream) return b.stream - a.stream
    if (a.proxy !== b.proxy) return a.proxy - b.proxy
    if (a.order !== b.order) return a.order - b.order
    if (a.label === b.label) return 0
    return a.label < b.label ? -1 : 1
  })

  var ranked = []
  for (var j = 0; j < scored.length; j++) ranked.push(scored[j].player)

  return ranked
}

function routeAction(players, action, context) {
  var ranked = rankActionCandidates(players, action, context)

  return ranked.length ? ranked[0] : null
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function streamLabelKey(label) {
  var key = String(label || "").toLowerCase()
  key = key.replace(/^pipewire alsa \[/, "")
  key = key.replace(/\]$/, "")
  key = key.replace(/^alsa playback \[/, "")
  key = key.replace(/[^a-z0-9]+/g, "")
  return key
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"]
    || node.description
    || p["media.name"]
    || p["node.name"]
    || node.name
}

function playerAppLabel(player) {
  if (!player) return ""
  var dbus = String(player.dbusName || "")
  dbus = dbus.replace(/^org\.mpris\.MediaPlayer2\./, "")
  dbus = dbus.replace(/\.instance[0-9]+$/, "")
  return player.desktopEntry || player.identity || dbus
}

function playerHasPlaybackStream(player, playbackStreams) {
  var playerKey = streamLabelKey(playerAppLabel(player))
  if (!playerKey) return false

  var streams = Array.isArray(playbackStreams) ? playbackStreams : []
  for (var i = 0; i < streams.length; i++) {
    var streamKey = streamLabelKey(rawStreamLabel(streams[i]))
    if (!streamKey) continue
    if (streamKey === playerKey
        || streamKey.indexOf(playerKey) !== -1
        || playerKey.indexOf(streamKey) !== -1)
      return true
  }

  return false
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function trackSignature(player) {
  if (!player) return ""

  var title = String(player.trackTitle || "")
  var artist = String(player.trackArtist || "")
  var album = String(player.trackAlbum || "")
  var artUrl = String(player.trackArtUrl || "")

  if (!title && !artist && !album && !artUrl) return ""

  return [title, artist, album, artUrl].join("\u001f")
}

function trackChanged(previousSignature, player) {
  return trackSignature(player) !== String(previousSignature || "")
}

function labelFor(player) {
  if (!player) return ""
  return player.trackTitle || player.identity || player.desktopEntry || ""
}

function osdMessage(player, fallback) {
  if (!player) return fallback
  var label = labelFor(player)
  if (label && player.trackArtist) return label + " - " + player.trackArtist
  return label || fallback
}

if (typeof module !== "undefined") {
  module.exports = {
    isProxyPlayer: isProxyPlayer,
    hasMetadata: hasMetadata,
    hasTrackMetadata: hasTrackMetadata,
    playerCanControl: playerCanControl,
    capabilityFor: capabilityFor,
    canHandleAction: canHandleAction,
    canCycleSource: canCycleSource,
    isKnownPlayer: isKnownPlayer,
    rankActionCandidates: rankActionCandidates,
    routeAction: routeAction,
    nodeProps: nodeProps,
    isPlaybackStream: isPlaybackStream,
    streamLabelKey: streamLabelKey,
    rawStreamLabel: rawStreamLabel,
    playerAppLabel: playerAppLabel,
    playerHasPlaybackStream: playerHasPlaybackStream,
    playerKey: playerKey,
    trackSignature: trackSignature,
    trackChanged: trackChanged,
    labelFor: labelFor,
    osdMessage: osdMessage
  }
}
