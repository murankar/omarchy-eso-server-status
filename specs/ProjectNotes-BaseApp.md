# Project Notes — ESO Server Status Base App

**Purpose of this document.** A complete, self-contained handoff. If this session
is lost, point a fresh agent at this file alone. It should contain everything
needed to understand what was built, why each decision was made, what was tried
and abandoned, and how to verify the current state. No prior context assumed.

**Scope.** Two deliverables were produced in this session:

| # | Deliverable | State |
|---|---|---|
| 1 | Workspace 1 forced to scrolling layout (Hyprland) | Complete, persisted |
| 2 | `eso.server-status` — an Omarchy shell plugin | Complete, verified, pushed |

Deliverable 2 is the "base app." It is finished and working. Everything below
about the plugin is the current, shipped state, not a plan.

---

## 1. Quick facts

| | |
|---|---|
| **Plugin name** | ESO Server Status |
| **Plugin id** | `murankar.eso-server-status` |
| **Install location** | `~/.config/omarchy/plugins/murankar.eso-server-status/` |
| **Version** | `1.2.0` |
| **Git remote** | `git@github.com:murankar/omarchy-eso-server-status.git` (GitHub only) |
| **Repository URL** | https://github.com/murankar/omarchy-eso-server-status |
| **Current branch** | `dev` (local + remote) |
| **Default branch** | `main` (local + remote) |
| **Head commit** | `8beba37` — identical on `main` and `dev` |
| **Files tracked** | `.gitignore`, `BarWidget.qml`, `Service.qml`, `Theme.js`, `manifest.json`, `README.md` |
| **This file** | `ProjectNotes-BaseApp.md` — intentionally untracked |

### Environment (verified 2026-09-29)

| Component | Version |
|---|---|
| Omarchy | `4.0.4-1` |
| Quickshell | `0.3.1` (Arch) |
| Hyprland | `0.56.2` |
| curl | `8.22.0-1` |
| Stock themes present | 22, each with a `colors.toml` |

### Runtime dependencies

All present and confirmed on the target machine:

- `curl` (`/usr/bin/curl`) — the plugin shells out for every poll
- `omarchy-launch-browser` (`/usr/share/omarchy/bin/`)
- `omarchy-notification-send` (`/usr/share/omarchy/bin/`)
- `quickshell` (`/usr/bin/quickshell`)
- Outbound HTTPS to `esoserverstatus.net`
- A Nerd Font covering **U+EB50** for the glyph

No build step, no package install, no API key.

---

## 2. Deliverable 1 — workspace 1 scrolling layout

Persisted to `/home/uri/.local/state/omarchy/workspace-layouts/1.lua`:

```lua
hl.workspace_rule({ workspace = "1", layout = "scrolling" })
```

Applied and verified with `hyprctl reload`; `hyprctl configerrors` reports
clean. This is a small standalone change, unrelated to the plugin, included
here only so the record is complete.

---

## 3. The data source

The plugin reads the same public JSON endpoint the website's own page uses.
No authentication.

**Endpoint**

```
GET https://esoserverstatus.net/api/refresh
```

**Required request headers** (the site is a Laravel/XHR endpoint and behaves
differently without them)

```
X-Requested-With: XMLHttpRequest
Accept: application/json
```

**Response shape** — a `servers` object with 7 keys:

```json
{ "servers": { "PC-EU": true, "PC-NA": true, ... } }
```

Keys: `PC-EU`, `PC-NA`, `PC-PTS`, `XBOX-EU`, `XBOX-NA`, `PS4-EU`, `PS4-NA`.

**Value semantics — this is the important detail:**

| Value | Meaning | Counts as online? |
|---|---|---|
| `true` | Online | Yes |
| `false` | Offline | No |
| `2` | "Ongoing issues" | **No** — by design |

The `2` is the subtle one. It is deliberately *not* treated as online, so a
server with a reported problem produces an **orange** reading rather than a
misleading green. Only a literal boolean `true` counts as online.

**Status derivation**

```
online === total  ->  "green"
online === 0      ->  "red"
otherwise         ->  "orange"
```

