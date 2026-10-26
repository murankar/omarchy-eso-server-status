# 01 — Project Overview & Architecture

## ESO Server Status Plugin

An Omarchy (Quickshell-based) status-bar widget that watches `esoserverstatus.net` and colours a single glyph according to the health of the Elder Scrolls Online server fleet.

### Status Mapping

| State | Colour | Meaning |
|---|---|---|
| Green | all servers online | nothing to do |
| Orange | any mix | partial outage, or a server flagged "ongoing issues" |
| Red | all servers offline | total outage |
| Neutral (foreground) | last reading stale | endpoint unreachable — never claims "all clear" |

### Core Files & Their Roles

```
manifest.json         → plugin metadata, settings schema, entry points
Service.qml           → one per shell process; owns Process, Timer, all state & network
BarWidget.qml        → per bar surface; reads published state, renders icon, handles input
Panel.qml            → per bar surface; popout server list + settings tabs (~795 lines)
Servers.js           → display names, region grouping, sort order for the server list
Theme.js             → hue-aware colour selection from active theme's palette
README.md            → user-facing documentation (install, usage, architecture)
Patch-Notes.md       → version history
LICENSE              → MIT
preview.png          → screenshot for manifest listing
docs/                → additional screenshots
```

### Key Architectural Decision: Service / Widget Split

The plugin is split into **service** and **bar-widget** kinds so that one polling process is shared across *all* monitor instances. The widget can be instantiated many times (one per bar surface), while the service cannot — this keeps request count **independent of monitor count**. 

- `Service.qml` is declared `keepLoaded: true` in manifest.json so editing/hot-reloading the bar widget does not orphan the live Service object.
- Trade-off: changes to the service itself require `omarchy restart shell` rather than auto-reload (documented in README.md).

### Install Path

```
~/.config/omarchy/plugins/murankar.eso-server-status/   ← installed files
```

### Settings & Persistence

All five settings are stored in the user's `~/.config/omarchy/shell.json`:

| Key | Type | Default | Effect |
|---|---|---|---|
| `paused` | boolean | false | Stop polling entirely; resume forces immediate refresh |
| `healthyInterval` | number | 300s | Poll interval when all monitored servers online |
| `alertInterval` | number | 60s | Poll interval during outage |
| `notifyRecovery` | boolean | true | Desktop notification when all recover |
| `detail` | boolean | false | Append online count to tooltip (e.g., "6/7 online") |

A new interval takes effect on the next poll; nothing needs restarting. Numeric fields are clamped to minimums by Service.qml, so invalid user input is silently corrected.

### Request Budget Targets

| Situation | Interval | Requests/day |
|---|---|---|
| All monitored servers online | 300 s | 288 |
| Any monitored server unhealthy | 60 s | 1440 |
| Nothing monitored | 300 s | 288 |
| Endpoint unreachable (backoff) | 60 → 600 s | 144 |

Muting servers excluded from the "unhealthy" check: a fleet broken only on muted servers preserves the healthy cadence.

### Backoff Strategy

Transport failures trigger exponential backoff starting at 60 s, doubling to **60 → 120 → 240 → 480 → 600 s**, capping at 600 s. Successful poll resets interval to 60 s baseline (alert-level). Prevents a dead network from creating request storms.

### Privacy Guarantees

- **One endpoint only:** `https://esoserverstatus.net/api/refresh`
- No analytics, telemetry, crash reporting, update checks, or beacons
- No data collected, stored, or transmitted — reads public status doc, renders colour
- HTTPS only; curl invoked **without `-L`**; certificate verification always enabled
- `curl` invoked without cookie jar — no cookies set or stored

---

## Source File Reference (paths)

| File | Size | Lines | Purpose |
|---|---|---|---|
| `/home/uri/.hermes-output/02-service-qml.md` | 18,892 chars | 355 | Polling engine & state management |
| `/home/uri/.hermes-output/03-barwidget-qml.md` | 6,790 chars | 177 | Bar button rendering & input |
| `/home/uri/.hermes-output/04-panel-qml-part1-structure.md` | 37,701 chars | 795 | Popout panel mount, layout, settings UI (structural) |
| `/home/uri/.hermes-output/05-panel-qml-part2-rendering.md` | 37,701 chars | 795 | Server list rendering & per-row logic (visual) |
| `/home/uri/.hermes-output/06-theme-js-servers-js.md` | 4,177 + 2,377 chars | 106 + 68 | Colour selection + name parsing |

Each spec file below contains the full source or detailed structural mapping with line references and algorithm descriptions. Read them in order starting from `02-service-qml.md`.
