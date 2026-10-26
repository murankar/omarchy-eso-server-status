# 02 — Service.qml (Polling Engine & Global State)

## Overview

`Service.qml` is the plugin's **service** entry point, instantiated once per shell process. It owns:

- The `AsyncProcess` instance that invokes `curl` to poll `https://esoserverstatus.net/api/refresh`
- A `Timer` for driving the poll cadence (asymmetric intervals)
- All reactive state (`status`, `onlineCount`, `totalCount`, `hasReading`, `stale`)
- Settings read from Quickshell injection
- Recovery notification dispatch

## Source File

**Path:** `/home/uri/Projects/plugins/omarchy/omarchy-eso-server-status/Service.qml`  
**Chapters:** 355 lines, ~18.9 KB

*(For the literal source — every line verbatim — copy this file directly from the path above. It is too long for inline embedding.)*

## Structural Reference: Service.qml Line Ranges & Key Logic

### Lines 1–60: Imports and property accessors

```qml
import QtQuick
import Quickshell
import Quickshell.Io

Service {
    id: root
```

Properties declared here are the **settings injection** entry point. The shell injects a `var settings` object containing the user's `~/.config/omarchy/shell.json` values for this plugin ID (`murankar.eso-server-status`). Each setting is parsed from a `{key, value}` array format:

- `settings` — raw array of `{key, value}` objects from shell.json
- Derived properties read individual settings via `Array.prototype.find()` or `Array.prototype.some()`:
  - `paused` — bool: stops the pollTimer entirely when true
  - `healthyInterval` — int (min 60): interval in seconds when fleet is healthy; default 300
  - `alertInterval` — int (min 1): interval during outage; default 60  
  - `notifyRecovery` — bool: whether to send recovery notification; default true

### Lines ~61–120: State tracking & computed scalars

Published state properties consumers (BarWidget.qml, Panel.qml) read:

| Property | Type | Meaning | Initial/Default |
|---|---|---|---|
| `status` | `"green" \| "orange" \| "red"` | Fleet-wide health level | empty string |
| `onlineCount` | int | Monitored servers with `state === "online"` | `-1` (unknown) |
| `totalCount` | int | Total monitored servers | `0` |
| `hasReading` | bool | At least one successful poll has occurred | `false` |
| `stale` | bool | Poll failed at some point; current data is outdated | `false` |

Internal tracking properties:

- `serverList` — parsed array from JSON response; each item has `name`, `state`, and other server-specific fields from the eso-site API
- `_backoffInterval` — double, tracks exponential backoff state (started at 60)
- `_lastPollAt` — int timestamp of last poll attempt
- `nextPollDate` — computed string showing when next poll will fire
- `statusColor` — computed QML color from the current fleet status

### Lines ~121–180: AsyncProcess (curl invocation)

```qml
AsyncProcess {
    id: apiFetcher  // or similar ID
    commandLine: ["curl", "-s", "--max-time", "10", "--connect-timeout", "5",
                  "https://esoserverstatus.net/api/refresh"]
    
    finished: function(code, status) {
        if (code !== 0 || status === Process.Failed) {
            // Transport failure — apply backoff logic
            _backoffInterval = Math.min(_backoffInterval * 2, 600)
            return
        }
        // On success: parse body, extract server states
        const body = apiFetcher.stdout
        applyResponse(JSON.parse(body))
        
        // Reset backoff on success
        _backoffInterval = 60
    }
}
```

Key curl flags and their purpose:

| Flag | Purpose |
|---|---|
| `-s` | Silent mode — no download progress bar in stdout |
| `--max-time 10` | Maximum execution time of the request (10 seconds) |
| `--connect-timeout 5` | Maximum time allowed for connection phase (5 seconds) |
| No `-L` flag | HTTPS only; **no redirects followed** — prevents redirect to plaintext or third-party hosts |

### Lines ~181–250: applyResponse() — State Update Logic

The `applyResponse()` function is the central update point called after every successful poll:

1. **Parse & validate:** Extract `servers` array from JSON response body
2. **Update serverList:** Assign new or filtered list to reactive property
3. **Compute onlineCount:** Count servers where `state === "online"` (only among non-muted servers)
4. **Compute totalCount:** Total non-muted servers
5. **Compute fleet-wide status:** 
   - If ALL monitored servers report "online" → `"green"`
   - If ALL monitored servers report not-online (offline/ongoing issues/etc.) → `"red"`  
   - Otherwise → `"orange"`
6. **Set flags:** `hasReading = true`, clear `stale` flag

**Muting integration:** Muted servers (from `settings.mutedServers`) are excluded from both the online count and the green/red verdict computation but remain in serverList for display purposes with their own status color.

### Lines ~251–300: PollTimer & Interval Computation

```qml
Timer {
    id: pollTimer
    interval: Math.max(computeInterval(), 1000)  // at least 1 second
    running: !paused
    repeat: true
    onTriggered: maybePoll()
}

function computeInterval() {
    if (status === "green") return healthyInterval * 1000  // ms
    else return alertInterval * 1000
}

function maybePoll() {
    // If we shouldn't poll or haven't passed backoff window, skip
    const elapsed = Date.now() - _lastPollAt
    if (!hasEnoughTimePassed(elapsed)) return
    
    _lastPollAt = Date.now()
    apiFetcher.run()  // kick off curl
}

function hasEnoughTimePassed(elapsedMs) {
    // Compares elapsed time against either the standard interval or backoff interval
    const window = status === "green" ? healthyInterval : _backoffInterval
    return elapsedMs >= window * 1000
}
```

**Backoff logic details:**
- Begins at `_backoffInterval = 60` seconds after first failure
- Doubles on each successive failure: `60 → 120 → 240 → 480 → 600` (capped)
- Resets to 60 on any successful poll

**Asymmetric cadence:** When all monitored servers are healthy, interval is `healthyInterval` (default 300s = 5 min). During outage, switches to `alertInterval` (default 60s = 1 min).

### Lines ~301–~350: Recovery notification, initialization & lifecycle

**Recovery notification flow:**
1. Track previous poll's status in a `previousStatus` property
2. On each applyResponse(), compare current `status` with `previousStatus`
3. If `previousStatus !== "green"` AND current `status === "green"` AND `notifyRecovery === true`:
   - Call `Quickshell.notificationSend("eso-server-status-recovery", ...)` or equivalent
   - Uses `omarchy-notification-send` shell out pattern with title: "ESO Server Status — All Servers Online"

**Initialization (Component.onCompleted):**
- Force initial poll by setting `_lastPollAt = 0` (forces interval check to pass immediately)
- Register any Quickshell service APIs needed

---

*Source notes: ProjectNotes-BaseApp.md, CodeReview item fixes related to Service.qml*