**Push was investigated and rejected.** The site does expose a WebSocket, but
it is an opt-in *announcement log* (maintenance notices), not a status feed. The
site's own browser client polls on a 60-second `setInterval`. Responses carry
`Cache-Control: no-cache, private` and **no ETag**, so every poll is a genuine
origin hit, and each response sets a Laravel session cookie. Conclusion: polling
is the only correct mechanism, and it must be frugal.

---

## 4. Architecture

```
Service.qml     one per shell process. Owns the Process, the Timer, all state,
                backoff, and the recovery notification. The ONLY network owner.
BarWidget.qml   one per bar surface. Renders, handles input, reads published
                state. Contains no Process and no network code whatsoever.
Theme.js        Hue-aware colour selection from the active theme's palette.
manifest.json   Plugin metadata, kinds, entry points, settings schema.
```

### Why the service/widget split

This is the central design decision and the reason the plugin is cheap.

Omarchy instantiates a `service` exactly **once per shell process**. A bar
widget may be instantiated **once per monitor**. Putting the poller in the
service means a three-monitor setup still makes **one** request per interval,
not three. The widget is a pure observer of state the service publishes.

Verified mechanically: `grep -nE "Process \{|StdioCollector|curl" BarWidget.qml`
returns nothing.

This mirrors the existing `omarchy.media` plugin, which uses the same
service-plus-observer pattern.

### How the widget reaches the service

```qml
readonly property var service: {
  var api = root.bar ? root.bar.shell : null
  return api ? api.serviceFor("eso.server-status") : null
}
```

Third-party bar widgets receive a `bar` object exposing `shell`, which is
scoped to the plugin's *own* service id. `BarWidget.qml` pushes user settings
into the service via `root.service.settings = root.settings` from
`onSettingsChanged`, `onServiceChanged`, and `Component.onCompleted`.

### `keepLoaded: true`

Declared in `manifest.json`. It keeps the service mounted so that editing and
hot-reloading the bar widget cannot orphan the live service object that
`BarWidget.qml` holds a binding to.

**Trade-off, and it is a real one:** the consequence is that changes to
`Service.qml` need `omarchy restart shell` rather than the usual automatic
reload. Bar-widget changes still hot-reload on save.

---

## 5. The request budget

ESO outages are rare and long. A healthy machine has no reason to poll often,
and the frequent cadence should be spent only during the window where a user
actually wants freshness — while waiting for recovery.

| Situation | Interval | Requests/day |
|---|---|---|
| All servers online | 300s (`healthyInterval`) | 288 |
| Incident open | 60s (`alertInterval`) | 1440 |
| Endpoint unreachable | 60 → 120 → 240 → 480 → 600s | 144 |

Backoff formula, capped:

```js
var backoff = 60 * Math.pow(2, Math.min(failures - 1, 10))
return Math.min(backoff, 600)
```

Verified sequence: `60, 120, 240, 480, 600, 600, …`

**Middle click bypasses the interval** by setting `service.lastPollAt = 0`; the
2-second tick then polls on the next pass.

### Staleness honesty

If a poll fails, the last known status is **kept** so the bar still renders
something, but `stale` flips true and the widget drops to the neutral
foreground colour. A dead endpoint must never be able to read as "all clear."

The widget is also `visible: status !== ""`, so it is entirely hidden until the
first successful response — it never appears as a meaningless empty slot during
startup.

---

## 6. Theming — the discovery that shaped `Theme.js`

Omarchy themes expose a named palette in `colors.toml`, **but the names are not
reliably semantic.** Reading `green` directly produces visibly wrong results on
several stock themes:

| Theme | What is actually named `green` |
|---|---|
| `lumon` | blue |
| `lupine` | purple |
| `white` | grey |
| `matte-black` | amber |

So `Theme.js` parses the active palette and selects the first candidate whose
**measured hue** lands in the required band, rather than trusting the key name.
A theme with no usable green falls back to a fixed hue-correct constant instead
of rendering something wrong.

**Hue bands (degrees, wrapping around 0):**

```js
green:  [[78, 168]]
orange: [[18, 58]]
red:    [[345, 360], [0, 14]]
```

**Candidate keys, in priority order** — first *hue-correct* hit wins:

