# Production Notes — Adding the Panel

**Purpose of this document.** A complete, self-contained record of the panel
work: what was built, why each decision was made, what was measured, what was
tried and abandoned, and how to re-verify the current state. If this session is
lost, point a fresh agent at this file alone. No prior context assumed.

**Scope.** The popout panel that opens on left click of the bar entry, across
five commits from `94bc2ab` to `8beba37`. This document covers only the panel
and the settings it owns. The base plugin, the request budget, and `Theme.js`
are documented in `ProjectNotes-BaseApp.md`.

**This file is intentionally untracked**, like the other production notes. It
is added to `.gitignore` and never published.

---

## 1. Quick facts

| | |
|---|---|
| **Plugin id** | `murankar.eso-server-status` |
| **Install location** | `~/.config/omarchy/plugins/murankar.eso-server-status/` |
| **Head commit** | `27b84cd` — identical on `main` and `dev`, pushed to GitHub |
| **Repository** | `git@github.com:murankar/omarchy-eso-server-status.git` |
| **Panel implementation** | `Panel.qml` (470 lines) — a file inside the bar widget, not a new manifest kind |
| **This file** | `ProductionNotes-AddPanel.md` — intentionally untracked |

### Files touched by the panel work

| File | Role | Lines |
|---|---|---|
| `Panel.qml` | The entire popout: header, tabs, server list, settings | 470 |
| `BarWidget.qml` | Click routing, loader, property injection into the panel | 159 |
| `Service.qml` | `serverList`, `paused` gate, forced refresh on resume | 175 |
| `manifest.json` | `paused` key in `defaults` and `schema` | — |
| `README.md` | User documentation for tabs, settings, pausing | 300 |

---

## 2. The commit series

Each commit is self-contained and was verified before the next one started.

| Commit | What it did | Why it was needed |
|---|---|---|
| `94bc2ab` | Per-server panel on left click | The bar glyph showed one colour for the whole fleet. Individual server state was invisible. |
| `0448e96` | Fixed status text clipped by the card border | The body column overflowed ~32px right; the border ran through the status word. |
| `3765435` | Right-aligned the status text with an 8px margin | Status sat beside each name; a right-hand status column reads as a table. |
| `dfe5221` | `Servers` / `Settings` tabs | Left click used to open the site, so the four poll settings had no UI at all. |
| `8beba37` | Pause switch, forced refresh on resume | A user on a metered link had no way to spend zero requests. |
| `27b84cd` | Paused state on the glyph and every server row | The pause state was only visible if you were already looking at the panel or the tooltip. |

---

## 3. User-facing behaviour

### Click routing on the bar entry

| Input | Result |
|---|---|
| Left click | Toggle the panel |
| Right click | Open `https://esoserverstatus.net/` |
| Middle click | Force a re-poll immediately (`service.lastPollAt = 0`) |

Handled in one `onPressed` in `BarWidget.qml:149`.

### The panel itself

Opens under the bar entry, closes on outside click, on `Escape`, and via the
shell's normal panel dismissal. It is a **pure view**: it performs no I/O and
never contacts the network, so opening it adds no request and cannot drift from
the bar glyph. The panel carries its own link to the site, so right click is
never the only route there.

**Server states**, coloured per server rather than for the fleet:

| State | Colour | Meaning |
|---|---|---|
| `online` | green | The service reported `true` |
| `ongoing issues` | amber | Reported `2`: reachable, but impaired |
| `offline` | red | Reported `false` |
| `unknown` | dimmed | The last poll failed, so no state is being claimed |

Amber is deliberately distinct from red. `2` means the server is up with
ongoing issues; collapsing it into offline overstates the severity.

---

## 4. How the panel is wired

`Panel.qml` is a plain file inside the bar widget — **not** a new manifest
kind. The manifest still declares only `service` and `bar-widget`. This is the
pattern the weather plugin uses, and it means no manifest surgery is needed to
add a panel.

The wiring, in order:

1. `BarWidget.qml` holds a `Loader` for the panel.
2. When the loaded item appears, the widget injects the live objects into it:
   `anchorItem`, `hostWidget`, `service`, `moduleName`
   (`BarWidget.qml:83`).
3. `Panel.qml` is handed the **live service object**, not a copy, so it reads
   the same state the glyph does.
