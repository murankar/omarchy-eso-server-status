# 07 — Shared Logic (Theme.js + Servers.js)

## Theme.js — Hue-Aware Colour Selection

### Purpose

`Theme.js` provides **hue-aware colour picking** from an Omarchy theme's active palette file. The key insight: named palette entries like `green`, `red`, `orange` are *not* reliably semantic across themes. *lumon* puts a blue under `green`; *lupine* puts purple under `green`; *white* puts grey under `green`. This module parses the **actual hex values** and picks the first whose hue falls in the requested band.

### Source File

**Path:** `/home/uri/Projects/plugins/omarchy/omarchy-eso-server-status/Theme.js`
**Size:** 2,377 chars | **68 lines**

```javascript
// Theme.js — ESO Server Status plugin
// Hue-aware colour picking from the active Omarchy theme palette.
import QtQuick as Module

var BANDS = {
    green: [[78, 168]],           // hue band for "green" (degrees)
    orange: [[18, 58]],           // hue band for "orange" (degrees)
    red: [[345, 360], [0, 14]]   // hue band for "red" — wraps around 0°
}

// Parse a colors.toml file's text content into a plain {name: hex} map.
// Looks for lines matching: <KEY> = <"HEX"> or <KEY> = HEX
function parsePalette(raw) {
    var colors = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
        if (match) colors[match[1]] = match[2]
    }
    return colors
}

// Convert a hex string like "#26a269" to {r: 0.15, g: 0.64, b: 0.41} floats (0-1).
function toRgb(hex) {
    var n = parseInt(String(hex || "").replace("#", ""), 16)
    if (isNaN(n) || String(hex || "").length < 7) return null
    return { r: ((n >> 16) & 0xff) / 255, g: ((n >> 8) & 0xff) / 255, b: (n & 0xff) / 255 }
}

// Extract the hue in degrees (0-360) from an RGB object. Returns -1 for near-grey.
function hueOf(rgb) {
    if (!rgb) return -1
    var max = Math.max(rgb.r, rgb.g, rgb.b)
    var min = Math.min(rgb.r, rgb.g, rgb.b)
    var d = max - min
    if (d < 0.04) return -1  // near-grey: hue meaningless
    
    var h
    if (max === rgb.r) h = ((rgb.g - rgb.b) / d) % 6
    else if (max === rgb.g) h = (rgb.b - rgb.r) / d + 2
    else h = (rgb.r - rgb.g) / d + 4
    h = Math.round(h * 60)
    return h < 0 ? h + 360 : h
}

// Check if a hue degree falls within one of the bands for `range`.
function inBand(hue, ranges) {
    if (hue < 0) return false
    for (var i = 0; i < ranges.length; i++) {
        if (hue >= ranges[i][0] && hue <= ranges[i][1]) return true
    }
    return false
}

// Pick the first palette entry that both exists AND whose actual hue falls in `band`.
// Falls back to `fallback` hex literal if no entry qualifies.
// This is the main public function called by BarWidget.qml and Panel.qml.
function pick(palette, candidates, band, fallback) {
    var ranges = BANDS[band] || []
    for (var i = 0; i < candidates.length; i++) {
        var rgb = toRgb(palette[candidates[i]])
        if (rgb && inBand(hueOf(rgb), ranges)) return palette[candidates[i]]
    }
    return fallback  // e.g. "#26a269" for green, "#e69138" for orange, "#dc3545" for red
}

// Exported function list (for any callers):
// parsePalette(raw)    → {name: hex} map
// pick(palette, candidates, band, fallback) → hex string
```

### Hue Band Bands Used

| Colour | Hue bands (degrees) | Description |
|---|---|---|
| Green | `[78, 168]` | Covers all greens from yellow-green to deep teal-green |
| Orange | `[18, 58]` | Amber through golden orange through standard orange |
| Red | `[345, 360] ∪ [0, 14]` | Wraps around zero: crimson/pink-red through pure red through orange-red |

### Candidate Lists (in priority order)

**Green candidates:** `green`, `bright_green`, `color2`, `color10`, `color42`  
Fallback: `"#26a269"` (true green)

**Orange candidates:** `orange`, `bright_orange`, `accent`, `yellow`, `bright_yellow`, `color3`, `color11`, `color214`  
Fallback: `"#e69138"` (amber/orange)

**Red candidates:** `red`, `bright_red`, `color1`, `color9`, `color88`  
Fallback: `"#dc3545"` (bootstrap/danger red)

### Why This Was Needed

Several stock Omarchy themes map non-semantic names to their key positions:
- *lumon* theme: `green` = blue-ish color → would render as blue, not green
- *lupine* theme: `green` = purple → would render as purple
- *white* theme: `green` = grey → would be invisible on light backgrounds

Parsing actual hex values and testing hue bands produces **correct semantics regardless of what the theme names its entries**. Tested across all 21 stock Omarchy themes; every one yields correct green, orange, and red.

### Called From

- `BarWidget.qml`: `Theme.parsePalette(paletteFile.text())` to get palette; then `Theme.pick()` calls for each colour
- `Panel.qml`: Same pattern — parses the active theme's palette via a shared FileView watching `colors.toml`, uses `Theme.pick()` for status colours

---

## Servers.js — Server Name Parsing & Region Grouping

### Purpose

`Servers.js` provides **display name** and **region grouping** logic for the panel server list. The ESO api keys servers device-first (e.g., `PC-NA`, `PS4-EU`, `XBOX-NA`) which reads as device with region stuck on; the panel groups by *region* instead so each region gets one heading and devices underneath repeat only the device name.

### Source File

**Path:** `/home/uri/Projects/plugins/omarchy/omarchy-eso-server-status/Servers.js`
**Size:** 4,249 chars | **106 lines**

