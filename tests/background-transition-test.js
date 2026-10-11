const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const BACKGROUND = path.join(__dirname, "..", "shell", "plugins", "background", "Background.qml")
const source = fs.readFileSync(BACKGROUND, "utf8")

// The transitions are deliberately built from clip, transform and opacity only.
// A ShaderEffect would need a precompiled .qsb tied to the installed Qt
// version, and an extra full-screen pass per frame; both are guarded here so a
// future change that reaches for a shader has to say why.
const GPU_ONLY_PRIMITIVES = ["clip:", "transform: Translate", "opacity:"]

test("the wallpaper transitions use no shader", () => {
  assert.doesNotMatch(source, /ShaderEffect/, "a shader would need a version-locked .qsb artifact")
  assert.doesNotMatch(source, /MultiEffect/, "an extra effect pass costs a full-screen render target")
  for (const primitive of GPU_ONLY_PRIMITIVES) {
    assert.ok(source.includes(primitive), `expected the reveal to use ${primitive}`)
  }
})

test("the transition types are offered and validated", () => {
  assert.match(source, /readonly property var transitionTypes: \["fade", "slide", "wipe", "random"\]/)
  assert.match(source, /readonly property var concreteTransitions: \["fade", "slide", "wipe"\]/)
  // "random" must choose from the concrete list, never from itself.
  const pick = source.slice(source.indexOf("function resolveTransition"))
  assert.match(pick.slice(0, pick.indexOf("\n  }")), /concreteTransitions\[Math\.floor\(Math\.random\(\) \* concreteTransitions\.length\)\]/)
})

test("a slide picks one of the four edge directions", () => {
  const body = source.slice(source.indexOf("function resolveTransition"))
  assert.match(body, /\[\[1, 0\], \[-1, 0\], \[0, 1\], \[0, -1\]\]/)
})

test("a wipe reveals a band rather than a second copy of the image", () => {
  // The layer is narrowed to the sweep and clips the full-size image inside it,
  // so no extra decode or texture is needed to cover the outgoing wallpaper.
  assert.match(source, /width: root\.transitionUsesWipe \? panel\.width \* root\.revealProgress : panel\.width/)
  assert.match(source, /clip: root\.transitionUsesWipe/)
  // The image inside stays full-size and simply overflows the band.
  assert.match(source, /id: incomingFrame[\s\S]{0,220}?width: panel\.width/)
})

test("the base layer only re-reads its file when it is asked to", () => {
  // backgroundVersion changes on every transition; if it drove the base
  // image's cache-busting query, every switch would decode a full-screen image
  // that was already on screen. Only a refetch may do that.
  assert.match(source, /version: root\.baseContentVersion/)
  assert.doesNotMatch(source, /version: root\.backgroundVersion/)
  const refetch = source.slice(source.indexOf("const refetchInPlace"), source.indexOf("oldBackground = displayedBackground || fromPath"))
  assert.match(refetch, /baseContentVersion \+= 1/)
})

test("the outgoing frame is kept decoded so a switch never blanks", () => {
  // Emptying oldBackground hands the texture back, which is what made the
  // desktop flash black for a few frames at the start of a switch.
  assert.doesNotMatch(source, /oldBackground = ""/, "the outgoing frame must stay warm")
  assert.match(source, /oldBackground = displayedBackground \|\| fromPath/)
  assert.match(source, /root\.oldBackground = root\.displayedBackground/)
})

test("the transition choice is settable and remembered", () => {
  assert.match(source, /function setTransition\(type: string\): string/)
  assert.match(source, /if \(root\.transitionTypes\.indexOf\(wanted\) === -1\) return "invalid"/)
  assert.match(source, /readonly property string transitionStatePath: stateHome \+ "\/omarchy\/current\/background-transition"/)
  assert.match(source, /savedTransition\.reload\(\)/)
})

test("the reveal animation itself is unchanged and still short", () => {
  assert.match(source, /property int revealDuration: 320/)
  assert.match(source, /duration: root\.revealDuration/)
  assert.match(source, /easing\.type: Easing\.InOutCubic/)
})