| Band | Candidates | Fallback |
|---|---|---|
| green | `green`, `bright_green`, `color2`, `color10`, `color42` | `#26a269` |
| orange | `orange`, `bright_orange`, `accent`, `yellow`, `bright_yellow`, `color3`, `color11`, `color214` | `#e69138` |
| red | `red`, `bright_red`, `color1`, `color9`, `color88` | `#dc3545` |

`hueOf()` returns `-1` for near-grey colours (`d < 0.04`), where hue is
meaningless and the candidate is correctly rejected.

**Live theme switching works.** The palette is read via a `FileView` on
`~/.local/state/omarchy/current/theme/colors.toml` with `watchChanges: true`.

**Verification method** — `Theme.js` is plain JS with no Qt dependencies, so it
can be exercised directly under Node against every stock theme's `colors.toml`.
All 22 stock themes were checked and produce a correct green, orange, and red.

> Correction worth carrying forward: this work was previously described as
> "21 stock themes." The accurate count is **22** (all 22 directories in
> `/usr/share/omarchy/themes/` contain a `colors.toml`).

---

## 7. User-facing behaviour

| Input | Result |
|---|---|
| Hover | Tooltip: `ESO Server Status`, or `ESO Server Status - 6/7 online` when `detail` is on |
| **Left click** | Opens `https://esoserverstatus.net/` via `omarchy-launch-browser` |
| **Middle click** | Forces an immediate re-poll |
| Any other button | Falls through to the left-click action (open site) |

**Icon:** U+EB50 (`\ueb50`), declared in `BarWidget.qml` and reused as the
notification icon in `Service.qml`.

### Settings schema

Stored in `~/.config/omarchy/shell.json`, editable from the shell settings panel.

| Key | Type | Default | Effect |
|---|---|---|---|
| `healthyInterval` | number | `300` | Seconds between polls while all online |
| `alertInterval` | number | `60` | Seconds between polls during an incident |
| `notifyRecovery` | boolean | `true` | Notify on transition back to all-green |
| `detail` | boolean | `false` | Append ` - N/7 online` to the tooltip |

The recovery notification is suppressed on first load (`everReported` gate) so
it cannot fire spuriously at startup. It only fires on a genuine
**non-green → green** transition.

---

## 8. Everything that was tried, and what failed

This is the section most worth preserving. Several of these cost real time.

### 8.1 The wrong diagnosis (important — do not repeat)

When the first service-based version produced no data, the cause was diagnosed
as *"a `Process` will not spawn inside a parentless third-party service."*

**That was wrong, and it was asserted too confidently.** There is no such
Quickshell limitation. The actual cause was that the `command:` property had
been dropped from the `Process` element during a rewrite. A `Process` with no
`command` never runs.

Lesson applied for the rest of the build: a render that is "present but inert"
should be proved wrong or right by instrumenting the actual data path
(`console.warn` in `settle()`, then in the widget) rather than by theorising
about framework behaviour.

### 8.2 Abandoned architecture — per-widget polling

The first working version put the `Process` and polling `Timer` directly in
`BarWidget.qml`. It rendered correctly, but it meant **one request per bar
surface per interval** — a 3× request multiplier for multi-monitor users, which
directly contradicted the anti-flood goal.

Replaced with the service/widget split described in §4. `Shared.js`, a helper
module created for the per-widget design, was left behind and subsequently
deleted as dead code.

### 8.3 Bugs encountered and fixed

| Symptom | Root cause | Fix |
|---|---|---|
| No polling at all | `Process` missing its `command:` property | Restored `command:` |
| Widget loads, renders nothing | Root `Item` missing `implicitWidth`/`implicitHeight`; the `anchors.fill: parent` button collapsed to zero size | Added both, propagating from `button.implicitWidth/Height` |
| `FileView is not a type` | Missing import | `import Quickshell.Io` |
| `Property value set multiple times` | Duplicate `onExited` handler left in during debug instrumentation | Restored clean file from backup |
| `File name case mismatch` | Stale shell plugin cache after a manifest change | `omarchy restart shell` |
| Service never instantiated | Manifest declared only `kinds: ["bar-widget"]`, no `entryPoints.service` | Added the `service` kind and entry point |

