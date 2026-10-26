# Project Notes — UI Corrections

Private working note. Listed in `.gitignore`; not for publication.

**Deliverables:** six items completed and verified live.

|| # | Deliverable | State |
|---|---|---|
| 1 | Per-server mute switches on the Servers tab | Complete |
| 2 | Display names: region-then-device, grouped by region | Complete |
| 3 | Drop region prefix from row names | Complete |
| 4 | Accent colour on headings and count | Complete |
| 5 | Headings render no status text | Complete |
| 6 | Indent the seven server rows | Complete |

|| | |
|---|---|---|
| **Plugin** | `murankar.eso-server-status` |
| **Install** | `~/.config/omarchy/plugins/murankar.eso-server-status/` |
| **Dev repo** | `/home/uri/Projects/murankar.eso-server-status-1.2.0/` |
| **Branch** | `dev`; uncommitted working tree (5 modified + 1 untracked) |
| **Files changed** | `BarWidget.qml`, `Panel.qml`, `README.md`, `Service.qml`, `manifest.json`, `Servers.js` (new) |

---

## 1. Per-Server Mute Switches

A switch per row. Off = muted: dropped from the `N of M` count and green/amber/red verdict, row goes dim with "muted" label.

### Persistence
Deny-list as `mutedServers` in `~/.config/omarchy/shell.json`:
```json
{"id": "murankar.eso-server-status", "paused": false, "mutedServers": ["XBOX-EU"]}
```

Deny-list over allow-list: a pre-existing install has no entry and keeps monitoring everything; a new server added later arrives monitored, not silently unmonitored.

**Schema note:** `mutedServers` is in `defaults` only, **not** the JSON Schema. The schema array drives Settings tab rows and accepts only scalar primitive types — an array is valid in defaults alone. Mutes are toggled from the Servers tab, not typed into Settings.

### All-muted edge case
Muting everything stays legal; the widget does not vanish:

|| Property | Value when all muted |
|---|---|
| `status` | `""` |
| `onlineCount` | `-1` |
| `totalCount` | `0` |
| `hasReading` | `true` |

`-1` is the bar's "nothing to report" sentinel; `hasReading` distinguishes "real reading, nothing to say" from "no reading yet." Visibility changed from `status !== ""` to `root.hasReading` so the glyph stays visible (taking its own switch row with it).

### Cadence
Muting changes *what* a poll is judged on, never how many polls happen — the endpoint returns the whole fleet in one document.

```js
function nextIntervalSeconds() {
  if (failures > 0) { /* exponential backoff */ }
  if (status === "red" || status === "orange") return alertSeconds()
  return healthySeconds()
}
```

A muted server stays in `serverList` so the panel continues listing it, but is skipped for counts and verdict.

### Immediate poll on toggle
`togglegMonitored()` sets `root.service.lastPollAt = 0`, forcing a fresh vote immediately after the user changes what's being polled.

---

## 2. Naming and Grouping

### Governing rule: payload keys are never rewritten
`mutedServers` stores exactly the site's keys (`PC-NA`, `PS4-EU`). A display label is carried *beside* the key, not in place of it.

Every row carries both: `{ heading, label }` for display and `server.name` for identity.

### Final display format
```
NA                                  ← accent, no status text
    ● PC                           online
    ● PlayStation                  online
    ● XBOX                         online
EU                                  ← accent
    ● PC                           online
    ● PlayStation                  online
    ● XBOX                         online
PUBLIC TEST SERVER                  ← accent
    ● PC-PTS                       online
```

### Servers.js — pure function module
Plain JS so naming/grouping is testable without a shell:

| Function | Purpose |
|---|---|
| `split(name)` | Splits on LAST hyphen (`XBOX-2-EU` survives) |
| `deviceLabel(device)` | `{ PS4 → "PlayStation" }`, unknown pass through |
| `label(name)` | Display name; PTS returned untouched |
| `region(name)` | `"NA"` \| `"EU"` \| `"PTS"` \| `""` |
| `groupLabel(region)` | `"Public Test Server"` for PTS, else region |
| `compare(a, b)` | Region first, then label |