4. `setSetting()` writes back three ways — see section 6.

`moduleName` was injected for the settings write path. `updateEntryInline`
needs the plugin id, and a second hardcoded copy of the id in `Panel.qml` was
exactly the kind of duplication that already caused a bug once (see
`4ef0adc` in `ProjectNotes-BaseApp.md`). It is now injected from the one place
that owns it.

---

## 5. Layout mechanics that matter

Three different widths are in play inside a `KeyboardPanel`. Do not assume they
match.

| Value | What it actually is |
|---|---|
| `panel.width` / `panel.height` | The **layershell window** (500x500), not the visible card |
| `panel.contentWidth` / `contentHeight` | The **card** size — use this for bounding boxes |
| `parent.width` inside the body | The **inset content area**, already reduced by padding and border |

### The inset gotcha (`0448e96`)

`KeyboardPanel` lays children out inside a `contentHolder` that is already
inset by `Style.spacing.popupPadding` (14) plus a 2px border, so **16 logical
pixels per side**. The body `Column` was originally sized to
`panel.contentWidth` — the full card width — so it overflowed ~32px to the
right and the border cut through the status word.

The fix is one line, and the comment in the file says why:

```qml
Column { width: parent.width }   // parent is contentHolder, already inset
```

This is the single most reusable fact in the whole panel.

### `centerOnBar: false`

`centerOnBar: true` is not what it sounds like: it centres the card on the
whole **bar**, which with a top bar is screen centre. `false` makes
`cardOrigin` use `anchorScreenPos` so the card sits under the bar entry.

### Card sizing

```qml
contentWidth:  panel.fittedContentWidth(Style.space(300))
contentHeight: panel.fittedContentHeight(body.implicitHeight)
```

`contentHeight` tracks the body's implicit height, so the card grows and
shrinks with the active tab automatically. Measured results:

| Tab | Card, logical | Card, physical (scale 2) |
|---|---|---|
| Servers | 300x429 | 600x858 |
| Settings (4 rows) | 300x266 | 600x532 |
| Settings (5 rows, with pause) | 300x298 | 600x596 |

All at screen offset `+2372+94` physical.

---

## 6. The settings write path

`Panel.qml:setSetting()` (line 57) writes to three places, in this order:

1. `root.settings = entry` — the panel's own copy, so the control re-reads
   what was just set.
2. `root.service.settings = entry` — pushed straight into the service, so a
   **new interval applies on the next poll** instead of waiting for the
   `shell.json` write to come back around through the bar widget.
3. `root.bar.shell.updateEntryInline(root.moduleName, entry)` — persistence.

`Service.qml` re-reads its intervals on every poll, so changing one needs no
restart and no service reload.

Entry shape: the base object is rebuilt as `{ id: root.moduleName }` and every
other key is copied across except `id`, then the one changed key is set. This
avoids the classic bug of writing a partial entry that drops the other settings.

### Ranges are mirrored, not invented

The `NumberField` bounds match the clamps in `Service.qml` exactly:

| Control | Range | Step | Default | Service clamp |
|---|---|---|---|---|
| `Healthy poll (s)` | 120..3600 | 30 | 300 | `Math.max(120, ...)` |
| `Incident poll (s)` | 30..1800 | 30 | 60 | `Math.max(30, ...)` |

A user therefore cannot enter a value the service would silently clamp to
something else.

---

## 7. The tabs (`dfe5221`)

### What was asked for

A second horizontal divider below the first, with `Servers` and `Settings`
between them, decorated to mimic the DNS provider row in the Network panel.

### What was built

Two `PanelSeparator`s with a `Row` of two outlined `Button` pills between them,
laid out the way `DnsProviderPill` in
`/usr/share/omarchy/shell/plugins/panels/network/Panel.qml` is (component
defined at line 1565): `bordered: true`, `active` on the selected one,
`Style.font.bodySmall`, equal-width cells, `Style.space(6)` gap.

The cell width is computed rather than hardcoded, so it survives a change to
the number of tabs:

```qml
readonly property int count: root.tabs.length
readonly property real cellWidth: (width - spacing * (count - 1)) / count
```

### Two decisions worth defending

