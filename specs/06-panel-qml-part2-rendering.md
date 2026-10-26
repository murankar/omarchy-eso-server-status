# 06 — Panel.qml (Part 2: Rendering, States & Interaction)

## Purpose

This document covers the **visual rendering** details and **interaction logic** for `Panel.qml` (~795 lines total, Part 1 covered structure/Settings tab; this completes the panel spec with every visual element).

## Visual Layout of Open Panel

When open, the popout appears directly beneath (for above-bar panels) or above (depending on bar position) the invoking button. Fixed width: **320 px**.

### Top area: Status header + Tabs

```
┌──────────────────────────────────────┐
│   7 of 7 servers online              │  ← status line in accent colour, no dot
├──────────────────────────────────────┤  ← top divider (matching network panel style)
│ ┌─────────────────┬────────────────┐ │
│ │   Servers       │   Settings     │ │  ← tab indicators between dividers
│ └─────────────────┴────────────────┘ │
├──────────────────────────────────────┤  ← bottom divider for tabs
│                                      │
│  Server list content or settings...  │
│                                      │
│    ───────── site link               │  ← footer: "esoserverstatus.net" + icon
└──────────────────────────────────────┘
```

### Status Line (row below tab dividers)

A single line spanning the panel width showing `N of M servers online`:

- Count is drawn in **accent colour** from the theme palette
- No status dot next to heading — it is a count, not a server
- When paused: changes to `"Polling paused - N of 7 servers online"` (status text included)
- When stale: no count shown; panel header shows neutral colour

### Servers Tab: Grouped Server List Rendering Pattern

Each region group renders as:

**Region heading row:**
- Text label in **accent colour**, no status dot, no state text
- `NA`, `EU`, or `Public Test Server` (from `Servers.groupLabel()`)

**Server rows under a region:**
```
● PC           [toggle]     ← for active/online servers (● = coloured dot)
 ● PlayStation  [toggle]    ← dimmer dot when not first in group  
```

Where:
- **First dot in a group** is drawn with a slightly larger radius so it visually anchors the group
- Each subsequent row's server icon is a smaller dot, same colour as its state
- Right side of each row carries both the per-server mute toggle and the status text (if not muted/online)
- Muted rows show `muted` text in grey/dimmed style instead of any coloured status
- Row height is sufficient for 18-point text + padding

### Per-Row State-to-Colour Mapping Table

| Server state | Dot colour | Status text colour | Text label to the right of name |
|---|---|---|---|
| `online` | theme green (or fixed fallback) | same as dot or foreground | *none* (no extra text for "fine" state) |
| `offline` | theme red | red | *empty* (status implied by colour) |
| `ongoing issues` | amber (distinct from red) | amber | *empty* (colour signals severity) |
| `unknown` (poll failed) | grey/foreground-muted | muted | `"unknown"` |
| `muted` | grey (dimmed, 50% opacity) | grey/dimmed | `"muted"` |
| when service is paused | neutral foreground colour (never claims live state) | same as dot's colour but neutralized | `"paused"` |

**Amber vs red distinction:** A server with `ongoing issues` deliberately uses amber rather than red because the server *is* up — collapsing to red would overstate severity. There is no third colour for "unknown" — that falls back to grey (the muted palette state).

### Row Component Reference

Each row in the Repeater (for orderedServers) renders:

```qml
rowDelegate {  // qs.Commons or qs.Ui component
    width: parent.width - margin
    
    statusDot: Rectangle {
        radius: firstInGroup ? 5 : 3   // slightly larger dot to anchor group
        color: colourForState(rowState)
        visible: !isMuted && !isPaused && !hasNoServersMonitored
        
        // When paused, every server's dot takes the neutral bar foreground colour.
        // A green/red dot would imply a live status the service has withdrawn.
        color: root.status === "paused" ? Color.foreground : statusColor
    }
    
    nameLabel: Text {
        text: Servers.label(row.name)  // device name only, not region
        font.pixelSize: 18
        color: isMuted || servicePaused ? foregroundMutedColor : mainTextColor
        // Name always renders in plain text — never parsed for markup.
    }
    
    statusIcon: Text {
        // Small icon next to the name conveying current state more precisely:
        // "issues" badge or similar, only when relevant
        visible: row.state === "ongoing issues"
        ...
    }
    
    muteSwitch: ToggleSwitch {  // qs.Ui component
        checked: !isServerMuted(row.name)
        onToggled: toggleMute(row.name, !checked)
    }
}
```