**Decisions:**
- PS4 → PlayStation (console's commercial name)
- Public test server is a single entry, not a region — left untouched
- Split on *last* hyphen so compound device names don't throw the region
- Unknown regions sort after PTS, still get a heading (new consoles appear, not vanish)
- Labels repeat across regions by design (`PC` under both NA and EU); uniqueness only within a group

### Panel structure
Flat `serverRows` model — alternating headings + servers — drawn by one delegate. No nested repeater so a heading can't separate from its rows.

---

## 3–6. Colours, Headings, Indent (Completed)

- **Accent colour** taken from `Color.accent` (the theme's `accent`), not a hand-picked hue. Guarantees contrast against `barForeground` in any theme.
- **Caption colour:** accent when real reading; dimmed (`65% opacity`) when stale/paused/all-muted — "could not reach the API" should never be dressed as a result.
- **Headings render no status** — evaluated to `""`, not just hidden. A visible-but-empty approach was abandoned after it was found to still compute an "offline" value that could leak if any binding changed. Headings are neither clickable nor hoverable.
- **Indent:** `Style.space(14)` (~4 spaces, on the theme's spacing scale). Applied to both left edge and switch position so internal row spacing is unchanged. Headings stay flush-left.

Measured geometry (`rowWidth=268`):
```
heading  indent=0   dotX=-     nameX=-     switchRight=-
server   indent=14  dotX=16    nameX=34    switchRight=254
```

---

## QML Traps Hit This Session

| Trap | Avoidance |
|===|===|
| Multiple `Component.onCompleted` on same object → later replaces earlier | Extend the existing handler only |
| Reading probe state *before* `injectPanel()` runs → reports pre-injection garbage | Read probe state after injection, not at Component.onCompleted |
| Unguarded `modelData.server.X` in delegates handling rows without a server → TypeError floods journal | Check `serverRow.heading ? ... : modelData.server.state` first |
| A Text element accidentally matched an edit anchor → silently broke an unrelated layout item | Verify the elements around every edit, not just the one changed |

---

## Verification Recipes (All Passed)

**Test suites** (in `/tmp/opencode/`, not part of the repo):
```bash
node /tmp/opencode/eso-logic-test.js     # aggregation, muting, cadence  → "all checks passed"
node /tmp/opencode/eso-servers-test.js   # naming, grouping, ordering     → "26 checks passed"
```

**Manifest valid:** `omarchy plugin validate /home/uri/Projects/murankar.eso-server-status-1.2.0` → exit 0

**Deploy to installed copy:**
```bash
cd /home/uri/Projects/murankar.eso-server-status-1.2.0
cp Service.qml Panel.qml BarWidget.qml manifest.json Servers.js \
   ~/.config/omarchy/plugins/murankar.eso-server-status/
omarchy restart shell          # required for Service.qml changes; BarWidget hot-reloads
```

**Confirm clean load:**
```bash
journalctl --user --no-pager --since "-1min" | grep -iE "murankar|TypeError|ReferenceError" \
  | grep -viE "IpcHandler|Local plugin changed|Handler was registered"   # → nothing
omarchy plugin list | grep murankar                                    # → enabled, bar-widget
```

**Confirm no probe left behind:**
```bash
grep -rn "ESO-" ~/.config/omarchy/plugins/murankar.eso-server-status/*.qml  # → must print nothing
```

---

## Git State (as of 2026-10-14)

```
branch: dev
HEAD:   2aa96b6 Bump version to 1.2.0
main:   2aa96b6 (identical, untouched)
```

```
 M BarWidget.qml
 M Panel.qml
 M README.md
 M Service.qml
 M manifest.json
?? Servers.js
```

Nothing committed or pushed. `Servers.js` is untracked — a `git commit -a` would silently omit it.

When ready to commit:
```bash
git add Servers.js BarWidget.qml Panel.qml Service.qml README.md manifest.json
git commit -m "..."   # on dev only
```