**The Settings tab was made functional, not a placeholder.** The request was
for tab chrome. A tab labelled "Settings" that showed nothing would be a dead
end, and there was a real gap underneath: the four poll settings previously had
no UI anywhere, only a hand-editable `shell.json`. Shipping a working settings
tab closed that gap as a side effect.

**Left click stopped opening the site.** The panel now owns left click, so
right click is the only route to the site — which is why the panel carries its
own link. Nothing was lost, but this is a behaviour change worth remembering.

### The tab state

`property int tab: 0` on the panel root, driven directly by `onClicked`. Both
tab bodies are `Column`s with `visible: root.tab === n`. Because `visible:
false` removes an item from its parent's implicit height, the single
`contentHeight: panel.fittedContentHeight(body.implicitHeight)` resizes the
card between tabs with no extra logic. **Verified: both cards resize correctly.**

---

## 8. The pause switch (`8beba37`)

### The gate is inside `maybePoll`, not around it

```qml
function maybePoll() {
  if (paused || settled || fetch.running) return
  ...
}
```

Every schedule in the plugin funnels through this one function. Putting the
gate here means a paused service cannot be started by *any* path — including a
forced re-poll from a middle click. Wrapping the call sites instead would have
left a hole.

### Resuming forces a refresh

```qml
readonly property bool paused: !!setting("paused", false)

onPausedChanged: {
  if (!paused) lastPollAt = 0
}
```

Zeroing `lastPollAt` makes the next 2-second tick fetch immediately rather than
waiting out the interval that was left over. Without this, unpausing after a
10-minute pause would show 10-minute-old data for up to 5 more minutes.

### Honesty while paused

The counts on screen are last-known, not live. This plugin has never claimed a
freshness it does not have — the pre-existing `stale` flag already does this
for failed polls — so pausing got the same treatment:

| Surface | While paused |
|---|---|
| Panel header | `Polling paused - 7 of 7 servers online`, dimmed |
| Bar tooltip | `polling paused`, dimmed |
| Manifest schema | `Pause polling (resume forces an immediate refresh)` |

`paused` deliberately **outranks** the `detail` count in the tooltip, because
`polling paused` is the honest reading and the count is not.

This is the one place in the panel work where scope was extended past the
literal request. It is a two-line revert if that is unwanted.

### 8.1 The paused visual language (`PAUSED-GLYPH`)

The pause state was originally only visible in two places: the panel header and
the bar tooltip. Both require the user to already be looking at the right
surface. A user who is not looking at the panel has no way to tell that the
status they are reading is minutes or hours old. So paused now changes every
surface at once:

| Surface | While paused | While live |
|---|---|---|
| Bar glyph | `bar.barForeground` — plain, like the other bar glyphs | Green / amber / red by fleet status |
| Bar tooltip | `polling paused` | Status count, with `detail` on |
| Panel header | `Polling paused - N of 7 servers online` | `N of 7 servers online` |
| Every server row | `paused`, dot + status in the name's own colour | That server's state and colour |

### The per-row change, and why

This was proposed by the user, initially on the fence, and is the most opinionated
decision in the panel work. The reasoning that settled it:

- A coloured dot beside the word `paused` is a **state claim the panel has
  withdrawn**. The whole premise of the `stale` handling is that the plugin does
  not display a colour it cannot stand behind. Showing red next to `paused`
  would break that rule.
- The dot, the status text, and the server name all taking `bar.barForeground`
  is visually unmistakable: the row stops being a status readout and becomes
  plain text.
- The requirement "clear no matter where the end user is" is only met if the
  *server list itself* says so. The header alone is not enough, because the
  header scrolls out of the way and the list does not.

**The cost, stated plainly:** while paused, the per-server state is not
readable at all. If a server goes down and you then pause, the panel will not
tell you which one. That is the intended trade — unpausing forces an immediate
refresh, so the information costs one request to recover.

### Implementation, and the reuse

Both changes reuse the mechanism the `stale` flag already had, rather than
adding a parallel one:

```qml
// BarWidget.qml — stale already fell back to the plain foreground; paused
// joins it in the same expression.
readonly property color statusColor: (stale || paused) ? (bar ? bar.barForeground : Color.foreground)
  : status === "green" ? greenColor
  : ...
```

