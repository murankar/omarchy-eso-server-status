# Production Notes — Panel Implementation

Private working note. Listed in `.gitignore`; not for publication.

|| | |
|---|---|---|
| **Plugin id** | `murankar.eso-server-status` |
| **Head commit** | `27b84cd` (identical on `main`/`dev`, pushed to GitHub) |
| **Repo** | `git@github.com:murankar/omarchy-eso-server-status.git` |
| **Panel** | `Panel.qml` (470 lines); a plain file inside the bar widget, not a new manifest kind |

## Commit series (5 commits from `94bc2ab` → `8beba37`)

| Commit | Change | Rationale |
|---|---|---|
| `94bc2ab` | Per-server panel on left click | Bar glyph showed one colour for the fleet; individual server state was invisible |
| `0448e96` | Fixed status text clipped by card border | Body overflowed ~32px right; border cut through status word |
| `3765435` | Right-aligned status text with 8px margin | Reads as a table when status sits beside each name |
| `dfe5221` | Servers / Settings tabs | The four poll settings previously had no UI; left click originally opened the site |
| `8beba37` | Pause switch + forced refresh on resume | No way to spend zero requests on a metered link |
| (follow-up) | Paused state on glyph and every row | Previously only visible inside the panel or tooltip |

## UI behaviour

### Bar entry click routing (one `onPressed`)

| Input | Result |
|---|---|
| Left click | Toggle panel |
| Right click | Open `https://esoserverstatus.net/` |
| Middle click | Force immediate re-poll (`lastPollAt = 0`) |

### Panel states

| State | Colour | Meaning |
|---|---|---|
| online | green | Reported `true` |
| ongoing issues | amber | Reported `2` (distinct from red to avoid overstating severity) |
| offline | red | Reported `false` |
| unknown | dimmed | Last poll failed; no state claimed |

### Layout essentials (three widths inside a `KeyboardPanel`)

| Value | Meaning |
|---|---|
| `panel.width/height` | Layershell window (500×500), **not** the visible card |
| `panel.contentWidth/Height` | Card size — use for bounding boxes |
| `parent.width` inside body | Inset content area (`contentHolder` minus 14px padding + 2px border = 16px per side) |

**Inset gotcha:** Body Column must be `width: parent.width` (not `panel.contentWidth`). The single most reusable fact.

`centerOnBar: false` makes the card position under the bar entry via `anchorScreenPos`; `true` centres on the whole bar (screen centre with a top bar).

`contentHeight` tracks body's implicit height, so the card resizes between tabs automatically. Measured at screen offset `+2372+94` (physical):

| Tab | Card (logical) | Card (physical, scale 2) |
|---|---|---|
| Servers | 300×429 | 600×858 |
| Settings (4 rows) | 300×266 | 600×532 |
| Settings (5 rows, pause) | 300×298 | 600×596 |

### Tabs implementation (`dfe5221`)

Two `PanelSeparator`s with outlined `Button` pills between them (`bordered: true`, `active` on selected), styled to match `DnsProviderPill` in the Network panel. Cell width computed dynamically for resilience to tab count changes. Both tab bodies are `Column`s; `visible: root.tab === n`.

**Design decisions:**
- Settings was made functional rather than a placeholder — there was no UI for poll settings before this. Left click stopped opening the site (right click is now the only route).

## Pause switch implementation (`8beba37`)

Gate placed **inside `maybePoll()`**, not around external call sites:

```qml
function maybePoll() {
  if (paused || settled || fetch.running) return
  ...
}
```

This prevents any path — including forced re-poll from a middle click — from starting while paused.

**Resume forces refresh:** `onPausedChanged` sets `lastPollAt = 0`, so the next 2-second tick fetches immediately instead of waiting for the leftover interval.

### Paused visual language (all surfaces)

| Surface | While paused | Live |
|---|---|---|
| Bar glyph | `bar.barForeground` — plain like other glyphs | Green / amber / red |
| Bar tooltip | `pollingpaused` (dimmed) | Status count with `detail` on |
| Panel header | `Polling paused - N of 7 servers online` (dimmed) | `N of 7 servers online` |
| Every server row | `paused`, dot + status in name's colour | Server state and colour |

Each row: dot, status text, and name all take `bar.barForeground` so the row becomes plain text — a **state claim the panel has withdrawn**. The name's Text already uses this colour, so "match the name" was literally the same expression.

Paused ranks above stale everywhere; unpausing forces a fetch and if the endpoint is unreachable that becomes true again immediately. Glyph for paused vs. stale looks identical (both plain `bar.barForeground`) — the tooltip and panel header disambiguate, consistent with matching other bar glyphs.

### Implementation details

```qml
// BarWidget.qml — paused joins the existing stale fallback
readonly property color statusColor: (stale || paused) ? (bar ? bar.barForeground : Color.foreground)
  : status === "green" ? greenColor : ...
```

```qml
// Panel.qml
function colorForState(state) {
  if (root.paused) return bar.barForeground   // matches server name Text colour
  if (root.stale)  return root.dimmed
  ...
}
function textForState(state) {
  if (root.paused) return "paused"
  if (root.stale)  return "unknown"
  ...
}
```

### QML gotcha: property-changed handlers fire before bindings re-evaluate

A handler on property `B` when `B` is bound to changed property `A` fires **before** `B`'s binding has been re-evaluated. The first run of a pause test logged the old (stale) colour from `B`'s own change handler — misleading. Lesson: never assert a value from inside its own change handler; log from a separate observer after settling state.