The zero-size bug was the most misleading: the widget was found, the service
was found, `status` was correctly `"green"`, and the shell logs were completely
clean — and yet nothing appeared in the bar. A bound `readonly property` and
correct state are not sufficient; the item still needs an explicit size.

### 8.4 Friction worth knowing

- `omarchy plugin enable eso.server-status --yes` — `--yes` is not a valid
  option for `enable`; it errors with `unknown placement option: --yes`. The
  plugin is enabled regardless, but use the documented form.
- One-off services are re-created on `rescanPlugins`, which invalidates a
  widget's `service` binding. This is why `keepLoaded` is set.

---

## 9. Verification recipes

These are the checks that were actually used, all of which passed.

**Manifest is valid**

```bash
omarchy plugin validate ~/.config/omarchy/plugins/eso.server-status
```

**Reload after service changes**

```bash
omarchy restart shell
```

**Watch for load/poll errors**

```bash
journalctl --user -f | grep eso
```

A widget that fails to load appears as `Plugin widget eso.server-status failed`
with the underlying QML error. **A completely clean log does not mean success** —
see the zero-size bug in §8.3.

**Confirm the glyph actually rendered** (this catches the zero-size class of bug
that logs cannot)

```bash
cd /tmp/opencode
grim -g "0,0 3000x38" eso.png
magick eso.png -depth 8 txt:- | python3 -c "
import sys,re
g=[]
for line in sys.stdin:
    m=re.match(r'(\d+),(\d+):\s*\((\d+),(\d+),(\d+),(\d+)\)',line)
    if not m: continue
    x,y,r,gg,b,a=map(int,m.groups())
    if a>200 and gg>r+25 and gg>b+15 and gg>90: g.append((x,y,r,gg,b))
print('green glyph pixels:', len(g))
if g: print('brightest RGB:', max(g,key=lambda p:p[3])[2:])
"
```

Expected and last measured: **163 green pixels, brightest `(38, 162, 105)` =
`#26a269`**, at logical x ≈ 1315–1324 on the right-hand bar section.

**Confirm the widget owns no network** (the anti-flood invariant)

```bash
grep -nE "Process \{|StdioCollector|curl" ~/.config/omarchy/plugins/eso.server-status/BarWidget.qml
# must return nothing
```

**Confirm state mapping without waiting for a real outage** — feed crafted
payloads through `apply()`; the mapping is the simple three-way branch in
`Service.qml` §3. All-online → green, all-offline → red, any mix → orange,
and a `2` value must land on orange.

---

## 10. Git and distribution state

| | |
|---|---|
| Remote | `git@gitlab.com:urix3/omarchy-eso-server-status.git` |
| Branches pushed | `main`, `dev` — both at `d9694bc` |
| `git user.name` | `Matthias Urankar` |
| `git user.email` | `murankar@proton.me` |
| SSH auth | `ssh -T git@gitlab.com` → `Welcome to GitLab, @urix3!` |

`main` was fast-forwarded to `dev` before the first push, because `main` still
carried the pre-managed-install README at that point and is the branch end users
clone.

### Open item — repository visibility

**The GitLab project was created PRIVATE by the initial push.** This was
confirmed by attempting an anonymous HTTPS clone, which failed:

```
fatal: could not read Username for 'https://gitlab.com'
```

Consequences until this is fixed:

- The install command in `README.md` does not work for anyone else.
- The failure is **hard**, not a password prompt, because `omarchy-plugin-add`
  sets `GIT_TERMINAL_PROMPT=0`, so non-interactive users get an immediate error.

**To resolve:**

> https://gitlab.com/urix3/omarchy-eso-server-status
> → Settings → General → Visibility, features and permissions
> → Project visibility → **Public**

This was deliberately **not** automated. `glab` is not installed, it would
require a personal access token, and flipping a repository to public is not an
action to take unattended.

---

## 11. How `omarchy plugin add` / `update` actually work

Read from `/usr/share/omarchy/bin/omarchy-plugin-add` and
`omarchy-plugin-update` rather than assumed — these details determine whether
the auto-update story holds.