```qml
// Panel.qml — the two per-server helpers, paused checked first.
function colorForState(state) {
  if (root.paused) return bar.barForeground   // same as the server name Text
  if (root.stale)  return root.dimmed
  ...
}
function textForState(state) {
  if (root.paused) return "paused"
  if (root.stale)  return "unknown"
  ...
}
```

Because `colorForState()` already drives **both** the dot and the status text
(`Panel.qml` server row), one branch neutralised the entire row. The server
name's `Text` already used `bar.barForeground`, so "match the name colour" was
literally the same expression — no colour constant was introduced.

`paused` was also hoisted to a `readonly property bool` on `BarWidget`, so
`statusSuffix` and `statusColor` read the same value instead of one of them
reaching into `service.paused` directly.

### Precedence: paused beats stale

`paused` is checked before `stale` everywhere. If the last poll failed and the
user then paused, the panel says `paused` rather than `Could not reach
esoserverstatus.net`. The reasoning:

- The pause is the more recent, deliberate, actionable fact.
- The failure describes a poll that is no longer happening while paused, so it
  is no longer the live question.
- **Nothing is lost permanently.** Unpausing forces a fetch, and if the
  endpoint is genuinely unreachable that fetch fails and `stale` becomes true
  again immediately.

If this ordering is ever questioned, the fix is one line — swap the two
conditions in `colorForState`, `textForState`, and `subtitle`. But keep the
argument above with the change, because the ordering looks arbitrary otherwise.

### Paused and stale look identical on the glyph

A paused glyph and a stale glyph are both plain `bar.barForeground`. This is
deliberate: the request was that the glyph "match the other glyphs in the
status bar", and a distinct paused glyph would be a new visual language in the
bar. The tooltip disambiguates, and the panel header disambiguates. If a
distinct treatment is ever wanted, the cheapest is a hollow dot rather than a
new colour.

### Verification

Proved from resolved bindings, not pixels, per section 10:

```
GLYPH paused=false status=[green] color=#26a269 barFg=#bebebe   live: green
>> pausing
GLYPH paused=true  status=[green] color=#bebebe barFg=#bebebe   paused: matches bar
row   paused=true  text=paused color=#bebebe nameColor=#bebebe  row neutral
>> unpausing
GLYPH paused=false status=[green] color=#26a269 barFg=#bebebe   restored
```

The neutral colour `#bebebe` is demonstrably different from the live green
`#26a269`, so this is not a false pass caused by both being unstyled.

### A QML gotcha this surfaced

`onPausedChanged` logged `color=#26a269` — the **old** value:

```
GLYPH-PAUSED-CHANGED paused=true status=[green] color=#26a269   <-- stale colour
GLYPH                  paused=true status=[green] color=#bebebe  <-- correct
```

When a property `A` changes and property `B` is bound to `A`, a change handler
on `B` runs **before** `B`'s binding has been re-evaluated. Any instrumentation
that reads `B` from inside `B`'s own change handler therefore reports the
previous value. This produced a genuinely misleading first test run, and the
first run also missed the transition entirely because `status` was still empty
when the pause was applied.

**Lesson: never assert a value from inside the change handler of the property
you are asserting about. Log the new value from a separate observer, and make
sure the state under test is already settled before you change it.**

---

## 9. Traps hit while building this

### QML `Row` children cannot use anchors

The first settings layout used `Row` with an anchored label and control per
row. It logged four warnings and rendered nothing: a `Row` positions its own
children and **rejects anchors** on them. Every setting row is an `Item` now,
which is also what the shell's own panels do.

This is worth remembering generally, not just here — it is an easy trap
because a `Row` looks like the right container for "label on the left, control
on the right".

### Labels were silently eliding

The first labels were too long for the space left by the control. Measuring the
rendered binding:

| Label | implicitWidth | available | elided |
|---|---|---|---|
| `Interval, all online (s)` | 173 | 136 | **yes** |
| `Interval, incident open (s)` | 194 | 136 | **yes** |
| `Interval, healthy` → `Healthy poll (s)` | 115 | 136 | no |
| `Interval, incident` → `Incident poll (s)` | 122 | 136 | no |
| `Notify on recovery` | 129 | 202 | no |
| `Count in tooltip` | 115 | 202 | no |

