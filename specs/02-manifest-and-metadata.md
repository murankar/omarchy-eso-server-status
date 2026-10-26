# manifest.json — Plugin Metadata & Settings Schema

## Location
`manifest.json` at the plugin root.

## Complete File

```json
{
  "schemaVersion": 1,
  "id": "murankar.eso-server-status",
  "name": "ESO Server Status",
  "version": "1.4.1",
  "author": "Matthias Urankar",
  "description": "Elder Scrolls Online server status indicator with shared, outage-aware polling",
  "kinds": [
    "service",
    "bar-widget"
  ],
  "entryPoints": {
    "service": "Service.qml",
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "ESO Server Status",
    "description": "Green when every ESO server is online, red when all are offline, orange otherwise",
    "category": "Info",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": {
      "paused": false,
      "healthyInterval": 300,
      "alertInterval": 60,
      "notifyRecovery": true,
      "detail": false,
      "mutedServers": []
    },
    "schema": [
      {
        "key": "paused",
        "type": "boolean",
        "label": "Pause polling (resume forces an immediate refresh)"
      },
      {
        "key": "healthyInterval",
        "type": "number",
        "label": "Poll interval when all servers are online (seconds)"
      },
      {
        "key": "alertInterval",
        "type": "number",
        "label": "Poll interval during an outage (seconds)"
      },
      {
        "key": "notifyRecovery",
        "type": "boolean",
        "label": "Notify when all servers come back online"
      },
      {
        "key": "detail",
        "type": "boolean",
        "label": "Append online count to tooltip"
      }
    ]
  },
  "keepLoaded": true
}
```

## Key Decisions (from code review + fixes notes)

### `allowMultiple: false`
The plugin prevents multiple instances. This matches its design: only one Service should exist per shell process, and the bar-widget itself issues no network calls — all polling is handled by the service. Multiple widgets would multiply visual output without multiplying data collection.

### `keepLoaded: true`
**Critical:** Ensures the service object survives hot-reload of the bar widget. Without this, editing/hot-reloading the bar component could orphan the live service. Trade-off: changes to the service require `omarchy restart shell` instead of auto-reload — but that is documented in README.md under Development.

### Settings default values
| Key | Default | Constraints & Effects |
|---|---|---|
| `paused` | `false` | Pause stops polling entirely (cost = 0 requests). Resume forces immediate refresh via `lastPollAt = 0`. |
| `healthyInterval` | `300` seconds | Minimum clamped in Service.qml; no dynamic minimum for healthy state. |
| `alertInterval` | `60` seconds | Minimum clamped in Service.qml; incident cadence during outage. |
| `notifyRecovery` | `true` | Sends a desktop notification when all monitored servers return online after an incident. |
| `detail` | `false` | When true, tooltip shows `ESO Server Status - N/7 online`. Controlled from Settings tab in the panel. |
| `mutedServers` | `[]` (array of strings) | Per-server mute deny-list stored in `~/.config/omarchy/shell.json`. Servers listed here are dropped from both the overall green/red verdict and the `N/M` count. The list uses exact site payload keys (`PC-NA`, `PS4-EU`, etc.). |

### Version note
The manifest version is **1.4.1**, tracking the current state after all fixes, UI corrections, panel additions, and optimizations referenced in the ProjectNotes files. This matches the git-tagged release.

---

*Source notes: ProjectNotes-BaseApp.md (schema evolution), ProjectNotes-Fixes.md (schema fixups), ProjectNotes-CodeReview.md (allowMultiple correction)*