**`omarchy plugin add <git-url> --enable`**

1. Clones to a staging dir, runs `omarchy-plugin-validate` on it.
2. Refuses if the plugin id is already present in `plugins/`.
3. Moves into `~/.config/omarchy/plugins/<manifest-id>/`.
4. Runs `omarchy-shell shell rescanPlugins`.
5. With `--enable`, prompts for a bar section, defaulting to the manifest's
   `barWidget.defaultSection` (here: `right`).
6. Warns first that shell plugins are unsandboxed code inside the long-lived
   `omarchy-shell` process.

**`omarchy plugin update [id]`**

- Discovers managed plugins purely by the presence of a **`.git` directory** in
  each plugin folder. No separate registration exists — this is why the managed
  install is what makes updates work.
- `git fetch origin HEAD`, shows the diff, asks to confirm.
- **`git merge --ff-only FETCH_HEAD`** — fast-forward only. Local commits in
  the installed copy cause a refusal, not a clobber.
- Re-validates the manifest afterwards and **rolls back** on failure.
- Runs `rescanPlugins` only if something actually updated.

**Two consequences for the ongoing workflow:**

1. `main` is the default branch, so updates fast-forward from `origin` HEAD =
   `main`. **A commit that exists only on `dev` will never reach users.** Merge
   `dev → main` before anything should be published.
2. Because the plugin is `keepLoaded`, run `omarchy restart shell` after an
   update for `Service.qml` changes to take effect. `omarchy plugin update`
   does not do this for you.

---

## 12. Known open items and loose ends

| # | Item | Severity |
|---|---|---|
| 1 | **Repo is private — must be made public** or the README install command is non-functional for users | High |
| 2 | ~~README install URLs contain the placeholder `YOUR-ACCOUNT`~~ — **resolved**, now `urix3` | Closed |
| 3 | `manifest.json` `author` is `"uri"` (the machine username), not a real name | Cosmetic |
| 4 | `manifest.json` `version` is `1.2.0`; still no git tag has been cut on the remote | Low |
| 5 | Bar content only renders in the left half of the right-hand section — pre-existing Omarchy behaviour, confirmed identical with the plugin disabled, **not** caused by this plugin | Informational |
| 6 | Local commits in an installed copy will block `omarchy plugin update`; documented in the README | Informational |
| 7 | This notes file is gitignored by request, so it exists only on this machine | Informational |

### Not yet built

Nothing was deferred that the current requirements ask for. Plausible future
work, in rough priority order:

- Per-server breakdown in the tooltip (currently only an `N/7` count)
- Historical uptime sparkline or flapping detection
- Additional status sources as a sibling plugin sharing the same polling
  architecture

---

## 13. Quick orientation for a new agent

Read in this order if picking the project up cold:

1. **This file** — the map.
2. `manifest.json` — the contract: kinds, entry points, settings schema, and
   `keepLoaded`.
3. `Service.qml` — all networking and state. §3 and §5 above explain every
   branch.
4. `BarWidget.qml` — rendering and input only. Note §8.3's zero-size trap.
5. `Theme.js` — self-contained, runnable under Node, testable without the shell.
6. `README.md` — the user-facing document already written for this plugin.

**The single most important invariant to preserve:** `BarWidget.qml` must never
contain a `Process` or a `curl` call. If a future change moves polling into the
widget, the request count silently multiplies by the number of monitors and the
entire anti-flood design is lost. The grep in §9 exists to catch that.


---

## 14. Addendum — the id rename (post-session)

The plugin id was changed from `eso.server-status` to
`murankar.eso-server-status`, and GitLab was dropped as an upstream.

### The trap worth remembering

**Renaming the plugin id means the string appears in QML, not just config.**

`BarWidget.qml` hardcodes the id twice:

```qml
moduleName: "murankar.eso-server-status"
api.serviceFor("murankar.eso-server-status")   // look up OUR service
```

A find-and-replace confined to `README.md` and `manifest.json` left both QML
occurrences on the old id. The failure mode is unusually nasty:

- the service registered under the **new** id
- the widget asked for the **old** id, got `null`
- `status` stayed `""`, so `visible: status !== ""` kept the widget hidden
- the shell log was **completely clean** — no QML error, no warning