A screenshot alone would never have shown this — the elided text just looked
short. The fix was structural, not cosmetic: every label is **bounded by its
control** and set to `Text.ElideRight`, so overlap is impossible by construction
under any theme font size.

```qml
Text {
  anchors.left: parent.left
  anchors.right: healthyField.left
  anchors.rightMargin: Style.space(12)
  elide: Text.ElideRight
  ...
}
```

Measuring the pixel gap between label and control initially showed only ~2
logical pixels. That number was misleading — see section 10.

---

## 10. Verification methodology, and its traps

The panel is nearly impossible to verify by eye, because the popup background
and a dark wallpaper are both near-black. The techniques that worked, and the
ways they lied:

### What worked

| Technique | Use |
|---|---|
| Temporary `console.warn` of a resolved binding | Proves the actual value, immune to rendering |
| Temporary `Timer` calling `root.open()` | Reproduces the panel without clicking |
| Temporary `Rectangle` at `panel.contentWidth x contentHeight` | Exact card bounding box |
| **Raw pixel analysis, no colour masking** | Ground truth for rendered geometry |

`omarchy plugin validate .` plus a journalctl sweep is a necessary minimum, not
a sufficient one. It reports no QML warnings and the panel can still be broken.

### Screenshots come back at scale 2

A 1500x1000 logical screen yields a 3000x2000 PNG. Halve any pixel bounding
box before comparing it to a logged logical value.

### Trap 1 — a masking probe can hide real content

The `geomProbe` rectangle was painted `magenta` to get an exact card bbox by
`-opaque` masking. The three toggle switches then measured as **15x16 logical**
for the two `checked` rows and **42x22** for the unchecked one — which looked
like a real layout bug.

It was not. The mask was swallowing the theme's **accent-coloured switch
track**, because the accent is magenta-ish under a 12% fuzz. Recolouring the
probe `blue` reproduced the same wrong result, because the accent matched that
too.

Measured against **raw pixels** with no masking at all, all three switches are
identical: 42 logical wide, 20–22 tall, at the same trailing x position.

**Lesson: a debugging overlay can become the thing you are measuring. When
instrumented and uninstrumented geometry disagree, believe the raw pixels.**

### Trap 2 — a passing test that proved nothing

The first pause test waited 22 seconds and observed no polls while paused. That
result is worthless: the healthy interval is **300 seconds**, so no poll would
have happened anyway.

The retest forced polls to be *due* by zeroing `lastPollAt` while paused:

```
POLL paused=false t=...047      startup poll
paused + poll FORCED due        lastPollAt=0, poll due
still paused, poll FORCED due again
                                ^ no POLL between these two lines
unpaused (no force)             lastPollAt never touched
POLL paused=false t=...069      2s later, unprompted
```

Two forced-due attempts while paused were both refused; unpausing with no nudge
produced a poll 2 seconds later. That is the whole requirement, proven.

**Lesson: check that a negative result is possible at all before trusting it.**

### Trap 3 — screen-scraping the whole screen for "is the panel open"

Counting green bands to confirm the panel was closed reported 8 bands instead
of 1, and looked like a stuck panel. The cause was unrelated windows: a `foot`
terminal and a Chromium window both contain green pixels.

The correct check is a window query, not a pixel count:

```bash
hyprctl clients -j | python3 -c "
import json,sys
for w in json.load(sys.stdin):
    if 'quickshell' in ((w.get('class') or '')+(w.get('title') or '')).lower():
        print(w.get('class'), w.get('at'), w.get('size'))
"
```

### Instrumentation hygiene

All temporary code — `dbgA`/`dbgB` timers, `geomProbe`, `ESO-DBG` warnings,
`ESO-LABEL` measurements — was removed before every commit. Verify with:

```bash
grep -rn "ESO-DBG\|geomProbe\|dbg\|console.warn" *.qml   # must return nothing
```

**A debug probe left in the tree will write to the user's real config.** This
happened for real: the pause test persisted `{"id": "murankar.eso-server-status",
"paused": true}` into `~/.config/omarchy/shell.json` through the real
`updateEntryInline` path. It had to be reset to `false` by hand afterwards, or
the user would have been left with polling switched off. **After any test that
touches settings, inspect `shell.json` and reset the state it left behind.**

