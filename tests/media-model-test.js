const test = require("node:test")
const assert = require("node:assert/strict")
const model = require("../shell/plugins/services/media/MediaModel.js")

function player(values) {
  return Object.assign({
    dbusName: "org.mpris.MediaPlayer2.test",
    desktopEntry: "test",
    identity: "Test",
    trackTitle: "",
    trackArtist: "",
    trackAlbum: "",
    trackArtUrl: "",
    isPlaying: false,
    canPlay: false,
    canPause: false,
    canTogglePlaying: false,
    canGoNext: false,
    canGoPrevious: false
  }, values)
}

test("trackSignature handles null and incomplete players", () => {
  assert.equal(model.trackSignature(null), "")
  assert.equal(model.trackSignature(player({})), "")
  assert.equal(model.trackSignature(player({ trackTitle: "Title", trackArtist: "Artist" })), "Title\u001fArtist\u001f\u001f")
  assert.equal(model.trackChanged(null, null), false)
  assert.equal(model.trackChanged(model.trackSignature(player({ trackTitle: "Old" })), player({ trackTitle: "New" })), true)
})

test("player metadata and control helpers are null-safe", () => {
  assert.equal(model.isProxyPlayer(null), false)
  assert.equal(model.hasMetadata(null), false)
  assert.equal(model.hasTrackMetadata(null), false)
  assert.equal(model.playerCanControl(null), false)
  assert.equal(model.canCycleSource(null), false)
  assert.equal(model.isKnownPlayer(null, []), false)
  assert.equal(model.labelFor(null), "")
  assert.equal(model.osdMessage(null, "Fallback"), "Fallback")
  assert.equal(model.playerKey(null), "")
  assert.equal(model.isProxyPlayer(player({ dbusName: "org.mpris.MediaPlayer2.playerctld.instance7" })), true)
  assert.equal(model.hasMetadata(player({ identity: "Player" })), true)
  assert.equal(model.hasTrackMetadata(player({ trackAlbum: "Album" })), true)
  assert.equal(model.playerCanControl(player({ canGoNext: true })), true)
  assert.equal(model.canCycleSource(player({ canPlay: true })), true)
})

test("capabilities distinguish supported and currently actionable controls", () => {
  const playingToggle = player({ isPlaying: true, canTogglePlaying: true })
  const pausedToggle = player({ canTogglePlaying: true })
  const playing = player({ isPlaying: true, canPlay: true, canPause: true })
  const paused = player({ canPlay: true })

  assert.equal(model.capabilityFor(pausedToggle, "play"), "toggle")
  assert.equal(model.capabilityFor(playingToggle, "pause"), "toggle")
  assert.equal(model.capabilityFor(playing, "play"), "play")
  assert.equal(model.canHandleAction(playingToggle, "play"), false)
  assert.equal(model.canHandleAction(pausedToggle, "play"), true)
  assert.equal(model.canHandleAction(pausedToggle, "pause"), false)
  assert.equal(model.canHandleAction(playingToggle, "pause"), true)
  assert.equal(model.canHandleAction(paused, "playPause"), true)
  assert.equal(model.canHandleAction(playing, "playPause"), true)
  assert.equal(model.canHandleAction(player({ isPlaying: true, canPlay: true }), "playPause"), false)
})

test("routeAction falls back to a capable player for every media action", () => {
  const active = player({ dbusName: "active", trackTitle: "Active", isPlaying: true })
  const next = player({ dbusName: "next", trackTitle: "Next" })
  const previous = player({ dbusName: "previous", trackTitle: "Previous" })
  const paused = player({ dbusName: "paused", trackTitle: "Paused", canPlay: true })
  const playing = player({ dbusName: "playing", trackTitle: "Playing", isPlaying: true, canPause: true })
  const players = [active, next, previous, paused, playing]
  const context = { targetKey: "active", activeKey: "active" }

  next.canGoNext = true
  previous.canGoPrevious = true

  assert.equal(model.routeAction(players, "play", context), paused)
  assert.equal(model.routeAction(players, "pause", context), playing)
  assert.equal(model.routeAction(players, "playPause", context), playing)
  assert.equal(model.routeAction(players, "next", context), next)
  assert.equal(model.routeAction(players, "previous", context), previous)
})

test("candidate ranking keeps targeted, active, playing, and streamed players first", () => {
  const target = player({ dbusName: "target", trackTitle: "Target" })
  const active = player({ dbusName: "active", trackTitle: "Active" })
  const streamed = player({ dbusName: "streamed", trackTitle: "Streamed" })
  const ordered = player({ dbusName: "ordered", trackTitle: "Ordered" })
  for (const item of [target, active, streamed, ordered]) item.canGoNext = true
  streamed.isPlaying = true

  const ranked = model.rankActionCandidates([ordered, streamed, active, target], "next", {
    targetKey: "target",
    activeKey: "active",
    hasStream: item => item === streamed,
    orderOf: item => item === ordered ? 1 : 2
  })

  assert.deepEqual(ranked, [target, active, streamed, ordered])
})

test("stream matching helpers handle PipeWire nodes", () => {
  const node = {
    ready: true,
    isStream: true,
    isSink: true,
    type: "Stream/Output/Audio",
    properties: { "application.name": "PipeWire ALSA [firefox]" }
  }

  assert.deepEqual(model.nodeProps(node), node.properties)
  assert.equal(model.isPlaybackStream(node), true)
  assert.equal(model.streamLabelKey("PipeWire ALSA [Firefox]"), "firefox")
  assert.equal(model.rawStreamLabel(node), "PipeWire ALSA [firefox]")
  assert.equal(model.playerAppLabel(player({ dbusName: "org.mpris.MediaPlayer2.firefox.instance2" })), "test")
  assert.equal(model.playerHasPlaybackStream(player({ desktopEntry: "firefox" }), [node]), true)
  assert.equal(model.playerHasPlaybackStream(player({ desktopEntry: "chromium" }), [node]), false)
})
