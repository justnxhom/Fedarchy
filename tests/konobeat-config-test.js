const test = require("node:test")
const assert = require("node:assert/strict")
const path = require("node:path")

const Config = require("../shell/plugins/konobeat/VisualizerConfig.js")

test("an absent file leaves the visualizer as it was", () => {
  const config = Config.parse("")
  assert.equal(config.bands, 0, "no explicit count")
  assert.equal(config.width, 0, "no explicit width")
  assert.equal(config.height, Config.DEFAULT_HEIGHT)
  assert.equal(config.color, "")
  assert.deepEqual(config.warnings, [])
})

test("a file that is not JSON is reported and ignored", () => {
  const config = Config.parse("{ bands: 12")
  assert.equal(config.bands, 0, "the count is left alone")
  assert.equal(config.warnings.length, 1)
  assert.match(config.warnings[0], /not valid JSON/)
})

test("a file that is not an object is reported and ignored", () => {
  const config = Config.parse("[1, 2, 3]")
  assert.equal(config.bands, 0)
  assert.equal(config.warnings.length, 1)
  assert.match(config.warnings[0], /must be a JSON object/)
})

test("an explicit count is read", () => {
  const config = Config.parse('{ "bands": 12 }')
  assert.equal(config.bands, 12)
  assert.deepEqual(config.warnings, [])
})

test("a count outside the range is pulled back and reported", () => {
  const config = Config.parse('{ "bands": 500 }')
  assert.equal(config.bands, Config.BAND_COUNT_MAX)
  assert.equal(config.warnings.length, 1)
  assert.match(config.warnings[0], /clamped/)

  const low = Config.parse('{ "bands": 1 }')
  assert.equal(low.bands, Config.BAND_COUNT_MIN)
  assert.equal(low.warnings.length, 1)
})

test("a count that is not a number is refused", () => {
  const config = Config.parse('{ "bands": "many" }')
  assert.equal(config.bands, 0)
  assert.equal(config.warnings.length, 1)
  assert.match(config.warnings[0], /must be a number/)
})

test("a fractional count is rounded and reported", () => {
  const config = Config.parse('{ "bands": 12.4 }')
  assert.equal(config.bands, 12)
  assert.match(config.warnings[0], /rounded/)
})

test("an explicit count wins over the derived one", () => {
  const config = Config.parse('{ "bands": 24 }')
  assert.equal(Config.effectiveBands(config, 32, 18), 24)
})

test("without a count the bars are derived from the size, as before", () => {
  const config = Config.parse("{}")
  // The width and height the bar has always used: 8 columns at the default
  // size, and 16 at the widest the setting allowed.
  assert.equal(Config.effectiveBands(config, 32, 18), 8)
  assert.equal(Config.effectiveBands(config, 64, 18), 16)
  assert.equal(Config.effectiveBands(config, 16, 18), 4, "never fewer than four")
  assert.equal(Config.effectiveBands(config, 200, 18), 16, "never more than sixteen")
})

test("the derived count is the one the plugin has always drawn", () => {
  // The formula the plugin used before the configuration file existed.
  const legacy = (width, height) =>
    Math.max(4, Math.min(16, Math.round(width / Math.max(1, height) * 4.5)))

  for (const width of [16, 24, 32, 48, 64, 80]) {
    for (const height of [8, 12, 18, 24, 32]) {
      assert.equal(
        Config.effectiveBands(Config.parse("{}"), width, height),
        legacy(width, height),
        `${width}x${height}`
      )
    }
  }
})

test("a size of zero falls back to the smallest count", () => {
  const config = Config.parse("{}")
  assert.equal(Config.effectiveBands(config, 0, 0), 4)
  assert.equal(Config.effectiveBands(config, 32, 0), 4)
})

test("the width and height are read and bounded", () => {
  const config = Config.parse('{ "width": 48, "height": 24 }')
  assert.equal(config.width, 48)
  assert.equal(config.height, 24)
  assert.deepEqual(config.warnings, [])

  const wide = Config.parse('{ "width": 900 }')
  assert.equal(wide.width, Config.WIDTH_MAX)
  assert.match(wide.warnings[0], /clamped/)

  const tall = Config.parse('{ "height": 900 }')
  assert.equal(tall.height, Config.HEIGHT_MAX)
})

test("the height falls back to the default", () => {
  assert.equal(Config.effectiveHeight(Config.parse("{}")), Config.DEFAULT_HEIGHT)
  assert.equal(Config.effectiveHeight(Config.parse('{ "height": 30 }')), 30)
})

test("a hex colour is read", () => {
  for (const color of ["#81a1c1", "#abc", "#81a1c1ff"]) {
    const config = Config.parse(JSON.stringify({ color }))
    assert.equal(config.color, color)
    assert.deepEqual(config.warnings, [], color)
  }
})

test("a colour that is not hex is refused", () => {
  // A name Qt does not know resolves to an invalid colour, and an invalid
  // colour makes the visualizer draw nothing at all.
  const named = Config.parse('{ "color": "nordic blue" }')
  assert.equal(named.color, "")
  assert.equal(named.warnings.length, 1)
  assert.match(named.warnings[0], /hex colour/)

  const broken = Config.parse('{ "color": "#12345" }')
  assert.equal(broken.color, "")
  assert.equal(broken.warnings.length, 1)
})

test("an empty colour is not a warning", () => {
  const config = Config.parse('{ "color": "" }')
  assert.equal(config.color, "")
  assert.deepEqual(config.warnings, [])
})

test("one bad value does not cost the others", () => {
  const config = Config.parse('{ "bands": 12, "color": "not a colour", "width": 40 }')
  assert.equal(config.bands, 12)
  assert.equal(config.width, 40)
  assert.equal(config.color, "")
  assert.equal(config.warnings.length, 1, "only the colour is reported")
})
