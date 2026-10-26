# 05 — Panel.qml (Part 1: Structure, Mounting & Settings Tab)

## Purpose

`Panel.qml` is the **popout panel** that appears beneath the bar glyph when the user left-clicks. It has two tabs:

- **Servers tab:** per-server status list with individual mute toggles + site link
- **Settings tab:** five poll-control settings (pause, intervals, notification, detail)

The panel receives the live `service` object via injection from BarWidget.qml — it is a pure view, never performs its own network requests.

## Source File

**Path:** `/home/uri/Projects/plugins/omarchy/omarchy-eso-server-status/Panel.qml`  
**Size:** ~37.7 KB | **~795 lines** (split across two spec files)

---

## Part 1: Structure & Settings Tab Reference

### Imports

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Theme.js" as Theme
import "Servers.js" as Servers
```

All UI components come from `qs.Commons` and `qs.Ui` (Omarchy's shared Quickshell component library). The panel is a KeyboardPanel-derived window anchored to the bar button.

### Injected Properties (from BarWidget.qml via injectPanel())

| Property | Type | Source |
|---|---|---|
| `bar` | Quickshell.Bar | `root.bar` from BarWidget |
| `settings` | array of `{key, value}` | Quickshell user settings (shell.json) |
| `service` | Service object | Shared service registry (`serviceFor`) |
| `anchorItem` | Item | The BarIconButton in the bar (panel positioning anchor) |
| `hostWidget` | QtObject | The root item of BarWidget.qml |
| `moduleName` | string | `"murankar.eso-server-status"` (for settings scoping) |

### Panel Root & Lifecycle

```qml
KeyboardPanel {
    id: root
    
    // Popout positioning beneath the bar button.
    width: 320    // panel fixed width
    x: anchorItem.x          // align left with bar button
    y: anchorItem.height     // sit just below the bar surface
    
    // Panel state tracking
    property bool opened: false
    readonly property bool popoutSwitchClosing: false
    
    function open() { opened = true }
    function close() { opened = false }
    function toggle() { opened = !opened }
    
    // Closing when mouse moves outside panel bounds (popout behavior)
    onVisibleChanged: if (!visible) opened = false
}
```

### Tab System

The panel uses a **two-tab layout** between dividers, drawn identically to the DNS provider row in the network panel for visual consistency.

```qml
// Tab state
property int activeTab: 0  // 0 = Servers, 1 = Settings

// Tabs between dividers:
Rectangle { height: 2; anchors.fill: parent; color: dividerColor } // top divider

Repeater {
    model: ["Servers", "Settings"]
    Rectangle {
        width: parent.width / 2
        height: 36
        background: activeTab === index ? accentColor : foregroundMutedColor
        text: modelData
        onClicked: activeTab = index
    }
}

Rectangle { height: 2; ... } // bottom divider
```

### Tab 0: Servers List Structure (structural overview)

The **Servers** tab renders the fleet of ESO servers grouped by region. Each server row is a delegate containing:

1. Status dot (`Rectangle` with colour based on state or muted/stale/paused)
2. Server name label (`Text`, plain text only — never rendered as markup)
3. Per-server mute toggle (`ToggleSwitch`)

The list uses a **decoration-sort-undecoration** pattern via `orderedServers` binding:

```qml
readonly property var orderedServers: {
    // Take service.serverRows, decorate with display name + region rank,
    // sort by region rank then display name, undecorate back to row shape.
    let tmp = serverRows.map(function(row) {
        return {
            row: row,                    // original {name, state} pair
            label: Servers.label(row.name),  // device label (e.g., "PC", "PlayStation")
            rank: Servers.groupRank(Servers.region(row.name)) // NA=0, EU=1, PTS=2, others=3+
        }
    })
    tmp.sort(function(a, b) {
        let byGroup = a.rank - b.rank
        if (byGroup !== 0) return byGroup
        return a.label < b.label ? -1 : (a.label > b.label ? 1 : 0)
    })
    return tmp.map(function(item) { return item.row })
}
```

**Region grouping logic:** The `ServerList` uses a `Flow` or manual `y` offset tracking to insert region heading rows between groups. Heading text is styled with the accent colour, no status dot, and carries no state text (it's a heading, not a server):

```qml
readonly property var groupedServers: {
    // Organize orderedServers into [{regionLabel, servers: [...]}] arrays
    let groups = []
    let currentRegion = null
    orderedServers.forEach(function(row) {
        let r = Servers.region(row.name)
        if (r !== "" && r !== currentRegion) {
            currentRegion = r
            groups.push({ label: Servers.groupLabel(r), servers: [row] })
        } else if (currentRegion === null || r === "") {
            groups.push({ label: "Public Test Server", servers: [row] })
        } else {
            groups[groups.length - 1].servers.push(row)
        }
    })
    return groups
}
```

**Per-row mute state:** For each row, determine if its site-key (e.g., `PC-NA`) is in the muted list:

```qml
function isServerMuted(serverName) {
    var list = storedMutedList()  // read from service.settings or fallback to root.settings
    for (var i = 0; i < list.length; i++) {
        if (list[i] === serverName) return true
    }
    return false
}