`omarchy plugin list` reported `enabled=true` and the catalog resolved the
widget path correctly, so every cheap check passed. Only a pixel check of the
rendered bar caught it. The glyph returned to `#26a269`, 163 pixels, at logical
x 1315-1324, once both QML strings were updated.

**Before ever changing a plugin id, grep the QML as well as the docs:**

```bash
grep -rn "<old-id>" --include="*.qml" --include="*.js" --include="*.json" --include="*.md" .
```

### Two more migration steps that are easy to miss

1. **`~/.config/omarchy/shell.json` hardcodes the id in the bar layout.** Left
   stale, the widget silently disappears from the bar while still being
   installed and enabled. `omarchy plugin remove` disables the entry but does
   not delete it, so a leftover entry needs removing by hand:

   ```bash
   jq '(.bar.layout.right) |= map(select(.id != "<old-id>"))' \
     ~/.config/omarchy/shell.json > /tmp/s && jq empty /tmp/s \
     && mv /tmp/s ~/.config/omarchy/shell.json
   ```

2. **The install directory is named after the id**, because
   `omarchy plugin update` resolves `$PLUGINS_DIR/$id`. A mismatched directory
   name means updates stop working while everything else still appears fine.
   The clean path is `omarchy plugin remove <old-id>` then
   `omarchy plugin add <url> --enable --yes`, which recreates the correct
   layout from scratch.

### Local notes are gitignored — back them up before a reinstall

`TODO.md` and this file are untracked by design. `omarchy plugin remove`
deletes the install directory outright, which silently destroys them. Copy both
somewhere outside the plugin directory **before** any remove/reinstall cycle.

---

## Addendum: per-server panel (2026-09-29)

> This addendum covers the panel's first commit only. The full panel
> effort — the border fix, the right-aligned status, the Servers/Settings
> tabs, and the pause switch — is documented in
> `ProductionNotes-AddPanel.md`.

Shipped as `94bc2ab` on `dev`, fast-forwarded to `main`, pushed to GitHub.

Left click toggles a popout listing all seven servers with individual state
colours. Right click still opens the site; the panel has its own link.

Three things that are not obvious from the code:

1. **`centerOnBar: true` centres on the whole bar, not the anchor.** With a top
   bar that puts the panel at screen centre instead of under the bar entry.
   `centerOnBar: false` makes `cardOrigin` use `anchorScreenPos`. The shipped
   panel uses `false`.

2. **`panel.width`/`panel.height` are the layershell window, not the card.** The
   window is 500x500 while the visible card is `contentWidth x contentHeight`
   (300x375). Log the latter when checking geometry.

3. **Do not verify this panel by filtering screenshot colours.** The popup
   background and a dark wallpaper are both near-black and pixel heuristics
   produce false results in both directions. What actually worked: a temporary
   magenta `Rectangle` sized to `panel.contentWidth/Height` for an exact bbox,
   and a per-row `console.warn` of the resolved binding to prove the colours.
   Both were removed before commit. Note screenshots are captured at scale 2, so
   halve any pixel bbox before comparing it to logged logical values.

`serverList` is reassigned wholesale rather than mutated, because a QML property
holding an array only notifies bindings when the reference itself changes.

### Follow-up: the popup inset gotcha (`0448e96`)

The status word was being split by the card border. Root cause was not the
text anchoring: `KeyboardPanel` lays children out inside a `contentHolder`
already inset by `padding + border` (`Style.spacing.popupPadding` = 14, plus a
2px border, so 16 logical per side), but the body `Column` was sized to
`panel.contentWidth` — the *full* card width. The column therefore overflowed
~32px to the right and the border ran through the glyphs.

Size popup content to the inset area, not the card size:

```qml
Column { width: parent.width }   // parent is contentHolder, already inset
```

The status is now anchored after the server name instead of to the right edge,
which also leaves room for the wider "ongoing issues" label.

Related: `panel.width`/`panel.height` are the layershell *window*, not the
card. The card is `contentWidth x contentHeight`. Three different widths are in
play here — do not assume they match.