---

## 11. Deliberate non-decisions

Things not done, on purpose. Do not "fix" these without asking.

- **No keyboard navigation between tabs.** The pills are clickable `Button`s
  but not focusable in a tab order. The shell's panel conventions do not
  require it and no user asked for it.
- **No tooltips on the settings controls.** The labels are self-describing
  (`Healthy poll (s)`) and the README documents each key.
- **Panel width not widened to fit longer labels.** Widening to ~340 logical
  would have fit `Interval, all online (s)`, but then the card would resize
  between tabs. Shorter labels plus elision was the better trade.
- **No dedicated "paused" glyph of its own.** A paused glyph is drawn in the
  plain bar foreground, identical to a stale one. See section 8.1 for why that
  is deliberate and what it costs.
- **Marketplace submission still on hold.** A Chromium tab titled
  "Publish a Plugin" is open locally; nothing has been filed and nothing should
  be without fresh approval.
- **No git tag cut.** The manifest is at `1.2.0` for the panel work, but no
  tag has been pushed. Bumping the manifest and tagging the commit are separate
  acts; only the first has been done.

---

## 12. Open items and suggestions

| # | Item | Priority |
|---|---|---|
| 1 | Keyboard focus order for the tab pills | Low |
| 2 | A distinct glyph for paused vs. stale (e.g. a hollow dot) | Low — see section 8.1 |
| 3 | `NumberField` values are read-only until edited; no reset-to-default | Low |
| 4 | Cut a `1.2.0` git tag and push it (the manifest version is already bumped) | Needs a decision |
| 5 | Back up the untracked notes outside the plugin directory before any `omarchy plugin remove` | **Do this first** |

Item 5 is not a suggestion about the panel, but it applies to this file:
`omarchy plugin remove` deletes the install directory outright, which silently
destroys every untracked note in it.

---

## 13. Reproducing the verification

```bash
cd ~/.config/omarchy/plugins/murankar.eso-server-status

# 1. Manifest and metadata are valid
omarchy plugin validate . ; echo "exit: $?"

# 2. No QML errors or warnings after a reload
MARK=$(date +%T); omarchy restart shell; sleep 26
journalctl --user --since "$MARK" | grep -i eso-server-status | grep -viE reloading
# expect: no output

# 3. No instrumentation left behind
grep -rn "ESO-DBG\|geomProbe\|dbg\|console.warn" *.qml
# expect: no output

# 4. Panel is closed on a clean start, and no panel window exists
pgrep -af quickshell
hyprctl clients -j | grep -i quickshell
# expect: no panel-sized window

# 5. Settings were not left mutated by testing
python3 -c "
import json,io
d=json.load(io.open('$HOME/.config/omarchy/shell.json'))
for e in d['bar']['layout']['right']:
    if e.get('id')=='murankar.eso-server-status': print(json.dumps(e))
"
# expect: {\"id\": \"murankar.eso-server-status\", \"paused\": false}

# 6. Anonymous clone matches the pushed head
git clone --depth 1 git@github.com:murankar/omarchy-eso-server-status.git /tmp/opencode/verify-clone
```

### Verifying the panel visually at all

The panel cannot be opened by clicking in a headless or scripted session. The
reliable recipe is a temporary timer in `Panel.qml`, which must be removed
before committing:

```qml
Timer { interval: 6000; running: true; repeat: false
        onTriggered: { root.open(); root.tab = 1 } }
Rectangle { id: geomProbe; width: panel.contentWidth
            height: panel.contentHeight; color: "magenta" }
```

Capture with `grim`, then analyse the **raw** pixels — do not mask by the probe
colour, for the reason in section 10.

---

## 14. Quick orientation for a new agent

If you are picking this up cold, in this order:

1. `Panel.qml` from line 110 — the `KeyboardPanel`, its sizing, and the inset
   comment at lines 133-135. That comment prevents the `0448e96` bug returning.
2. `Panel.qml` line 57 — `setSetting()`, the three-way write.
3. `Service.qml` lines 41-49 (`paused` and the forced refresh) and line 81
   (the gate inside `maybePoll`).
4. Section 10 of this file — before you trust any visual verification.
5. `ProjectNotes-BaseApp.md` — the base plugin, request budget, and theming.
