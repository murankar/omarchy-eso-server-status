// Server naming and grouping for the panel's server list.
//
// The site keys its payload device-first -- PC-EU, PS4-NA, XBOX-EU -- which
// reads as a device with a region stuck on the end rather than as a region
// hosting a device. The panel groups by region instead: a heading names the
// region once, and the rows under it name only the device.
//
// The payload key is never rewritten. `mutedServers` is a list of exactly
// these keys, so a label is carried beside the key and never in place of it:
// changing what a row *shows* must not change what an existing setting
// *means*. A user who muted PC-EU before this existed keeps a muted PC-EU.
//
// The public test server is the deliberate exception. It is not a region, so
// it keeps the name the site gives it and gets a group of its own at the
// bottom.

// Regions with a fixed position in the list. Anything else sorts after the
// test server rather than being dropped: a console the site adds later should
// still appear, just below the fleet we know about.
var REGIONS = ["NA", "EU"]
var TEST_REGION = "PTS"

// Names as the panel shows them. A device missing from this table keeps its own
// name, so an unknown console gets a row rather than a blank one.
var DEVICES = { "PS4": "PlayStation" }

// Split on the *last* hyphen, so a device name containing one does not throw
// the region off. Returns null for a name with no usable region part at all.
function split(name) {
  var text = String(name === undefined || name === null ? "" : name)
  var cut = text.lastIndexOf("-")
  if (cut <= 0 || cut === text.length - 1) return null
  return { device: text.slice(0, cut), region: text.slice(cut + 1) }
}

function deviceLabel(device) {
  return DEVICES[String(device).toUpperCase()] || device
}

function isTest(region) {
  return region === TEST_REGION
}

// The display name: the device alone, because the region is already the
// heading it sits under. Repeating it on every row in the group would say the
// same thing seven times. The test server is returned untouched, by name, and
// keeps its own prefix -- it is not in a region group.
function label(name) {
  var parts = split(name)
  if (!parts || isTest(parts.region)) return String(name)
  return deviceLabel(parts.device)
}

// The region a server groups under, or "" when the name carries none.
function region(name) {
  var parts = split(name)
  return parts ? parts.region : ""
}

// The heading shown above a group.
function groupLabel(regionText) {
  if (isTest(regionText)) return "Public Test Server"
  return String(regionText)
}

// NA, then EU, then the test server, then whatever the site adds later.
function groupRank(regionText) {
  var i = REGIONS.indexOf(regionText)
  if (i !== -1) return i
  return isTest(regionText) ? REGIONS.length : REGIONS.length + 1
}

// Region first, then display name, so the order is the same whether you read
// it off the group or off the rows.
function compare(a, b) {
  var ra = region(a.name)
  var rb = region(b.name)
  var byGroup = groupRank(ra) - groupRank(rb)
  if (byGroup !== 0) return byGroup
  var la = String(label(a.name))
  var lb = String(label(b.name))
  if (la < lb) return -1
  if (la > lb) return 1
  return 0
}