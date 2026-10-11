const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const model = require("../shell/plugins/services/media/MediaModel.js")

const servicePath = path.join(__dirname, "../shell/plugins/services/media/Service.qml")
const serviceSource = fs.readFileSync(servicePath, "utf8")

function extractFunction(name) {
  const marker = `function ${name}(`
  const start = serviceSource.indexOf(marker)
  assert.notEqual(start, -1, `${name} exists in Service.qml`)
  const open = serviceSource.indexOf("{", start + marker.length)
  let depth = 0
  let quote = ""
  let escaped = false
  for (let i = open; i < serviceSource.length; i += 1) {
    const character = serviceSource[i]
    if (quote) {
      if (escaped) escaped = false
      else if (character === "\\") escaped = true
      else if (character === quote) quote = ""
      continue
    }
    if (character === '"' || character === "'") {
      quote = character
      continue
    }
    if (character === "{") depth += 1
    if (character === "}") {
      depth -= 1
      if (depth === 0) return serviceSource.slice(start, i + 1)
    }
  }
  assert.fail(`${name} has a complete function body`)
}

function qmlFunctions(names) {
  const context = {}
  vm.createContext(context)
  const methods = names.map(name => `var ${name} = ${extractFunction(name)}`).join(";")
  vm.runInContext(`${methods};`, context)
  return context
}

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

test("QML no-player IPC contract is explicit and side-effect free", () => {
  const functions = qmlFunctions(["runAction", "ipcActionResult", "ipcSourceResult", "statusJson"])
  const root = Object.assign(functions, {
    players: [],
    activePlayer: null,
    hasMedia: false,
    osdCalls: 0,
    playerForAction: () => null,
    showOsd: () => { root.osdCalls += 1 }
  })
  root.root = root

  root.runAction("play", true)
  assert.equal(root.osdCalls, 0)
  assert.equal(root.ipcActionResult("play"), "no-player")
  assert.equal(root.ipcSourceResult(1, false), "no-player")
  assert.deepEqual(JSON.parse(root.statusJson()), {
    hasPlayer: false,
    hasMedia: false,
    playing: false,
    identity: "",
    desktopEntry: "",
    title: "",
    artist: "",
    album: "",
    artUrl: "",
    canGoNext: false,
    canGoPrevious: false,
    canTogglePlaying: false
  })
})

test("QML delayed OSD callbacks ignore a disappeared player", () => {
  const functions = qmlFunctions(["showOsd", "scheduleShowOsd", "scheduleOsd", "trackOsdSignalsChanged", "flushPendingTrackOsd", "cancelPendingTrackOsd", "switchSource"])
  const queue = []
  const calls = []
  const current = player({ dbusName: "current", trackTitle: "Old" })
  const root = Object.assign(functions, {
    MediaModel: model,
    shell: { summon: (target, payload) => calls.push({ target, payload: JSON.parse(payload) }) },
    activePlayer: current,
    sourceCyclePlayers: [current],
    preferredPlayerKey: "",
    players: [current],
    pendingTrackOsd: null,
    trackOsdSerial: 0,
    playerKey: model.playerKey,
    playerForKey: key => root.players.find(item => model.playerKey(item) === key) || null,
    livePlayer: item => root.playerForKey(model.playerKey(item)),
    osdMessage: (item, fallback) => item ? `${item.trackTitle} - ${item.trackArtist}` : fallback,
    trackChanged: model.trackChanged
  })
  root.root = root
  root.Qt = { callLater: callback => queue.push(callback) }

  root.scheduleShowOsd("Pause", "media-pause", current, "Old")
  root.players = []
  while (queue.length) queue.shift()()
  assert.equal(calls.length, 0)

  root.players = [current]
  root.scheduleOsd("Next", "media-next", current, true, model.trackSignature(current))
  root.players = []
  while (queue.length) queue.shift()()
  assert.equal(calls.length, 0)
  assert.equal(root.pendingTrackOsd, null)

  root.players = [current]
  root.switchSource(1, false, true)
  root.players = []
  while (queue.length) queue.shift()()
  assert.equal(calls.length, 0)
})

test("QML track OSD flushes from coalesced property-change callbacks", () => {
  const functions = qmlFunctions(["showOsd", "scheduleOsd", "trackOsdSignalsChanged", "flushPendingTrackOsd", "cancelPendingTrackOsd"])
  const queue = []
  const calls = []
  const current = player({ dbusName: "current", trackTitle: "Old", trackArtist: "Artist" })
  const root = Object.assign(functions, {
    MediaModel: model,
    shell: { summon: (target, payload) => calls.push({ target, payload: JSON.parse(payload) }) },
    activePlayer: current,
    players: [current],
    pendingTrackOsd: null,
    trackOsdSerial: 0,
    playerKey: model.playerKey,
    playerForKey: key => root.players.find(item => model.playerKey(item) === key) || null,
    livePlayer: item => root.playerForKey(model.playerKey(item)),
    osdMessage: (item, fallback) => item ? `${item.trackTitle} - ${item.trackArtist}` : fallback,
    trackChanged: model.trackChanged
  })
  root.root = root
  root.Qt = { callLater: callback => queue.push(callback) }

  const before = model.trackSignature(current)
  root.scheduleOsd("Next", "media-next", current, true, before)
  current.trackTitle = "New"
  root.trackOsdSignalsChanged()
  current.trackArtist = "New Artist"
  root.trackOsdSignalsChanged()
  assert.equal(queue.length, 3)
  while (queue.length) queue.shift()()
  assert.deepEqual(calls, [{ target: "omarchy.osd", payload: { icon: "media-next", message: "New - New Artist" } }])
  assert.equal(root.pendingTrackOsd, null)
})

test("QML runAction routes to a player that can execute the requested action", () => {
  const functions = qmlFunctions(["runAction", "actionLabelFor", "iconNameFor"])
  const active = player({ dbusName: "active", trackTitle: "Active", isPlaying: true })
  const next = player({ dbusName: "next", trackTitle: "Next" })
  const previous = player({ dbusName: "previous", trackTitle: "Previous" })
  const paused = player({ dbusName: "paused", trackTitle: "Paused", canPlay: true })
  const playing = player({ dbusName: "playing", trackTitle: "Playing", isPlaying: true, canPause: true })
  const players = [active, next, previous, paused, playing]
  const calls = []
  active.togglePlaying = () => calls.push("active.toggle")
  next.next = () => calls.push("next.next")
  previous.previous = () => calls.push("previous.previous")
  paused.play = () => calls.push("paused.play")
  playing.pause = () => calls.push("playing.pause")
  const root = Object.assign(functions, {
    players,
    activePlayer: active,
    preferredPlayerKey: "",
    playerKey: model.playerKey,
    playerForAction: (action, targetKey) => model.routeAction(players, action, { targetKey, activeKey: "active" }),
    capabilityFor: model.capabilityFor,
    trackSignature: model.trackSignature,
    scheduleOsd: () => {},
    showOsd: () => {}
  })
  root.root = root

  assert.equal(root.runAction("play", false, "active"), true)
  assert.equal(root.runAction("pause", false, "active"), true)
  assert.equal(root.runAction("playPause", false, "active"), true)
  next.canGoNext = true
  previous.canGoPrevious = true
  assert.equal(root.runAction("next", false, "active"), true)
  assert.equal(root.runAction("previous", false, "active"), true)
  assert.deepEqual(calls, ["paused.play", "playing.pause", "playing.pause", "next.next", "previous.previous"])
})
