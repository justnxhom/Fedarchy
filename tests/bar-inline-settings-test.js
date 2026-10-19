const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const BAR = path.join(__dirname, "..", "shell", "plugins", "bar", "Bar.qml")
const MODEL = path.join(__dirname, "..", "shell", "plugins", "bar", "BarModel.js")

// What BarModel.entrySettings does: everything but the id.
function settingsOf(entry) {
  const copy = {}
  for (const key in entry) if (key !== "id") copy[key] = entry[key]
  return copy
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && entry.id !== undefined && entry.id !== null && String(entry.id) !== "") return String(entry.id)
  return ""
}

// The bar's applySettingsDelta, lifted out of the QML and run as it is.
//
// The function is written in plain JavaScript apart from the QML properties
// it closes over, so it can be evaluated directly. Testing the real thing
// rather than a paraphrase of it is the point: a paraphrase would keep
// passing after the QML was changed, and the change is what the test is for.
function extractApplySettingsDelta() {
  const source = fs.readFileSync(BAR, "utf8")
  const start = source.indexOf("function applySettingsDelta")
  assert.ok(start > 0, "Bar.qml should define applySettingsDelta")
  const end = source.indexOf("\n  }", start)
  assert.ok(end > start, "applySettingsDelta should be a complete function")
  return source.slice(start, end + "\n  }".length)
}

// Models the bar's inline-settings path.
//
// The bar's Repeater models are plain JavaScript arrays. QML never re-diffs
// one when an element is replaced in place, so a slot keeps the entry object
// it was built with, and the settings a widget is injected with are derived
// from that entry. The bar's delta path replaces the element in the layout
// and patches the live widget, which is enough to make the change visible
// once -- but if the slot itself does not follow, the next time the widget
// is rebuilt the bar injects the settings the change replaced, and the change
// silently reverts.
function barHarness(entries) {
  const layoutConfig = { right: entries.map((entry) => Object.assign({}, entry)) }
  const repeaterModel = layoutConfig.right
  const moduleSlots = []

  // injectProps(): the widget is handed the slot's settings.
  function inject(slot) {
    slot.activeItem = { settings: Object.assign({}, slot.moduleSettings) }
  }

  function build() {
    moduleSlots.length = 0
    for (const modelData of repeaterModel) {
      const slot = {
        region: "right",
        moduleName: entryId(modelData),
        entry: modelData,
        get moduleSettings() {
          return settingsOf(this.entry)
        },
        activeItem: null
      }
      inject(slot)
      moduleSlots.push(slot)
    }
  }
  build()

  // The QML function closes over these by name.
  const context = { layoutConfig, moduleSlots, entrySettings: settingsOf, entryId }

  function slotFor(id) {
    return moduleSlots.find((slot) => slot.entry.id === id)
  }

  return {
    // applySettingsDelta takes the list of changes, as BarModel's
    // inlineSettingsDelta produces it.
    applyDelta(changes) {
      const apply = new Function(
        "ctx",
        `with (ctx) { ${extractApplySettingsDelta()}\n return applySettingsDelta; }`
      )(context)
      apply(changes)
    },
    widget(id) {
      return slotFor(id).activeItem
    },
    // The bar recreating a widget -- the plugin's component is reloaded, or a
    // setting change elsewhere rebuilds it -- while the slot that hosts it
    // stays. The widget is then injected with the slot's settings again.
    rebuildWidget() {
      for (const slot of moduleSlots) inject(slot)
    },
    // The bar re-reading its layout: the Repeater is rebuilt and every
    // delegate is created again from the layout.
    rebuildModel() {
      build()
    }
  }
}

const ENTRY = { id: "konochi.konobeat", labelFormat: "song-artist", rhythmStyle: "led" }
const OTHER = { id: "omarchy.power", showPercentage: true }

test("an inline settings change reaches the live widget", () => {
  const bar = barHarness([ENTRY, OTHER])

  bar.applyDelta([{
    region: "right",
    index: 0,
    entry: { id: "konochi.konobeat", labelFormat: "title", rhythmStyle: "wave" }
  }])

  const widget = bar.widget("konochi.konobeat")
  assert.equal(widget.settings.rhythmStyle, "wave", "the widget must see the new visualizer")
  assert.equal(widget.settings.labelFormat, "title", "the widget must see the new label format")
})

test("the change survives a rebuild of the bar's widgets", () => {
  // The reported symptom: the setting is written to shell.json, the widget
  // shows it for a moment, and the next rebuild puts the old value back.
  const bar = barHarness([ENTRY, OTHER])

  bar.applyDelta([{
    region: "right",
    index: 0,
    entry: { id: "konochi.konobeat", labelFormat: "title", rhythmStyle: "wave" }
  }])
  bar.rebuildWidget()

  const widget = bar.widget("konochi.konobeat")
  assert.equal(widget.settings.rhythmStyle, "wave", "a rebuild must not revert the visualizer")
  assert.equal(widget.settings.labelFormat, "title", "a rebuild must not revert the label format")
})

test("the change survives the bar re-reading its layout", () => {
  const bar = barHarness([ENTRY, OTHER])

  bar.applyDelta([{
    region: "right",
    index: 0,
    entry: { id: "konochi.konobeat", labelFormat: "none", rhythmStyle: "scope" }
  }])
  bar.rebuildModel()

  assert.equal(bar.widget("konochi.konobeat").settings.rhythmStyle, "scope")
  assert.equal(bar.widget("konochi.konobeat").settings.labelFormat, "none")
})

test("a change to one widget leaves the others alone", () => {
  const bar = barHarness([ENTRY, OTHER])

  bar.applyDelta([{
    region: "right",
    index: 0,
    entry: { id: "konochi.konobeat", labelFormat: "none", rhythmStyle: "scope" }
  }])
  bar.rebuildWidget()

  assert.equal(bar.widget("omarchy.power").settings.showPercentage, true)
  assert.equal(bar.widget("konochi.konobeat").settings.rhythmStyle, "scope")
})

test("the slot follows the change so the derived settings stay in step", () => {
  // The fix itself: the slot's entry is what its settings are derived from.
  const source = fs.readFileSync(BAR, "utf8")
  const start = source.indexOf("function applySettingsDelta")
  const body = source.slice(start, source.indexOf("\n  }", start))

  assert.match(
    body,
    /slot\.entry = change\.entry/,
    "the slot must be pointed at the new entry, or a rebuild injects the old settings"
  )
  assert.match(body, /item\.settings = settings/, "the live widget must be patched")
})

test("BarModel's entry settings keep everything but the id", () => {
  const model = require(MODEL)
  assert.deepEqual(model.entrySettings({ id: "x", a: 1, b: 2 }), { a: 1, b: 2 })
  assert.deepEqual(model.entrySettings({ id: "x" }), {})
})
