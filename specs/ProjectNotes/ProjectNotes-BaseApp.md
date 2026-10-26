# Base App — ESO Server Status (v1.3.0)

Private working note. Listed in `.gitignore`; not for publication.

|| | |
|---|---|---|
| **Plugin** | `murankar.eso-server-status` v1.3.0 (`2aa96b6`) |
| **Dev repo** | `/home/uri/Projects/murankar.eso-server-status-1.2.0/` |
| **Install** | `~/.config/omarchy/plugins/murankar.eso-server-status/` |
| **Branch** | `dev` (identical to `main` at `2aa96b6`) |
| **Environment** | Omarchy `4.0.4-1`, Quickshell `0.3.1`, Arch, `curl 8.22.0`, Aether theme (`accent = #3aa000`) |

## Data source

```
GET https://esoserverstatus.net/api/refresh
X-Requested-With: XMLHttpRequest
Accept: application/json
```

Confirmed payload (7 keys): `{"servers":{"PC-EU":true,"PC-NA":true,"PC-PTS":true,"PS4-EU":true,"PS4-NA":true,"XBOX-EU":true,"XBOX-NA":true}}`

State semantics: `true` = online, `false` = offline, `2` = ongoing issues (renders orange). Payload keys are the plugin's stable identity — they must never be rewritten. Existing `mutedServers` entries match these keys exactly.

## Architecture overview

### Service layer (`Service.qml`)
Manages polling cycle over Quickshell's IPC bridge to the shell, with exponential backoff across five levels (4 s → 1 m → 5 m). Handles payload validation (`apply()`), state computation (`settle()` recovery notification), and settings persistence via shell IPC. `pollTimer` fires at `nextIntervalSeconds()`.

**`keepLoaded: true` in `manifest.json:58`:** the shell retains this service across hot-reloads, so saving `Service.qml` does not reload it — run `omarchy restart shell` for changes to take effect. This also means `--max-filesize` is not active until a full restart.

### Panel (`Panel.qml`) — 795 lines
Opens as a Quickshell `KeyboardPanel` window from the BarWidget on click/tap/drag. Dual tabs: Servers (per-server status, mute switches, grouped display) and Settings (poll/refresh intervals). Uses a single-delegate Repeater over alternating heading + server objects in `serverRows`.

**Key properties:** `status`, `onlineCount`, `totalCount` (`-1` sentinel for all-muted), `hasReading`, `serverList`, `stale`, `paused`. The bar glyph uses these plus `textForState()`.

### Bar widget (`BarWidget.qml`)
Loads the panel, provides the click/tap/drill area on the Omarchy bottom bar. On click: `togglePanel()` loads/dismisses; on tap-and-hold: `startDragTimer` opens the settings panel directly.

**Visibility rule:** `root.visible = root.hasReading`. The glyph stays on screen even when all servers are muted (`hasReading=true, onlineCount=-1/0`).

### Servers.js (pure functions)
Named `Servers.js`; untracked in git, must be committed before publishing. Contains: `split()` (last-hyphen), `label()`, `region()`, `groupLabel()`, `groupRank()`, `compare()`, `deviceLabel()`. Testable via node harness without QML context.

### Theme.js
Color helper module. `Theme.pick` resolves palette candidates; `statusColors(palette)` returns `{green, orange, red}` — the single source for status color picking across components.

## Settings schema (manifest.json)

| Setting | Type | Default | Range | Description |
|---|---|---|---|---|
| `healthyInterval` | int | 300 | 10–2592000 | Poll interval when all servers are green (seconds) |
| `alertInterval` | int | 60 | 10–86400 | Poll interval on orange/red status (seconds) |
| `refreshDelay` | int | 3 | 1–15 | Panel load delay; prevents duplicate loads |
| `muteServers` | var | `[]` | — | Array of muted server keys |

**Schema note:** `mutedServers` is in `defaults` only, **not** the JSON Schema. The schema array type drives Settings tab rows and accepts only scalar primitive types (`int`, `string`, etc.), so only a non-array value belongs there. An array is valid in defaults alone.

## Runtime notes

- `pgrep omarchy-shell` returns nothing; the process runs as `quickshell`. Use: `pgrep -af "quickshell\|omarchy-shell"` or read the PID from the journal.
- Panel switches use a null-prototype lookup (`Object.create(null)`) for O(1) mute checks instead of `indexOf()` array scan — this also handles payload keys named `constructor` / `hasOwnProperty`.
- Cross-realm arrays from the shell fail `Array.isArray()` — use duck-typing: `typeof raw.length === "number"` and copy via `String()`.

## Verification (passed)

```bash
# Plugin validation
omarchy plugin validate /home/uri/Projects/murankar.eso-server-status-1.2.0   # exit 0

# Journal check — no errors
journalctl --user --no-pager --since "-1min" | grep -iE "murankar|TypeError|ReferenceError" \
  | grep -viE "IpcHandler|Local plugin changed|Handler was registered"           # → nothing

# Plugin list
omarchy plugin list | grep murankar                                               # → enabled three-party service,bar-widget
```

## Deploy to installed copy

No build step. Edit in dev repo, then copy:

```bash
cd /home/uri/Projects/murankar.eso-server-status-1.2.0
cp Service.qml Panel.qml BarWidget.qml manifest.json Servers.js \
   ~/.config/omarchy/plugins/murankar.eso-server-status/
omarchy restart shell          # required for Service.qml changes
```

## Git state (as of 2026-10-14)

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

Nothing committed or pushed. When committing, remember `Servers.js` is untracked — a bare `git commit -a` would omit it.
