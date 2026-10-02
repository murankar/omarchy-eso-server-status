# Project Notes — UI Corrections

**Purpose of this document.** A complete, self-contained handoff for the mute
switch, server-list naming/grouping, and Servers-tab UI work done in one
session. If this session is lost, point a fresh agent at this file alone. It
contains everything needed to reproduce the exact same result: what was built,
why each decision was made, what was tried and abandoned, the two bugs that
survived a passing test, and how to verify the current state. No prior context
assumed.

**Scope.** Six deliverables, in the order the user asked for them:

| # | Deliverable | State |
|---|---|---|
| 1 | Per-server mute switches on the Servers tab | Complete, verified live |
| 2 | Display names: region-then-device, grouped by region | Complete, verified live |
| 3 | Drop the region prefix from row names | Complete, verified live |
| 4 | Accent colour on the headings and the count | Complete, verified live |
| 5 | Headings render no status text | Complete, verified live |
| 6 | Indent the seven server rows | Complete, verified live |

Everything below is the current, shipped state, not a plan.

**Relationship to the other notes.** `ProjectNotes-BaseApp.md` is the base app
handoff and `ProductionNotes-AddPanel.md` is the full panel effort. This file
supersedes neither: it records what came *after* both. Read those two first for
the architecture and the panel's original design; read this one for everything
that changed afterwards.

---

## 1. Quick facts

| | |
|---|---|
| **Plugin id** | `murankar.eso-server-status` |
| **Install location** | `~/.config/omarchy/plugins/murankar.eso-server-status/` |
| **Dev repo** | `/home/uri/Projects/murankar.eso-server-status-1.2.0/` |
| **Current branch** | `dev` |
| **Head commit** | `2aa96b6` "Bump version to 1.2.0" |
| **Working tree** | 5 modified + 1 untracked, **nothing committed** |
| **Files changed** | `BarWidget.qml`, `Panel.qml`, `README.md`, `Service.qml`, `manifest.json`, `Servers.js` (new) |
| **Diff size** | +398 / −47 |
| **This file** | `ProjectNotes-UICorrections.md` — intentionally untracked |

**Branch rule for this repo. Never merge to `main`.** All work stays on `dev`
until the user says otherwise. `main` and `dev` are both at `2aa96b6` and must
stay that way until explicitly told otherwise. Do not commit, push, or
fast-forward without being asked.

### Environment (verified 2026-09-30)

| Component | Version |
|---|---|
| Omarchy | `4.0.4-1` |
| Quickshell | `0.3.1` (Arch) — runs as `quickshell -n -p /usr/share/omarchy/shell` |
| curl | `8.22.0-1` |
| Active theme | Aether, `accent = "#3aa000"` |

`pgrep omarchy-shell` returns **nothing**. The shell runs under the name
`quickshell`; use `pgrep -af "quickshell\|omarchy-shell"` or read the pid out of
the journal. Looking for `omarchy-shell` as a process name looks like a dead
shell.

---

## 2. The data source (unchanged this session)

```
GET https://esoserverstatus.net/api/refresh
X-Requested-With: XMLHttpRequest
Accept: application/json
```

Live payload, re-confirmed this session:

```json
{ "servers": { "PC-EU": true, "PC-NA": true, "PC-PTS": true,
               "PS4-EU": true, "PS4-NA": true, "XBOX-EU": true, "XBOX-NA": true } }
```

Seven keys, captured live with:

```bash
curl -fsS --max-time 10 -H "X-Requested-With: XMLHttpRequest" \
  -H "Accept: application/json" https://esoserverstatus.net/api/refresh \
  | jq -c '{count: (.servers|length), keys: (.servers|keys)}'
```

Value semantics are unchanged: `true` online, `2` "ongoing issues" (deliberately
not counted as online, so it reads orange), `false` offline.

**The payload keys are the plugin's stable identity.** This single fact drives
the most important design decision in this session — see §5.

---

