const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const Model = require("../shell/plugins/panels/clock/Model.js")

const CLOCK_DIR = path.join(__dirname, "..", "shell", "plugins", "panels", "clock")
const WIDGET = path.join(CLOCK_DIR, "BarWidget.qml")
const PANEL = path.join(CLOCK_DIR, "Panel.qml")
const SHELL = path.join(__dirname, "..", "shell", "shell.qml")
const ALT = "d MMMM 'W'ww yyyy"
const VERTICAL_ALT = "dd\nMMM\n'W'ww\n''yy"

// What updateEntryInline does: merge the given keys into the stored entry.
function mergeEntry(entry, patch) {
  const next = Object.assign({}, entry)
  for (const key in patch) if (key !== "id") next[key] = patch[key]
  return next
}

// A widget instance. Writing settings rebuilds it, which throws away local
// state, and the replacement is handed the entry as it was *before* the write —
// applySettingsDelta patches the live layout in place, which the bar's Repeater
// model never sees. `sync` is the widget asking the shell what is stored now.
function clockHarness(initial, { vertical = false, sync = true } = {}) {
  const key = vertical ? "verticalFormat" : "format"
  const alt = vertical ? VERTICAL_ALT : ALT
  let config = { id: "omarchy.clock", format: "dddd HH:mm", formatAlt: ALT, verticalFormat: "HH\n—\nmm" }
  config[key] = initial

  let widget = null
  function build(staleEntry) {
    widget = {
      injected: Object.assign({}, staleEntry),
      active: String(staleEntry[key] || ""),
      syncFromShell() {
        if (sync && config[key]) this.active = String(config[key])
      }
    }
  }
  build(config)

  return {
    get label() {
      return widget.active
    },
    get config() {
      return config
    },
    cycle() {
      widget.syncFromShell()
      const from = widget.active
      const ring = Model.clockFormatRing(from, alt, Model.clockFormats(vertical))
      const next = Model.nextClockFormat(ring, from)
      if (next === "" || next === from) return false

      const before = Object.assign({}, config)
      config = mergeEntry(config, { [key]: next })
      widget.active = next
      widget.injected = mergeEntry(widget.injected, { [key]: next })
      build(before) // the write rebuilds the widget with the pre-write entry
      widget.syncFromShell() // ...whose onCompleted sync adopts the stored value
      return true
    }
  }
}

test("cycling walks every format although each write rebuilds the widget", () => {
  const clock = clockHarness("dddd HH:mm")
  const presets = Model.clockFormats(false)

  for (let i = 0; i < presets.length; i++) {
    assert.equal(clock.cycle(), true, `cycle ${i + 1} should advance`)
    assert.equal(clock.label, clock.config.format, "label shows the stored format")
  }

  assert.equal(clock.config.format, presets[0], "the ring wraps back to the first format")
})

test("without asking the shell, clicks only advance every other time", () => {
  // The reported symptom: right-clicking appears to toggle between two formats.
  // Each write rebuilds the widget with the pre-write entry, so the next click
  // recomputes the format already stored and only every second click moves on.
  function distinctAfterSixClicks(sync) {
    const clock = clockHarness("dddd HH:mm", { sync })
    const written = new Set()
    for (let i = 0; i < 6; i++) {
      clock.cycle()
      written.add(clock.config.format)
    }
    return written
  }

  const stale = distinctAfterSixClicks(false)
  const fresh = distinctAfterSixClicks(true)

  assert.equal(stale.size, 3, "a stale injected entry halves the cycle rate")
  assert.equal(fresh.size, 6, "reading the stored format advances on every click")
  assert.ok(
    [...stale].some((format) => format === "dddd HH:mm" || format === "dddd h:mm AP"),
    "the stale cycle keeps coming back to the same formats"
  )
})

test("a rebuilt widget adopts the stored format", () => {
  const clock = clockHarness("HH:mm")
  clock.cycle()
  assert.equal(clock.config.format, "h:mm AP")
  assert.equal(clock.label, "h:mm AP", "the replacement widget must not show the previous format")
})

test("vertical cycling walks every format", () => {
  const clock = clockHarness("HH\n—\nmm", { vertical: true })
  const presets = Model.clockFormats(true)
  assert.equal(presets.length, 4)

  for (let i = 0; i < presets.length; i++) {
    assert.equal(clock.cycle(), true, `cycle ${i + 1} should advance`)
    assert.equal(clock.config.verticalFormat, presets[(i + 1) % presets.length])
  }
})

test("the alt format joins the ring and the current format is not repeated", () => {
  const presets = Model.clockFormats(false)
  const ring = Model.clockFormatRing("HH:mm", ALT, presets)
  assert.equal(new Set(ring).size, ring.length, "ring entries must be unique")
  assert.ok(ring.includes("HH:mm"), "the configured format is offered")
  assert.ok(ring.includes(ALT), "alt format should be offered")
  assert.equal(ring.length, presets.length, "ALT is a preset, so it is not appended twice")
})

test("a panel change does not write the label format back from a stale copy", () => {
  const clock = clockHarness("dddd HH:mm")
  const presets = Model.clockFormats(false)
  for (let i = 0; i < presets.length - 1; i++) clock.cycle()
  const cycled = clock.config.format
  assert.notEqual(cycled, "dddd HH:mm")

  // The panel still holds the entry from before those clicks, and persists a
  // week start of its own.
  const stalePanelCopy = { id: "omarchy.clock", format: "dddd HH:mm", formatAlt: ALT, weekStartDay: "monday" }
  const merged = mergeEntry(clock.config, { weekStartDay: "sunday" })

  assert.equal(merged.format, cycled, "persisting weekStartDay must not revert the cycled format")
  assert.equal(merged.weekStartDay, "sunday")
  assert.equal(stalePanelCopy.format, "dddd HH:mm", "the panel's own copy is the stale one")

  const source = fs.readFileSync(PANEL, "utf8")
  const persist = source.slice(source.indexOf("function persistSettings"))
  const body = persist.slice(0, persist.indexOf("\n  }"))
  assert.match(
    body,
    /updateEntryInline\(root\.moduleName, values\)/,
    "persistSettings must send only the keys it changed"
  )
  assert.doesNotMatch(body, /updateEntryInline\(root\.moduleName, entry\)/)
})

test("the widget reads the stored format from the shell", () => {
  const widget = fs.readFileSync(WIDGET, "utf8")
  assert.match(widget, /function syncFormatsFromShell\(\)/)
  assert.match(widget, /entrySettingsInline\(root\.moduleName\)/, "the widget asks the shell for the current value")
  assert.match(widget, /root\.activeHorizontalFormat = String\(current\.format\)/)
  assert.match(widget, /root\.activeVerticalFormat = String\(current\.verticalFormat\)/)
  assert.match(
    widget,
    /function cycleFormat\(\) \{[^}]*syncFormatsFromShell\(\)/,
    "cycling must sync before computing the next format"
  )
  assert.doesNotMatch(widget, /cycledHorizontalFormat|cycledVerticalFormat/)
})

test("the shell exposes an authoritative inline settings reader", () => {
  const shell = fs.readFileSync(SHELL, "utf8")
  const start = shell.indexOf("function entrySettingsInline")
  assert.ok(start > 0, "shell.qml should define entrySettingsInline")
  const body = shell.slice(start, shell.indexOf("\n  }", start))
  assert.match(body, /shellConfig \|\| builtinShellConfig/, "it must read the in-memory config")
  assert.match(body, /source\.bar\.layout/, "it must look in the bar layout")
  assert.match(body, /if \(key !== "id"\) copy\[key\] = entry\[key\]/, "id is not a setting")
})