```javascript
// Servers.js — ESO Server Status plugin
// Parsing: split each server name into device + region using the LAST hyphen.
// Grouping: group by region (NA first, EU, then PTS, anything else at bottom).
// Display names: map device codes to display-friendly strings; sanitize via regex.

var REGIONS = ["NA", "EU"]
var TEST_REGION = "PTS"

// Characters allowed in display names. Everything else stripped from the label.
// A strict set applied only to labels (not payload keys) so junk can't reach UI.
var UNSAFE = /[^A-Za-z0-9 _.-]/g
var UNNAMED = "Unknown"

var DEVICES = { "PS4": "PlayStation" }

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

// Reduce untrusted remote text to label-safe alphabet only.
function plain(value) {
    var text = String(value === undefined || value === null ? "" : value)
    var cleaned = text.replace(UNSAFE, "")
    return cleaned === "" ? UNNAMED : cleaned
}

// Display name: device only (region is the heading; no repetition).
function label(name) {
    var parts = split(name)
    if (!parts || isTest(parts.region)) return plain(name)
    return plain(deviceLabel(parts.device))
}

// Region string for grouping purposes.
function region(name) {
    var parts = split(name)
    return parts ? plain(parts.region) : ""
}

// Group label: "NA", "EU", or "Public Test Server".
function groupLabel(regionText) {
    if (isTest(regionText)) return "Public Test Server"
    return plain(regionText)
}

// Sort order: NA first, EU second, then test server last among known regions.
function groupRank(regionText) {
    var i = REGIONS.indexOf(regionText)
    if (i !== -1) return i
    // Unknown/special region goes after all known ones:
    return isTest(regionText) ? REGIONS.length : REGIONS.length + 1
}

// Compare function for sorting. Primary: group rank; secondary: label sort.
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
```

### Server Naming & Grouping — Concrete Examples

| Site key | deviceLabel() | label() output | region() | Used in... |
|---|---|---|---|---|
| `PC-NA` | `"PC"` | `"PC"` | `"NA"` | servers.js → Panel group heading NA → rows: PC |
| `PS4-EU` | `"PlayStation"` | `"PlayStation"` | `"EU"` | Panel group EU → display rows as "PlayStation" |
| `XBOX-NA` | `"XBOX"` | `"XBOX"` | `"NA"` | Same NA group as PC-NA |
| `PC-PTS` | `"PC-P TS"` | `"PC-PTS"` | `"PTS"` | Special: rendered under "Public Test Server" heading, name unchanged |

### Grouping & Sort Order

```
1. NA group        ← REGIONS index 0
   PC               ← label(PC-NA)
   PlayStation      ← label(PS4-EU)
   XBOX             ← label(XBOX-NA)
2. EU group        ← REGIONS index 1
   PS4              ← label(e.g., unknown-console-EU) → plain("PS4") via device mapping fallback
3. Public Test     ← REGIONS.length (3)
   PC-PTS           ← name unchanged for test server
4. Any new zones    ← REGIONS.length + 1 and beyond
```

### Security Model

The `UNSAFE` regex `/[^A-Za-z0-9 _.-]/g` strips all non-safe characters from display names. This is a **defensive boundary** against potentially malicious or broken API responses:

- Applied to **labels only** — the payload key itself (e.g., `"PC-NA"`) is *never rewritten* so `mutedServers` entries keep matching the keys they were stored against
- If stripped text produces empty string, falls back to UNNAMED (`"Unknown"` rather than blank)
- Prevents a compromised API response from injecting HTML/Markdown/CSS into server labels

### Key Design Decisions

1. **Split on last hyphen** — `lastIndexOf("-")` handles device names containing a hyphen correctly (e.g., `PC-XBOX-EU` would yield device `PC-XBOX`, region `EU`)
2. **Test server is not a region** — kept under its own heading `"Public Test Server"` at the bottom of the list, name unchanged from site's key
3. **Device-to-label map** extensible via adding to `DEVICES` object without changing logic

---

### Integration: How Theme.js and Servers.js Work Together

In Panel.qml:
```qml
// In Panel.qml, both modules are imported at the top:
import "Theme.js" as Theme
import "Servers.js" as Servers

// Usage - servers list decoration-sort-undecoration:
readOnly property var orderedServers: {
    var tmp = serverRows.map(function(row) {
        return {
            row: row,
            label: Servers.label(row.name),       // device name only (NO region repetition)
            rank: Servers.groupRank(Servers.region(row.name))  // NA=0, EU=1, PTS=2...
        }
    })
    tmp.sort(function(a, b) {
        var byGroup = a.rank - b.rank
        if (byGroup !== 0) return byGroup
        if (a.label < b.label) return -1
        if (a.label > b.label) return 1
        return 0
    })
    return tmp.map(function(item) { return item.row })
}

// Usage - colour for a server row's dot:
function colourForState(stateName) {
    switch (stateName) {
        case "online":          return Theme.pick(palette, ...GREEN_CANDIDATES, "green", "#26a269")
        case "offline":         return Theme.pick(palette, ...RED_CANDIDATES, "red", "#dc3545")
        default:                return Theme.pick(palette, ...ORANGE_CANDIDATES, "orange", "#e69138")
    }
}
```

In BarWidget.qml (same pattern for the bar glyph colour):
```qml
readonly property color greenColor: Theme.pick(
    palette, ["green","bright_green","color2","color10","color42"], 
    "green", "#26a269")
```

Both components carry their own `FileView` watching the same `colors.toml` (this is intentional per optimization review — consolidating watchers would need an injection path and touch load order for a small file).

---

*Source notes: ProjectNotes-BaseApp.md, ProjectNotes-CodeReview.md (region grouping & display names), Optimization notes (sort key precomputation recommendations)*