## 3. Deliverable 1 — per-server mute switches

A switch per server row. Switching it off **mutes** the server: it is dropped
from the `N of M` count and from the green/amber/red verdict that colours the bar
glyph, and its row goes dim and says `muted`.

### Persistence

Deny-list stored as `mutedServers` in `~/.config/omarchy/shell.json`:

```json
{ "id": "murankar.eso-server-status", "paused": false,
  "mutedServers": ["XBOX-EU", "PS4-EU"] }
```

Deny-list rather than allow-list for two reasons: an install predating the
setting has no entry at all and keeps watching the whole fleet, and a server the
site adds later arrives monitored rather than silently unmonitored by a list
that never mentioned it.

**`mutedServers` was added to `barWidget.defaults` in `manifest.json` but NOT
to `barWidget.schema`.** The schema array drives the *Settings tab's* generated
rows and only accepts scalar types; an array belongs in `defaults` alone. The
mutes are toggled from the Servers tab, not typed into Settings.

### The all-muted case

Muting everything is legal and must not make the widget vanish. The bar stays
on screen and says `no servers monitored`:

| Property | Value when all muted |
|---|---|
| `status` | `""` |
| `onlineCount` | `-1` |
| `totalCount` | `0` |
| `hasReading` | `true` |

`-1` was already the bar's "nothing to say about a count" sentinel, so
all-muted needed no new state of its own. `hasReading` is the property that
separates "a real reading with nothing to report" from "no reading yet" — that
is why it was added.