function storedMutedList() {
    var list = service && "settings" in service ? service.settings : null
    if (!list || !Array.isArray(list)) list = root.settings
    // filter non-string entries (defensive against corrupt shell.json)
    for (var i = 0, result = []; i < list.length; i++) {
        if (typeof list[i] === "string") result.push(list[i])
    }
    return result
}
```

**Per-row state rendering:** Each row shows its own colour and state text:

| State | Colour | Text shown next to name |
|---|---|---|
| `online` | theme's green (or fixed fallback) | blank (no extra text) |
| `offline` | theme's red | none |
| `ongoing issues` | amber, distinct from red | "issues" or no text — just the colour difference |
| `unknown` (poll failed) | dimmed/foreground-muted | "unknown" |
| `muted` | dimmed | "muted" |
| `paused` reading | neutral foreground colour | "paused" (dot and status match server name colour when live, but go neutral when paused) |

**Amber vs red distinction:** Servers reporting `ongoing issues` use **amber** deliberately separate from the red used by truly offline servers — a server that is reachable but impaired must not collapse into the red severity.

### Tab 1: Settings Structure (full list)

Five settings, each rendered identically to other Omarchy panel's settings rows: toggle switches or number fields within styled rows with label on left, control(s) on right, all text in the theme's foreground colour.

#### Setting 1: Pause Polling (toggle switch)

Label: "Pause polling"
Control: `ToggleSwitch { checked: root.settings["paused"]; onToggled: updateSettings("paused", value) }`
- When toggled **on**: pauses the service layer — no more curl requests, glyph goes neutral foreground colour, tooltip changes to "polling paused"
- When toggled **off**: immediately resets `service.lastPollAt = 0` triggering a fresh poll as soon as possible

#### Setting 2: Healthy Poll Interval (number field)

Label prefix: "Healthy poll:" with unit "(s)" suffix
Control: `NumberField { value: root.settings["healthyInterval"]; min: <clamp to minimum>; onValueChanged: updateSettings("healthyInterval", value) }`
- Bounded below by the same minimum the service clamps — cannot enter a value silently overridden by the backend

#### Setting 3: Incident Poll Interval (number field)

Label prefix: "Incident poll:" with unit "(s)" suffix  
Control: `NumberField { value: root.settings["alertInterval"]; min: <clamp>; onValueChanged: updateSettings("alertInterval", value) }`
- Same minimum bounds. A new interval takes effect immediately on the next poll tick; no restart required.

#### Setting 4: Recovery Notification (toggle switch)

Label: "Notify on recovery"
Control: `ToggleSwitch { checked: root.settings["notifyRecovery"]; onToggled: updateSettings("notifyRecovery", value) }`
- When enabled, the service sends a desktop notification via `omarchy-notification-send` when *all previously-unhealthy monitored servers* return online. Fires once per recovery event, not on every healthy poll.

#### Setting 5: Count in Tooltip (toggle switch)

Label: "Count in tooltip"
Control: `ToggleSwitch { checked: root.settings["detail"]; onToggled: updateSettings("detail", value) }`
- When disabled (default): tooltip shows only "ESO Server Status"
- When enabled: tooltip appends " - N/M online" e.g., "ESO Server Status - 6/7 online"

### Settings Update Path

Each setting writes back to the QML settings system via a helper:

```qml
function updateSettings(key, value) {
    // Find existing or create new entry for this key within root.settings
    var found = false
    for (var i = 0; i < root.settings.length; i++) {
        if (root.settings[i].key === key) {
            root.settings[i].value = value
            found = true
            break
        }
    }
    if (!found) {
        root.settings.push({ key: key, value: value })
    }
    // Sync up to service immediately so the backend sees fresh settings
    if (root.service && "settings" in root.service) {
        root.service.settings = root.settings
    }
}

function removeMutedServer(keyName) {
    // Remove from service.settings.mutedServers array: locate by key and splice out
    if (!root.service || !("settings" in root.service)) return
    var settings = root.service.settings
    for (var i = 0; i < settings.length; i++) {
        if (settings[i].key === "mutedServers") {
            // Remove keyName from the array value using Array.filter or splice
            settings[i].value = settings[i].value.filter(v => v !== keyName)
            break
        }
    }
}
```

---

*Source notes: ProjectNotes-BaseApp.md (initial panel design), AddPanel.md (full panel specs), CodeReview.md (panel corrections), Fixes.md (mute list fixes)*
