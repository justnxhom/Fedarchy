// The visualizer's appearance, read from the user's own configuration file.
//
// The file is optional, every value in it is optional, and every value is
// checked on its own. A typo must not be able to stop the visualizer from
// drawing, so a value that does not make sense is corrected and reported
// rather than obeyed.
//
// Everything here is locale- and Qt-free so it can be unit tested under node;
// the QML owns the colour and the geometry.

var BAND_COUNT_MIN = 4
var BAND_COUNT_MAX = 64

// Without an explicit count the bars are derived from the size of the
// visualizer, which is what the plugin has always done.
var DERIVED_BAND_COUNT_MIN = 4
var DERIVED_BAND_COUNT_MAX = 16
var DERIVED_BAND_RATIO = 4.5

var WIDTH_MIN = 16
var WIDTH_MAX = 160
var HEIGHT_MIN = 8
var HEIGHT_MAX = 48

var DEFAULT_HEIGHT = 18

// A colour is a hex triple or quad. Names are refused on purpose: a name
// QML does not know resolves to an invalid colour, and an invalid colour
// makes the visualizer draw nothing at all.
var COLOR_PATTERN = /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/

function clamp(value, min, max) {
  if (value < min) return min
  if (value > max) return max
  return value
}

function isNumber(value) {
  return typeof value === "number" && isFinite(value)
}

// Reads a number that must fall inside a range. A value outside the range is
// pulled back to the nearest end and the correction is reported, so a
// configuration that asks for 500 bars gets 64 and a word about it rather
// than being ignored.
function readNumber(raw, name, min, max, warnings) {
  if (raw === undefined || raw === null) return 0
  var number = Number(raw)
  if (!isFinite(number)) {
    warnings.push(name + " must be a number")
    return 0
  }
  var rounded = Math.round(number)
  if (rounded !== number) warnings.push(name + " was rounded to " + rounded)
  var clamped = clamp(rounded, min, max)
  if (clamped !== rounded) warnings.push(name + " was clamped to " + clamped)
  return clamped
}

// Parses the configuration file. Always returns a usable configuration: the
// defaults are in place before anything is read, and anything unreadable
// leaves them alone.
function parse(text) {
  var config = {
    bands: 0,
    width: 0,
    height: DEFAULT_HEIGHT,
    color: "",
    warnings: []
  }

  var raw = String(text === undefined || text === null ? "" : text).trim()
  if (!raw) return config

  var parsed = null
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    config.warnings.push("configuration is not valid JSON: " + (e && e.message ? e.message : e))
    return config
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    config.warnings.push("configuration must be a JSON object")
    return config
  }

  config.bands = readNumber(parsed.bands, "bands", BAND_COUNT_MIN, BAND_COUNT_MAX, config.warnings)
  config.width = readNumber(parsed.width, "width", WIDTH_MIN, WIDTH_MAX, config.warnings)
  config.height = readNumber(parsed.height, "height", HEIGHT_MIN, HEIGHT_MAX, config.warnings)

  if (parsed.color !== undefined && parsed.color !== null && parsed.color !== "") {
    var color = String(parsed.color).trim()
    if (COLOR_PATTERN.test(color)) config.color = color
    else config.warnings.push("color must be a hex colour such as #81a1c1")
  }

  return config
}

// The number of bars to draw. An explicit count wins; otherwise the count is
// derived from the size of the visualizer, as it always has been.
function effectiveBands(config, width, height) {
  if (config && config.bands > 0) return config.bands
  var w = Number(width) || 0
  var h = Number(height) || 0
  if (w <= 0 || h <= 0) return DERIVED_BAND_COUNT_MIN
  var derived = Math.round(w / Math.max(1, h) * DERIVED_BAND_RATIO)
  return clamp(derived, DERIVED_BAND_COUNT_MIN, DERIVED_BAND_COUNT_MAX)
}

// The height to draw at. An explicit height wins; otherwise the default.
function effectiveHeight(config) {
  if (config && config.height > 0) return config.height
  return DEFAULT_HEIGHT
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    effectiveBands: effectiveBands,
    effectiveHeight: effectiveHeight,
    BAND_COUNT_MIN: BAND_COUNT_MIN,
    BAND_COUNT_MAX: BAND_COUNT_MAX,
    WIDTH_MIN: WIDTH_MIN,
    WIDTH_MAX: WIDTH_MAX,
    HEIGHT_MIN: HEIGHT_MIN,
    HEIGHT_MAX: HEIGHT_MAX,
    DEFAULT_HEIGHT: DEFAULT_HEIGHT
  }
}