`BarWidget.qml` visibility changed from `status !== ""` to `root.hasReading`, so
the glyph no longer disappears (taking the panel's own switch row with it) when
every server is muted.

### Cadence is the subtle part

Muting changes what a poll is *judged on*, never how many polls happen — the
endpoint returns the whole fleet in one document, so there is no cheaper request
to make. But it does change cadence in the direction the user wants: a fleet
that is only broken on servers they muted is not an incident, so it does not
trigger the 60-second alert poll and stays on the 300-second healthy one.

```js
function nextIntervalSeconds() {
  if (failures > 0) { /* exponential backoff, unchanged */ }
  if (status === "red" || status === "orange") return alertSeconds()
  return healthySeconds()
}
```

A muted server left in `serverList` so the panel keeps listing it, but skipped
for the counts and the verdict.

### Toggling forces an immediate poll

`toggleMonitored()` ends with `root.service.lastPollAt = 0`. The glyph is
currently showing a verdict computed over a set the user just changed; leaving
it on screen until the interval expired would mean showing a fleet the plugin
has stopped watching. Mid-poll the service ignores this and the next poll
settles it anyway.

---

## 4. The two bugs that survived a passing test

**This is the most valuable section in the file.** Both bugs passed a green
headless test suite and were caught only by probing the running shell. Do not
trust a transplanted-into-node test for anything that crosses the QML/JS
boundary.

### 4.1 `Array.isArray()` is false for a cross-realm array

**Symptom.** The mute feature did nothing at all. No error, anywhere. Every
server stayed monitored regardless of what `mutedServers` contained.

**Root cause.** The guard in `mutedList()` was:

```js
return Array.isArray(raw) ? raw : []
```

Qt hands the plugin an array that was built in the *shell's* JS realm.
`Array.isArray()` checks realm identity, so it answers **`false`** for a real
array that arrived from another realm. Measured live:

```
typeof=object isArray=false ctor=Array length=7 indexOf=function join=function first=string
```

Note `ctor=Array`, `length=7`, `indexOf` is a function — a perfectly good array
by every measure except the one being tested.

**Fix.** Duck-type, and copy the names out (which also normalises them to
strings, which is what comparing against the payload's keys needs):

```js
function mutedList() {
  var raw = settings ? settings.mutedServers : undefined
  if (!raw || typeof raw.length !== "number") return []
  var names = []
  for (var i = 0; i < raw.length; i++) names.push(String(raw[i]))
  return names
}
```

Applied identically in `Service.qml` and `Panel.qml` — the two copies must
agree or a switch stops matching its own row.

**Why the test passed.** The node suite built its own array in its own realm,
where `Array.isArray()` is `true`. The test exercised the *logic*, not the
*boundary*, and the bug lived entirely in the boundary. The suite now includes
array-like objects (`{ length: 1, 0: "PC-EU" }`) that reproduce the real failure.

### 4.2 A stale per-panel settings copy could drop an edit

**Symptom.** Found by reading the code, not by a crash — the first instance of a
panel overwrites a later one's change.

**Root cause.** `setSetting()` seeded every write from `root.settings`, the
*panel's own* copy. But more than one panel instance is alive at once — the bar
keeps a hidden one loaded next to the one in the popout — and only the service is
updated by every write. A later edit seeded from a stale instance handed back an
older entry and silently dropped an earlier one.

**Fix.** Seed from the service, which is the single shared owner:

```js
function setSetting(key, value) {
  var base = root.service && root.service.settings ? root.service.settings : root.settings
  var entry = { id: root.moduleName }
  if (base) for (var k in base) if (k !== "id") entry[k] = base[k]
  entry[key] = value
  root.settings = entry
  if (root.service) root.service.settings = entry
  if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
    root.bar.shell.updateEntryInline(root.moduleName, entry)
}
```

`toggleMonitored()` reads through a matching `storedMutedList()` for the same
reason: toggling off a stale list would put a server back on that another panel
had just switched off.

---

## 5. Deliverable 2 — naming and grouping

### The rule that governs everything here

**The payload key is never rewritten.** `mutedServers` stores exactly the
site's own keys (`PC-NA`, `PS4-EU`, `XBOX-NA`). A display label is carried
*beside* the key, never in place of it.

> Changing what a row *shows* must not change what an existing setting *means*.
> A user who muted `PC-NA` before this existed keeps a muted `PC-NA`.

Every row object therefore carries both: `{ heading, label }` for display and
`server.name` for identity.

### What the panel shows

Iterated through three states during the session, ending here:

| Stage | NA group | EU group | PTS |
|---|---|---|---|
| Initial (region-first) | `NA-PC`, `NA-PlayStation`, `NA-XBOX` | `EU-PC`, `EU-PlayStation`, `EU-XBOX` | `PC-PTS` |
| After step 1 (final) | `PC`, `PlayStation`, `XBOX` | `PC`, `PlayStation`, `XBOX` | `PC-PTS` |

```
NA                     ← accent, no status text
    ● PC                online
    ● PlayStation       online
    ● XBOX              online
EU                     ← accent, no status text
    ● PC                online
    ● PlayStation       online
    ● XBOX              online
PUBLIC TEST SERVER     ← accent, no status text
    ● PC-PTS            online
```

The user first asked for region-then-device names, then removed the prefix once
the headings were grouping them. The heading names the region once; repeating it
on every row said the same thing seven times.

### `Servers.js` — new file, pure functions, no QML

Deliberately a plain JS module so the naming and grouping are testable without a
shell:

```js
function split(name)        // splits on the LAST hyphen, so "XBOX-2-EU" works
function deviceLabel(device) // { "PS4": "PlayStation" }, unknown devices pass through
function label(name)        // the display name; PTS returned untouched
function region(name)       // "NA" | "EU" | "PTS" | "" when there is no region
function groupLabel(region) // "Public Test Server" for PTS, else the region
function groupRank(region)  // NA=0, EU=1, PTS=2, unknown=3
function compare(a, b)      // region first, then label
```

Decisions inside:

- **`PS4` displays as `PlayStation`**, which is the name the console is sold
  under. Devices with no entry keep the site's own name.
- **The public test server is the exception.** It is a single server rather than
  a region, so `label()` returns `PC-PTS` untouched and its group is labelled for
  what it is. The user explicitly said to leave its naming alone.
- **Split on the *last* hyphen**, so a device name containing one does not throw
  the region off. Leading and trailing hyphens are not a split.
- **Unknown regions sort after the test server**, ranked last, and still get a
  heading. A console the site adds later should appear, just below the fleet we
  know about — not vanish.
- **A regionless name gets no heading.** An empty band above it would be noise.
- **Labels repeat across regions by design.** `PC` appears under both `NA` and
  `EU`. Uniqueness only has to hold *within* a group, which is all a reader ever
  compares at a glance. The test suite was changed to assert exactly that.

### Panel structure

The repeater walks a flat `serverRows` model built in `Panel.qml`, alternating
headings and servers, rather than nesting one repeater per region:

```js
readonly property var orderedServers: { var rows = root.servers.slice(); rows.sort(Servers.compare); return rows }
readonly property var serverRows:     { /* heading + server objects, in order */ }
```

Sorted on a copy so the service's list stays in whatever order the site sent it.
One delegate draws both row kinds — a nested repeater would let a heading end up
separated from its rows.

---

## 6. Deliverables 3–5 — colours and headings

### Accent colour

Taken from `Color.accent` (`qs.Commons`), which reads `accent` straight out of
the active theme's `colors.toml` — currently `#3aa000` from Aether.

**Not a hand-picked hue, deliberately.** A heading drawn in a *status* colour
would read as a server reporting that state; `Color.accent` is the one role
guaranteed to contrast `barForeground` in whatever theme gets installed next. It
also rides the theme's spacing and colour swaps automatically.

Applied to the three headings and to the `7 of 7 servers online` count. The
subtitle stays dimmed when it is *not* a real reading (stale, paused, all-muted),
since tinting "could not reach esoserverstatus.net" in accent would dress a
failure up as a result:

```qml
color: (root.stale || root.paused || root.onlineCount < 0)
  ? Qt.rgba(bar.barForeground.r, bar.barForeground.g, bar.barForeground.b, 0.65)
  : Color.accent
```

### Headings render no status at all — not even a hidden one

The first attempt set `visible: false` on the status text and left a comment
claiming it was empty. A probe reading the resolved values showed the comment
was lying:

```
ESO-HEADROW label="NA" statusText="offline" statusVisible=false
```

`textForState()` falls through to `"offline"` for any state it does not recognise,
so each heading was still *computing* "offline" and merely not drawing it.
Invisible today, but one binding change away from claiming a server is down.

Fixed to evaluate to `""` as well:

```qml
text: serverRow.heading ? "" : root.textForState(serverRow.rowState, serverRow.muted)
```

Verified: `statusText="" statusVisible=false dotVisible=false switchVisible=false`
on all three headings.

A heading is also not clickable and not hoverable — there is no server behind it
to toggle, and swallowing the click would silently do nothing.

---

## 7. Deliverable 6 — the indent

```qml
readonly property int indent: serverRow.heading ? 0 : Style.space(14)
```

- **14px ≈ four spaces** at the body font size, and on the theme's spacing scale,
  so a roomier theme gets a roomier indent instead of a hardcoded 14 that looks
  wrong next to everything else. `Style.space(14)` is the `xxxl` token.
- **Headings keep the flush-left edge.** They are the thing being indented away
  from; moving them too would collapse the distinction the indent creates.
- **The switch mirrors the indent on the right.** Indenting only the left would
  leave the status column and switches hanging at the old right edge and the rows
  would look shoved rather than nested.

Measured live geometry (`rowWidth=268`):

```
heading  indent=0   dotX=-     nameX=-     switchRight=-
server   indent=14  dotX=16    nameX=34    switchRight=254
```

The dot, name, and switch all shift together, so the row's internal spacing is
unchanged apart from the offset.

---

## 8. QML traps hit this session

Each of these cost time and would cost it again.

**Never add a second `Component.onCompleted` to an object that already has
one.** QML lets the later declaration *replace* the earlier one. A temporary
probe added as a second `Component.onCompleted` silently clobbered the real one,
so `onServiceArrived()` stopped running and the widget failed to load with
`Property value set multiple times`. Extend the existing handler.

**Probe state *after* injection, not at `Component.onCompleted`.** Two probes
read pre-injection state and reported bugs that did not exist: `settings` read
as `{}` because `injectPanel()` had not run yet, and a row's state read as
`undefined` because the field is `modelData.state`, not `modelData.status`.

**Never read `modelData.server.X` unguarded in a delegate that also handles
rows without a server.** Heading rows have no `server`, so every binding threw
a `TypeError` — and while those errors were invisible on screen they filled the
journal. Added:

```qml
readonly property string rowState: serverRow.heading ? "" : modelData.server.state
```

with the reasoning in the comment: errors on rows nobody is looking at still
fill the journal.

**A `Text` element accidentally matched an edit anchor and silently de-indented
an unrelated element** (the "Open esoserverstatus.net" link lost its right
anchor). Verify the elements around every edit, not just the one you changed.

**Screenshots cannot verify this UI.** The popup background and a dark
wallpaper are both near-black and pixel heuristics produce false results in both
directions; the tray's item widths shift between restarts, so the widget's x
position moved between 1756 and 2444 across runs in one session, which
invalidated a whole round of pixel hunting. `Servers` grouping, colours, and
indent were all verified by logging resolved binding values instead. That works
and is faster.

**`grim` and pixel-diffing are not available as a fallback** — this agent cannot
read images at all, so every visual claim in this session rests on logged
binding values, not on looking at the panel.

---

## 9. Verification recipes

All of these passed. The node suites live in `/tmp/opencode/` and are **not**
part of the repo — recreate them from the recipes below if lost.

**Both test suites**

```bash
node /tmp/opencode/eso-logic-test.js     # aggregation, muting, cadence  → "all checks passed"
node /tmp/opencode/eso-servers-test.js   # naming, grouping, ordering  → "26 checks passed"
```

`eso-logic-test.js` fetches the real payload and drives `apply()` through: absent
key, one muted, an outage, all muted, invalid array shapes, a stale name in
`mutedServers`, unparseable JSON, and backoff. It covers the cross-realm
array-like case that §4.1 describes — that case is the one that must not be
removed.

`eso-servers-test.js` loads the real `Servers.js` and checks every label, region,
heading, and ordering rule, including that labels are unique *within* a group.

**Loading a JS module under node.** QML's `import "X.js"` hoists bare
declarations onto a namespace object; node does not. Collect them explicitly so
the code under test stays the real file:

```js
const EXPORTS = ["split", "label", "region", "groupLabel", "groupRank", "compare", "deviceLabel", "isTest"]
const Servers = new Function(fs.readFileSync(SRC, "utf8") + "\nreturn { " + EXPORTS.join(", ") + " };\n")()
```

**Manifest is valid**

```bash
omarchy plugin validate /home/uri/Projects/murankar.eso-server-status-1.2.0
# → exit 0
```

**Deploy to the installed copy.** There is no build step; the plugin *is* the
files. Edit in the dev repo, then copy, and always copy the new file too:

```bash
cd /home/uri/Projects/murankar.eso-server-status-1.2.0
cp Service.qml Panel.qml BarWidget.qml manifest.json Servers.js \
   ~/.config/omarchy/plugins/murankar.eso-server-status/
omarchy restart shell
```

`Service.qml` changes need a restart (see `keepLoaded` in the base-app notes);
bar-widget changes hot-reload on save.

**Confirm it loaded clean**

```bash
journalctl --user --no-pager --since "-1min" | grep -iE "murankar|TypeError|ReferenceError" \
  | grep -viE "IpcHandler|Local plugin changed|Handler was registered"
# → nothing
omarchy plugin list | grep murankar
# → murankar.eso-server-status enabled third-party service,bar-widget ESO Server Status
```

`Handler was registered but will not be used because another handler is
registered for target omarchy.*` is pre-existing noise from the settings tab's
device toggles, not from this work.

**Confirm no probe was left behind.** Probes are installed into the *installed*
copy only, then overwritten by the final `cp` from the dev repo:

```bash
grep -rn "ESO-" ~/.config/omarchy/plugins/murankar.eso-server-status/*.qml
# → must print nothing
```

**The temporary probe pattern that worked.** Inject into the installed copy, run,
then re-copy from the dev repo to remove:

```python
p = "/home/uri/.config/omarchy/plugins/murankar.eso-server-status/Panel.qml"
s = open(p).read()
anchor = "  function mutedList() {"
probe = '''  Timer {
    interval: 3500
    running: true
    repeat: false
    onTriggered: console.warn("ESO-PROBE " + JSON.stringify(/* ... */))
  }

  function mutedList() {'''
open(p, "w").write(s.replace(anchor, probe, 1))
```

Use a **delayed `Timer`**, not `Component.onCompleted` — see §8.

**Confirm the live mute state end to end.** Verified this session, each row after
a `omarchy restart shell`:

| `mutedServers` | Observed |
|---|---|
| `[]` | `visible=true status='green' colour=#4bb017 online=7/7` |
| `["XBOX-EU"]` | `visible=true status='green' online=6/6` |
| all 7 | `visible=true status='' nothingMonitored=true tooltip='ESO Server Status - no servers monitored' colour=#e0e8d3 online=-1/0` |

`#4bb017` is green, `#e0e8d3` is the neutral foreground. The glyph staying
*visible* in the all-muted row is the assertion that matters — a widget that
disappears when you mute everything would take its own switch row with it.

To set the list for testing, edit `shell.json` directly:

```bash
python3 - <<'PY'
import json
p = "/home/uri/.config/omarchy/shell.json"
c = json.load(open(p))
for sec in ("left", "center", "right"):
    for e in c["bar"]["layout"][sec]:
        if e.get("id") == "murankar.eso-server-status":
            e["mutedServers"] = ["XBOX-EU"]
json.dump(c, open(p, "w"), indent=2)
PY
omarchy restart shell
```

Restore afterwards to the pristine entry — `{"id":"murankar.eso-server-status"}`,
no `mutedServers` key at all.

---

## 10. Final state of the panel

```
ESO Server Status
7 of 7 servers online                    ← accent

[ Servers ] [ Settings ]

NA                                          ← accent, uppercase, DemiBold, +0.6 tracking
    ● PC                          online
    ● PlayStation                 online
    ● XBOX                        online
EU                                          ← accent
    ● PC                          online
    ● PlayStation                 online
    ● XBOX                        online
PUBLIC TEST SERVER                          ← accent
    ● PC-PTS                      online

Open esoserverstatus.net
```

Row geometry: server rows 30px, headings 16px, indent `Style.space(14)` on both
edges, dot 8px at `leftMargin Style.space(2) + indent`, name 10px clear of the
dot, status 12px clear of the switch.

---

## 11. Git state — read this before doing anything

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

**Nothing is committed. Nothing is pushed. `main` has never been touched.**

When the user approves a commit, it goes on `dev` only:

```bash
git add Servers.js BarWidget.qml Panel.qml Service.qml README.md manifest.json
git commit -m "..."
```

Remember `Servers.js` is untracked, so a `git commit -a` would silently omit it
and the panel would fail to load on a fresh clone.

---

## 12. Open items

- **Nothing is committed.** All six deliverables are uncommitted working-tree
  changes on `dev`.
- **No visual confirmation.** The agent cannot read images, so the panel has
  never been *looked at*. Every claim here rests on logged resolved binding
  values. Worth the user opening it once and confirming the indent feels right
  and the accent reads as structure rather than status.
- **`ProjectNotes-UICorrections.md` is untracked** and listed in `.gitignore`.
  Back it up somewhere outside the repo before any `omarchy plugin update`, which
  re-clones and would delete untracked files.