### The `colourForState()` Function

Maps each server row's raw state value to the colour that should be used for its status dot and status indicators:

```javascript
function colourForState(stateName) {
    // Called per row inside the Repeater delegate for every tick.
    switch (stateName) {
        case "online":          return greenColor;   // computed from theme palette
        case "offline":         return redColor;     // computed from theme palette
        case "ongoing issues":  return orangeColor;  // amber (distinct from red)
        case "unknown":         return Color.foregroundMuted;
        default:                return Color.foregroundMuted;
    }
}

// These are the three colour helpers shared with BarWidget.qml.
// They call Theme.pick() against the loaded palette, falling back to fixed colours.
readonly property color greenColor: ...
readonly property color orangeColor: ...
readonly property color redColor: ...
```

### Settings Tab Rendering Details

Each setting row consists of three horizontal zones:

| Zone | Content | Alignment |
|---|---|---|
| Left (60%) | Label text (e.g., "Pause polling") | left-aligned, foreground colour |
| Middle (30%) | Value display (e.g., "ON", "300 s") — read-only preview of current value | right-aligned to the zone edge where the control starts |
| Right (10% or more) | Interactive control: ToggleSwitch, NumberField per setting type | right-aligned in cell |

**Number field specifics:** For healthyInterval and alertInterval settings:
- Displays as a numeric input box with +/- buttons beside it
- Minimum values are clamped by the component (same minimums that Service.qml enforces; see Settings spec for defaults)
- On focus loss, pending value is flushed to the service; no half-written states survive across tab switches
- A `NumberField` from qs.Ui handles keyboard navigation and validation internally

**All text in settings tab:** rendered in the active theme's foreground colour. Labels are descriptive ("Pause polling") rather than imperative ("Pause the poll").

### Per-Site Link Footer

At the bottom of the Servers tab, centered:

```
esoserverstatus.net  [→]
```

Where `[→]` is a right-arrow icon that opens https://esoserverstatus.net/ via `Quickshell.execDetached(["omarchy-launch-browser", ...])`. This mirrors the right-click behaviour on the bar entry so no navigation requires reaching the widget itself.

### Panel Close / Outside-Click Behaviour

The panel closes via three mechanisms:

1. **Outside click:** Clicking anywhere outside the panel bounds (or the anchored window's content region)
2. **Escape key:** Standard dismissible-panel behaviour (`onEscapeKeyPressed`)  
3. **Shell-level dismissal:** Any standard Quickshell mechanism for closing popout panels — no custom implementation needed beyond the `opened` state being respected

The `KeyboardPanel` base component from `qs.Ui` handles the modal backdrop and click-outside detection automatically; the plugin simply toggles `opened` which controls visibility through the base class.

### Popout Open Positioning (continued)

The panel uses `anchorItem` to position itself relative to the BarIconButton that opened it:

```qml
x: root.barX + anchorX   // horizontal centre of button or left-align — depends on bar orientation and screen edge padding
y: isAboveBar ? -root.height : barHeight  // below-bar vs above-bar panels handled dynamically
// If panel would extend past screen bounds after opening, flip position (below ↔ above).
```

When the bar itself is at a screen edge the positioning accounts for available viewport dimensions. No scrollbars or clipping of the panel occurs under normal bar positions; if the panel extends beyond screen edges, it snaps to fit within viewable area.

### Panel State After First Poll + What It Means

Before any poll lands:
- Panel may open but shows a `Loading...` placeholder during initial connection (or is hidden entirely depending on timing)
  
After first successful poll:
- All server rows populated with live data from eso-site's JSON API
- Status line shows `N of M servers online` in accent colour
- Rows coloured per the state mapping table above

---

## Source File Reference

The complete literal source for Panel.qml is at `/home/uri/Projects/plugins/omarchy/omarchy-eso-server-status/Panel.qml`. Part 1 covered structure/Settings tab (86 KB reference); this Part 2 covers:
- Per-server row rendering and colour mapping
- Settings tab controls in detail  
- Panel open/close/popout positioning
- State line header logic

---

*Source notes: AddPanel.md (full UI specs), CodeReview.md (panel visual corrections), Fixes.md (mute switch fixes)*
