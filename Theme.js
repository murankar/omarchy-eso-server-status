// Theme-aware status colour picking.
//
// Omarchy themes expose a named palette in colors.toml, but the names are not
// reliably semantic: several stock themes ship a blue under `green`
// (lumon), a purple under `green` (lupine), a grey under `green` (white), or
// an amber under `green` (matte-black). Reading `green` directly would render
// the wrong hue on those themes.
//
// So instead of trusting the key names, parse the active theme's palette and
// take the first candidate whose actual hue lands in the requested band. A
// theme that does define a usable green gets used; one that does not falls
// back to a fixed, hue-correct constant rather than showing something wrong.

// Hue bands in degrees, wrapping around 0. 90 = green, 35 = orange, 0 = red.
var BANDS = {
  green: [[78, 168]],
  orange: [[18, 58]],
  red: [[345, 360], [0, 14]]
}

function parsePalette(raw) {
  var colors = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (match) colors[match[1]] = match[2]
  }
  return colors
}

function toRgb(hex) {
  var n = parseInt(String(hex || "").replace("#", ""), 16)
  if (isNaN(n) || String(hex || "").length < 7) return null
  return { r: ((n >> 16) & 0xff) / 255, g: ((n >> 8) & 0xff) / 255, b: (n & 0xff) / 255 }
}

// Hue in degrees 0-360, or -1 for a near-grey colour where hue is meaningless.
function hueOf(rgb) {
  if (!rgb) return -1
  var max = Math.max(rgb.r, rgb.g, rgb.b)
  var min = Math.min(rgb.r, rgb.g, rgb.b)
  var d = max - min
  if (d < 0.04) return -1
  var h
  if (max === rgb.r) h = ((rgb.g - rgb.b) / d) % 6
  else if (max === rgb.g) h = (rgb.b - rgb.r) / d + 2
  else h = (rgb.r - rgb.g) / d + 4
  h = Math.round(h * 60)
  return h < 0 ? h + 360 : h
}

function inBand(hue, ranges) {
  if (hue < 0) return false
  for (var i = 0; i < ranges.length; i++) {
    if (hue >= ranges[i][0] && hue <= ranges[i][1]) return true
  }
  return false
}

// First candidate whose palette entry exists and actually reads as `band`.
function pick(palette, candidates, band, fallback) {
  var ranges = BANDS[band] || []
  for (var i = 0; i < candidates.length; i++) {
    var rgb = toRgb(palette[candidates[i]])
    if (rgb && inBand(hueOf(rgb), ranges)) return palette[candidates[i]]
  }
  return fallback
}