## Settings write path (`setSetting()` at `Panel.qml:57`)

Three-way write, in order:

1. `root.settings = entry` — panel's copy (controls re-read the new value)
2. `root.service.settings = entry` — pushed to service (new interval applies next poll instead of waiting for `shell.json` round-trip)
3. `root.bar.shell.updateEntryInline(root.moduleName, entry)` — persists to disk

Entry shape: rebuild as `{id: root.moduleName}`, copy all other keys from the existing entry, then set the changed key. Avoids the classic bug of writing a partial entry that drops other settings.

Ranges mirror `Service.qml` clamps exactly — no client/server range mismatch possible:

| Control | Range | Step | Default | Service clamp |
|---|---|---|---|---|
| Healthy poll (s) | 120–3600 | 30 | 300 | `Math.max(120, ...)` |
| Incident poll (s) | 30–1800 | 30 | 60 | `Math.max(30, ...)` |

## Traps hit during development

- **QML `Row` children cannot use anchors.** A `Row` positions its own children and rejects anchors. Every setting row had to become an `Item`. This is worth remembering generally — it's an easy trap.
- **Labels were silently eliding.** Long labels (`"Interval, all online (s)"` at 173px) exceeded available space (136px) without showing any hint. Fix: bounding the label to its control with `elide: Text.ElideRight`.

## Verification methodology and traps

### Techniques that worked

| Technique | Use |
|---|---|
| Temporary `console.warn` of resolved binding | Actual value; immune to rendering |
| Temporary `Timer` calling `root.open()` | Reproduces panel without clicking |
| `Rectangle` at `panel.contentWidth × contentHeight` | Exact card bounding box |
| Raw pixel analysis (no colour masking) | Ground truth for geometry |

### Trap: screenshots come back at scale 2

A 1500×1000 logical screen yields a 3000×2000 PNG. Halve any pixel bounding box before comparing to logged logical values.

### Trap: masking probes can hide real content

Painting `geomProbe` magenta to get an exact card bounding box by `-opaque` masking swallowed theme accent-coloured switch tracks (accent was magenta-ish under 12% fuzz). Recolouring blue reproduced the same wrong result. **Raw pixels with no masking are the truth.** A debugging overlay can become what you're measuring: when instrumented and uninstrumented geometry disagree, believe raw pixels.

### Trap: passing tests that proved nothing

First pause test waited 22 seconds and saw no polls while paused — but the healthy interval is 300 seconds, so **no poll would have happened anyway**. The correct retest forced polls to be `due` by zeroing `lastPollAt` while paused; verified two forced-due attempts were refused, and unpausing produced a poll ~2s later. Lesson: check that a negative result is possible before trusting it.

### Trap: screen-scraping for panel window presence

Counting green bands to confirm the panel was closed reported 8 bands (unrelated windows also contain green pixels). Correct check: query via `hyprctl clients`, not pixel counts.

### Instrumentation hygiene

All temporary code was removed before every commit. Verify and reset:

```bash
grep -rn "ESO-DBG\|geomProbe\|dbg\|console.warn" *.qml   # → nothing
```

**A debug probe left in the tree can write to real config.** The pause test persisted `{"paused": true}` into `shell.json` through the real `updateEntryInline` path — had to be reset by hand or polling was permanently off.

## Deliberate non-decisions (do not "fix" without asking)

- No keyboard navigation between tabs
- No tooltips on settings controls
- Panel width not widened for longer labels (would resize card between tabs)
- No dedicated "paused" glyph (deliberately identical to stale by request; tooltip disambiguates)
- Marketplace submission still on hold — no Chromium tab open, nothing filed
- No git tag cut yet (manifest is at 1.2.0 but tagging is a separate act)

## Open items

| # | Item | Priority |
|---|------|----------|
| 1 | Keyboard focus order for tab pills | Low |
| 2 | Distinct glyph for paused vs. stale (e.g. hollow dot) | Low |
| 3 | `NumberField` values are read-only; no reset-to-default | Low |
| 4 | Cut and push a 1.2.0 git tag (manifest already bumped) | Needs decision |
| 5 | Back up untracked notes outside the plugin before any `omarchy plugin remove` | **Do this first** — `plugin remove` deletes the install directory outright |

## Reproducing verification

```bash
cd ~/.config/omarchy/plugins/murankar.eso-server-status

# 1. Manifest valid
omarchy plugin validate . ; echo "exit: $?"

# 2. No QML errors after restart
MARK=$(date +%T); omarchy restart shell; sleep 26
journalctl --user --since "$MARK" | grep -i eso-server-status | grep -viE reloading

# 3. No instrumentation left behind
grep -rn "ESO-DBG\|geomProbe\|dbg\|console.warn" *.qml

# 4. Settings not mutated by testing
python3 -c "import json,io; d=json.load(io.open('$HOME/.config/omarchy/shell.json')); ...; print(json.dumps(e))"

# 5. Anonymous clone matches pushed head
git clone --depth 1 git@github.com:murankar/omarchy-eso-server-status.git /tmp/opencode/verify-clone
```

## If picking up cold, read in this order

1. `Panel.qml` lines 110+ — `KeyboardPanel`, sizing, inset comment at 133–135 (prevents the clip bug from returning)
2. `Panel.qml` line 57 — `setSetting()` three-way write
3. `Service.qml` lines 41–49 (`paused`) and line 81 (`maybePoll()` gate)
4. This section 10 (verification traps) before trusting any visual check
5. `ProjectNotes-BaseApp.md` for base plugin, request budget, and theming
