# Code Review — ESO Server Status

Private working note. Not published: listed in `.gitignore` alongside the other
`ProjectNotes-*` files, because it names defects in a plugin that is on its way
to a public marketplace.

| | |
|---|---|
| **Plugin** | `murankar.eso-server-status` v1.3.0 |
| **Reviewed revision** | `f13906f` ("Bump version to 1.3.0") plus the uncommitted `Service.qml` / `.gitignore` working-tree changes |
| **Status** | Both HIGH and all three MEDIUM findings **fixed in the working tree, uncommitted**, along with LOW-7 and OPTA-3. Nine LOW findings, the nits, and OPTA-1/2/4 remain. See [Applied corrections](#applied-corrections) and [Performance round](#performance-round--one-applied-three-proposed). |
| **Scope** | Full plugin: `Service.qml`, `Panel.qml`, `BarWidget.qml`, `Servers.js`, `Theme.js`, `manifest.json` |
| **Excluded** | `README.md`, `MARKETPLACE-SUBMISSION.md`, `ProjectNotes-*.md`, `ProductionNotes-*.md`, `TODO.md`, `preview.png`, `LICENSE`, `docs` — read only where a claim in them contradicts the code |
| **Environment** | Omarchy on Arch, `curl 8.22.0`, Quickshell `qs` |
| **Line numbers** | Cite the reviewed revision, not the working tree. Fixes in *Applied corrections* have moved them. |

---

## Verdict

Close to ship, and unusually careful for a first release — the request budget,
the backoff, the duck-typed cross-realm array handling and the "never claim a
freshness you do not have" UI discipline are all sound and all deliberate.

Two things block publication:

1. **A remote-input bug with teeth.** Server names from the API are rendered in
   `Text` items that never set `textFormat`, so Qt 6 treats them as **rich
   text**. The endpoint can inject `<img src="http://attacker.example/">` and
   the rich-text loader **fetches it** — confirmed live against a local beacon.
   That is an outbound request to an attacker-chosen host, once per poll, from a
   long-lived privileged process, with no user interaction. It also falsifies the
   README's central privacy claim.
2. **A logic inversion in the recovery notification.** It fires during an
   outage and stays silent on the real recovery. Every incident, both
   directions, the one user-facing push notification says the opposite of the
   truth.

Three medium findings follow from the same threat model the uncommitted
`--max-filesize` change adopts: unbounded server count, a poll latch that cannot
be cleared, and a settings write per keystroke.

The uncommitted `--max-filesize` change itself is **correct and load-bearing** —
measured, not assumed. See [The uncommitted change](#the-uncommitted-change) and
[the corrected comment](#the-comment-corrected).

Both HIGH findings, all three MEDIUM findings, and LOW-7 are **fixed in the
working tree and uncommitted**. What is left is below.

---

## Still to address

The outstanding work, in the order I would do it. Nothing here blocks
publication; LOW-1 is the only one with a measurement behind it, and LOW-2 and
LOW-3 are the two a reviewer will actually notice. (Correctness only — the
read-only performance pass is in
[Performance round](#performance-round--one-applied-three-proposed): OPTA-3 is
applied, OPTA-1/2/4 are not.)

| | Item | Why it is still open | Effort |
|---|---|---|---|
| ☐ | **LOW-1** — `bar.barForeground` → `barForeground` in 23 places | **18 `TypeError`s per panel construction**, measured. A `sed`, and it is the only remaining finding with evidence rather than reasoning. | trivial |
| ☐ | **LOW-2** — `switchPanel` never overridden | Panel-switch keys do nothing. Four lines, copied from `clock/Panel.qml:113-117`. | trivial |
| ☐ | **LOW-3** — no `ipcTarget` | `omarchy shell summon\|hide\|toggle murankar.eso-server-status` does nothing. One line. | trivial |
| ☐ | **LOW-6** — `~/.curlrc` not disabled | Add `-q`. Until then the README's "certificate verification stays enabled" is a claim about the *user's* rc, not about the plugin. | trivial |
| ☐ | **LOW-4** — `apply()` accepts an array as `servers` | `{"servers":[true,false]}` renders two rows named `0` and `1`. Add `Array.isArray`. | one line |
| ☐ | **LOW-5** — `mutedServers` never pruned | Grows monotonically in `shell.json`; a dropped server returns pre-muted. | small |
| ☐ | **LOW-8** — `manifest.json:18` hardcodes "all 7 servers" | Marketplace-visible; goes stale on the next fleet change. | one line |
| ☐ | **LOW-9** — `property var shell` unused; settings channel undocumented | Real coupling: with no widget in the bar, the service polls on hardcoded defaults. Comment it or drop it. | small |
| ☐ | **LOW-10** — `README.md:216` says four settings, there are five | Self-contradicting within two lines of itself. | one line |
| ☐ | **Nits** (7) | Unused `index` property, one misindented `Text`, the `siteLink` anchors, hardcoded plugin id in `BarWidget.qml`, `toRgb` ordering. See [Nits](#nits). | trivial each |

**Deliberately not done, and worth a decision rather than a fix:**

- The **switchPanel** and **ipcTarget** gaps are the kind of thing stock panels
  simply do not have. If the plugin is going to the marketplace, both are what a
  reviewer compares against.
- **LOW-5** is a design question, not a bug: whether a muted server the site has
  dropped should stay in the list is a policy call, and the current behaviour
  (keep it, so it returns pre-muted) is defensible. It only needs to be a
  decision on record.

Also outstanding, and not a code finding: `omarchy restart shell` has to be run
before any of this is live, because `keepLoaded: true` keeps the service alive
across a hot-reload. See [Applied corrections](#applied-corrections).

## Must fix before publishing

### HIGH — Remote payload can render as rich text and beacon to arbitrary hosts

**`Panel.qml:402`, `Panel.qml:473`** · source `Service.qml:169` → `Panel.qml:55`
→ `Servers.js:48-52`, `Servers.js:61-64`

Server names are `Object.keys(servers)` taken verbatim from the response
(`Service.qml:169`, pushed at `Service.qml:180-183`) and end up as `text:` on
`Text` items that never set `textFormat`. Qt 6's default is `Text.AutoText`,
which **renders as rich text**. Measured in a `qs` harness:

```
AUTO   width=81.84   (== RichText)
PLAIN  width=196.69
RICH   width=81.84
```

**The fetch is real.** A `qml6` window with two `Text` items, identical hostile
strings, one left at the default and one set to `PlainText`, against a local
server that logs every path it is asked for:

```
qml6 exit=0
=== beacon hits ===
HIT /beacon-auto.png
```

One hit, and it is the `AutoText` item's. The `PlainText` item made no request
at all — which is the fix, demonstrated rather than argued.

**Trigger.** The endpoint returns
`{"servers":{"<img src=\"http://attacker.example/beacon?x\">":true}}`.
`Servers.split` finds no `-`, returns `null`, so `Servers.label()` returns
`String(name)` verbatim → one delegate at `Panel.qml:473`. Equally reachable
through a heading: `x-EV<img src="…">` → `Servers.groupLabel` →
`Panel.qml:402`. It repeats on every poll.

**Impact.**

- Arbitrary outbound GET from `omarchy-shell`, to a host of the endpoint's
  choosing, on a schedule, unattended and unlogged.
- This is the payload of a beacon, and it defeats `README.md:294-299` — the
  "one endpoint, nothing else" promise that is the plugin's main selling point.
- Arbitrary formatting and impersonation: a hostile name can render bold,
  coloured, large text styled to look like another row's state, or inject
  `<br>` to fabricate extra lines inside one row. This runs inside the shell,
  not a sandboxed browser.

**Fix.** `textFormat: Text.PlainText` on both items — that alone fully closes
it — matching stock `Ui/WidgetButton.qml:77` and `Ui/NumberField.qml:28`.
Additionally sanitise in `Servers.js:48`/`61` so unknown junk from a compromised
endpoint cannot reach the UI at all.

### HIGH — Recovery notification is inverted: fires on outage, never on recovery

**`Service.qml:141` + `Service.qml:144`, vs `Service.qml:196`**

`onStreamFinished: root.settle(root.apply(text))` (`Service.qml:226`) evaluates
`apply()` — which assigns `status` at line 196 — *completely* before `settle`
runs. So `wasDown` at line 141 reads the **new** status, not the previous one:

```js
var wasDown = everReported && status !== "" && status !== "green"
```

**Trigger.** Fleet is green → one server drops → poll returns `orange` →
`wasDown = true && "orange" !== "" && "orange" !== "green"` → true →
`announceRecovery()` fires *"All 7 servers are back online."* while the fleet
is down. The next poll returns `green` → `wasDown = false` → **no notification
at all** on the actual recovery. Both transitions, every time, backwards.

**Impact.** The panel's only push notification asserts the opposite of the
truth on every incident — the "lying UI" outcome the design explicitly sets out
to avoid at `Service.qml:48-51` and `README.md:283-286`.

**Fix.** Snapshot the status before `apply()` runs: capture in `maybePoll()`
(`Service.qml:126`), compare in `settle()`. Keep `everReported` so the first
successful poll stays silent.

---

## Worth fixing

### MEDIUM — No cap on server count: the byte limit does not bound the UI

**`Service.qml:169-187`, `Panel.qml:33-58`, `Panel.qml:148-150`, `Panel.qml:344`**

`--max-filesize` bounds bytes, not elements. `Object.keys(servers)` has no upper
bound — `Service.qml:170` only checks `=== 0` — and the panel then builds two
full JS arrays per poll (`orderedServers` with an `O(n log n)` sort at
`Panel.qml:35`, `serverRows` at `Panel.qml:42`) and instantiates one `Repeater`
delegate per row. Each delegate is a `Rectangle` + 2 `Text` + `Rectangle` +
`ToggleSwitch` + 3 handlers (`Panel.qml:347-478`), in **both** live `Panel`
instances.

Worse, `isMuted` (`Panel.qml:148`) rebuilds the muted-name array from scratch on
*every* call, and it is called once per delegate plus once per row by `anyMuted`
(`Panel.qml:70-74`) → `O(rows × mutedCount)` with an allocation per call.

**Trigger.** `{"servers":{"s1":true, …, "s20000":false}}` is ~200 KB, well
inside the 1 MiB limit.

**Impact.** Layout and binding work for 20 000 delegates on the UI thread inside
`omarchy-shell` — a bar and panel freeze. The uncommitted comment adopts the
"hostile or compromised endpoint" threat model explicitly, so this is squarely
in scope for the change it ships with.

**Fix.** Reject payloads above a sane fleet size in `apply()`, and hoist the
muted-name lookup into one binding computed per settings change instead of
rebuilt per row.

### MEDIUM — `settled` is an unlatchable latch with no watchdog

**`Service.qml:129-131`, `Service.qml:136-150`, `Service.qml:224-230`; symptom
visible at `BarWidget.qml:61`**

`settled = true` is set in `maybePoll` *before* the process starts, and is only
cleared by `settle()`, which runs only from `onStreamFinished` or `onExited`.
There is no wall-clock backstop, so once the latch is stuck, `maybePoll` refuses
to poll for the rest of the session (`Service.qml:127`).

Two paths reach it:

- **(a)** the spawn fails in a way that emits neither signal;
- **(b)** `apply()` throws, so the argument at `Service.qml:226` never
  evaluates and `settle` is never called. Today `apply()` is well guarded
  (`try/catch` at `Service.qml:161-165`), so (b) needs a hostile object shape;
  (a) could not be ruled out.

**Impact when it happens.** Polling stops permanently, and because `stale` is
only set by `settle(false)` (`Service.qml:148`), the widget keeps painting its
**last known green or red indefinitely** — exactly the lie `README.md:283-286`
claims cannot happen. Silent, and nothing in the journal.

**Fix.** Bound the outstanding poll against the clock and clear the latch when
it overruns, and derive staleness from elapsed time rather than only from the
last outcome, so a poll that never reports can still go stale.

### MEDIUM — `NumberField` writes `shell.json` per keystroke and persists a transient clamped interval

**`Panel.qml:568-581`, `Panel.qml:600-613` → `Panel.qml:105-114` →
`shell.qml:1078` (`updateEntryInline` → `persistShellConfig`)**

`NumberField` is an editable `QQC.SpinBox` (`Ui/NumberField.qml:36-57`) with
`from: 120` / `from: 30`, and `onValueModified` fires per committed edit
(`Ui/NumberField.qml:57`). Typing `3600` into "Healthy poll (s)" commits
`3` → clamped to `120` → `setSetting` → a **full `shell.json`
read/clone/write round trip**, then `36`→120, `360`, `3600`.

`updateEntryInline` also *drops* every key not present in the object it is
handed (`shell.qml:1093-1095`), so every intermediate write rewrites the whole
entry.

**Impact.** Four full config writes and four `service.settings` reassignments
per typed field, and the transient `healthyInterval: 120` becomes a real,
persisted, in-force setting that briefly switches the live poll cadence to
120 s. `setSetting` re-seeds from `service.settings` (`Panel.qml:106`), so the
intermediate write is not free of side effects either.

**Fix.** Coalesce numeric commits and commit on editing-finished rather than
value-modified, and make `setSetting` a no-op when the value already matches.

---

## Also worth doing (LOW)

Nine of these are still open and are listed with a suggested order in
[Still to address](#still-to-address); the tenth (LOW-7) is fixed. Full detail
is kept here so nothing is lost to a summary.

| # | Finding | Reference | Note |
|---|---|---|---|
| 1 | `bar.barForeground` instead of the null-safe inherited `barForeground`, in 23 places | `Panel.qml:196, 264, 277, 286, 305, 318, 329, 377, 436, 475, 484, 495, 506, 540, 551, 577, 590, 609, 622, 637, 648, 663, 674` | **Confirmed, not inferred** — see [Confirmed by execution](#confirmed-by-execution). `bar` is `null` until `injectPanel()` (`BarWidget.qml:95`), so these evaluate before the bar arrives. `grep -c "bar\.barForeground"` across `/usr/share/omarchy/shell/plugins/panels/*/Panel.qml` = **0**; `clock/Panel.qml:79-80` guards it explicitly. `sed` fix. |
| 2 | Panel keyboard switching silently fails — `switchPanel` not overridden | `Panel.qml:26` defines `barIdentity`, no override | `Ui/Panel.qml:32-35` calls `bar.switchPanelFrom(root, …)` with the nested `Panel`; `Bar.qml:661-672` resolves the slot by `slot.activeItem === owner`, which is the bar widget. Every stock nested panel overrides this (`clock/Panel.qml:113-117`, `weather/Panel.qml:59-63`). Add the four-line override. |
| 3 | No `ipcTarget`: panel unreachable over shell IPC | `Panel.qml:18` | All ten stock bar-widget panels set it (`audio:14`, `clock:20`, `weather:11`, …) and `Ui/Panel.qml:49` gates the `IpcHandler` on it, so `omarchy shell summon\|hide\|toggle murankar.eso-server-status` does nothing. Capability gap, not fatal. |
| 4 | `apply()`'s type guard accepts arrays | `Service.qml:167-168` | `typeof [] === "object"`, so `{"servers":[false,true]}` passes; `Object.keys` yields `["0","1"]` and the panel renders two rows named `0` and `1`. Add `Array.isArray(servers)`. |
| 5 | `mutedServers` never pruned, grows monotonically in `shell.json` | `Panel.qml:161-168`, `Service.qml:97-103` | `toggleMonitored` only appends; a name the site drops stays forever and returns pre-muted. `anyMuted` is correctly derived from live rows so the UI stays consistent, but the stored list has no bound and no reconciliation. |
| 6 | `~/.curlrc` is not disabled, so the invocation is not what the README describes | `Service.qml:219-223`, claim at `README.md:330-333` | No `-q`, so a user rc with `-k`, `--proxy` or `--netrc` silently changes the call. README asserts "certificate verification stays enabled" and "neither `--user` nor `--netrc`" as properties of the invocation. No `~/.curlrc`, `/etc/curlrc` or `~/.netrc` exists on this machine, so the claim holds *here* — but it is a property of the user's rc, not the plugin. Add `-q`. |
| 7 | ~~The uncommitted comment omits the curl version floor its safety depends on~~ **RESOLVED** | `Service.qml:303-321` | `--max-filesize` **had no effect at all** for responses of unknown length before **curl 8.4.0** (`curl(1)`: *"before curl 8.4.0, when the file size is not known prior to download, for such files this option has no effect"*). "curl enforces this per chunk" was also wrong: the threshold is checked against the **running total**, not per chunk. Comment rewritten and re-verified; see [The comment, corrected](#the-comment-corrected). |
| 8 | `manifest.json:18` hardcodes "all 7 ESO servers" | `manifest.json:18` | Marketplace-visible description goes stale the moment the fleet changes. (It is 7 today.) |
| 9 | `Service.qml:26` `property var shell` is injected but never read | `Service.qml:26` | Genuinely injected (`shell.qml:929`). Related undocumented coupling: the service's *entire* settings channel is `BarWidget.pushSettings()` (`BarWidget.qml:73-74`), so with no widget in the bar the service polls on hardcoded defaults. |
| 10 | `README.md:216` says "the four polling settings"; there are five | `Panel.qml:531, 564, 596, 628, 654` | Line 220 of the same file correctly says "All five". |

### Nits

- `Panel.qml:350` — `required property int index` is declared and never used.
- `Panel.qml:502` — `Text {` at column 1 inside the `siteLink` `Rectangle`
  (misindented; ~30 lines of indentation drift).
- `Panel.qml:502-510` — site-link `Text` has `anchors.right` but no left anchor
  and no `elide`; safe today (constant string) but inconsistent with every other
  `Text` in the file.
- `BarWidget.qml:10, 18` — the plugin id is hardcoded in two places instead of
  reusing `moduleName`.
- `Theme.js:32-33` — `toRgb` parses before length-checking. Functionally correct
  given the regex at line 25, but the order reads like a bug.

---

## Performance round — one applied, three proposed

A final pass over the **working tree** (post-fix source, so the line numbers
below are current-tree numbers, not the reviewed revision cited elsewhere) for
optimizations that hold behaviour constant.

> **OPTA-3 is applied, and the other three are not.** OPTA-3 was the one with an
> argument behind it rather than a preference — a leftover of the MEDIUM
> mute-lookup fix — so it was pulled forward and is now covered by harness
> assertions. **OPTA-1, OPTA-2 and OPTA-4 remain unmeasured** proposals: their
> arithmetic is an estimate off the code, and there is no evidence for them to
> match [Confirmed by execution](#confirmed-by-execution). Read those three as
> candidates, not conclusions.

| # | Finding | Reference (working tree) | Status |
|---|---|---|---|
| OPTA-1 | `compare()` re-decomposes both names on every comparison | `Servers.js:96-106`, used at `Panel.qml:35` | proposed, not applied |
| OPTA-2 | `serverRows` decomposes each name a second time | `Panel.qml:42-58` (`:47`, `:55`) | proposed, not applied |
| OPTA-3 | `apply()` scans the muted array per server — O(servers × muted) | was `Service.qml:273`; now `:287` | **applied, uncommitted** |
| OPTA-4 | Three hand-synchronised copies of the duck-typed list reader | `Service.qml:152`, `Panel.qml:193`, `Panel.qml:205` | proposed, not applied |

### OPTA-3 — applied

The asymmetry was the whole finding: the MEDIUM fix gave `Panel.qml` an O(1) mute
lookup (`Panel.qml:223`, null-prototype, built once per settings change), but the
**service** kept the linear scan. `Service.mutedList()` at `Service.qml:152`
returns a plain array, and `apply()` then called `muted.indexOf(name)` once per
server, inside its loop:

```js
var isMuted = muted.indexOf(name) !== -1
```

So the O(rows × muted) shape the review flagged in the panel survived in
`apply()`, where it runs on **every poll** rather than on a settings change. It
was bounded in practice — `maxServers: 256` (`Service.qml:73`) caps the outer
term — which is exactly why it read as harmless. It was never a security finding
or a publication blocker; it was the MEDIUM fix stopping one layer short.

`Service.qml` now builds the same lookup the panel uses, immediately after
`mutedList()` returns, and reads it inside the loop:

```js
var muted = mutedList()
var mutedSet = Object.create(null)
for (var m = 0; m < muted.length; m++) mutedSet[muted[m]] = true
// ...inside the server loop:
var isMuted = mutedSet[name] === true
```

The null prototype and the `=== true` read are both kept. The `=== true` test is
not incidental: it is the only value that counts, and dropping it would
reintroduce the inherited-property read the panel's comment rules out. The
comment records that payload names — unlike the settings list — are not ours to
constrain, which is the reason the guard is load-bearing *here* in a way it is
not in `mutedList()`.

**Verified, not assumed.** The `Service.qml` harness grew from 41 to **51
assertions**, ten of them specific to this change, and all 51 pass. They pin the
behaviour the `indexOf()` scan had, rather than the new mechanism:

- a muted server leaves the counts but stays in `serverList`, and its **stored key
  survives** so existing `mutedServers` entries keep matching;
- muting the last-named server in a six-server fleet still counts it out;
- a payload name of `constructor` or `hasOwnProperty` reads as **not** muted —
  the null-prototype property, on the names an attacker actually controls;
- a genuinely muted `__proto__` *is* muted, so the guard is not simply broken;
- the all-muted fleet still reports the `-1` sentinel and an empty verdict;
- a non-array `mutedServers` is ignored rather than fatal.

One assertion was wrong on first write — it expected `3/5` for a fleet where the
muted server was also up, which double-counted it. The panel's own `-1`
comment caught the intent; corrected to `2/5` and passing. Recorded because a
test that fails for its own arithmetic and gets "fixed" is how a real
regression would slip through later.

The `--max-filesize` flood test, the rich-text beacon test (`HIT /beacon-auto.png`
for `AutoText`, nothing for `PlainText`), and the 18-`TypeError` bare-`Panel`
baseline are all unchanged, as expected: none of them touch `apply()`.

### OPTA-1 / OPTA-2 — proposed, not applied

`Servers.compare` (`Servers.js:96-106`) calls `region()`, `groupRank()` and
`label()` on **both** operands on every invocation, and `label()`/`region()` each
run `split()` and the `plain()` regex pass. It is passed straight to `sort()` at
`Panel.qml:35`, so the cost is O(n log n) in comparisons and the same name is
re-split and re-regexed roughly `2·log2(n)` times.

`Panel.qml:42-58` then walks the sorted result and calls `Servers.region()`
again at `:47` and `Servers.label()` again at `:55` to build group headings and
row labels — a second full decomposition pass over the same fleet.

Both are per-poll, on the UI thread, and `n` is now allowed to reach 256
(`Service.qml:73`), so this is the path that got more expensive when the MEDIUM
cap landed. Rough arithmetic: at n=256 a sort costs ~256×(2×8) ≈ 4 100
decompositions plus 512 more in `serverRows`; decorating first makes it 256. For
today's 7-server fleet the difference is noise, and the estimate is exactly that
— an estimate.

The fix is decorate-sort-undecorate, with `Servers.compare` left in place for
anything else that reads it:

```js
function sortKeys(server) {
  var regionText = region(server.name)
  return { row: server, rank: groupRank(regionText), label: String(label(server.name)) }
}

function compareKeys(a, b) {
  if (a.rank !== b.rank) return a.rank - b.rank
  if (a.label < b.label) return -1
  if (a.label > b.label) return 1
  return 0
}
```

`Panel.qml:33-37` sorts the decorated array; `serverRows` then reads
`key.region` / `key.label` instead of re-deriving them. Ordering is unchanged
because the comparison key is the same function of the same input, evaluated
once rather than repeatedly — that equivalence is the thing to assert, not the
timing.

### OPTA-4 — proposed, not applied — one reader, not three

`Service.qml:152` and `Panel.qml:193` are the same function reading different
settings objects; `Panel.qml:205` (`storedMutedList`) is a third variant with its
own fallback. The comment at `Panel.qml:188-192` states the hazard outright: the
copies **have to agree** or a switch stops matching its own row.

Three synchronised-by-hand copies of a correctness-critical guard is itself the
defect risk, independent of any runtime cost — which is near zero, since each
runs once per poll or once per click. Collapse the shared shape into
`Servers.js`:

```js
function nameList(raw) {
  if (!raw || typeof raw.length !== "number") return []
  var names = []
  for (var i = 0; i < raw.length; i++) names.push(String(raw[i]))
  return names
}
```

Leave `storedMutedList`'s source selection in `Panel.qml`: preferring the
service copy is a deliberate correctness rule (this instance's own settings can
be a write behind), not a detail to fold into the shared helper.

### Deliberately not proposed

None of these were implemented either; they are recorded so they are not
re-derived later.

Palette work (`Theme.parsePalette` at `Theme.js:21`, `Theme.pick` at `Theme.js:61`,
duplicated across `Panel.qml:263-269` and `BarWidget.qml:45-51`, each with its
own `FileView` at `Panel.qml:256` and `BarWidget.qml:129`), caching those palette
results, lazy-loading the panel tabs via `Loader`, consolidating the two
`FileView`s, and touching `pollTimer` / `nextIntervalSeconds()`
(`Service.qml:172`, called only from `:195` and `:212`). Each was considered and
rejected as churn: the palette path runs on theme changes, not per frame, and the
timer path is two read-only property reads. Full reasoning, including the
per-tab-`Loader` caveats, is in [ProjectNotes-Optimizations.md](ProjectNotes-Optimizations.md).

### How to verify, if the rest get applied

- **OPTA-1** — sort order equality against `Servers.compare` at n=4 and at the
  256-row cap. Equality of order is the assertion; speed is not the claim.
- **OPTA-2** — `serverRows` output identical to the current headings and labels,
  in order, for a fleet spanning every region group including the test server.
- **OPTA-4** — toggle a switch with the panel closed and with it open; the
  existing `Panel.qml` harness covers the cross-instance case.

**OPTA-3's verification is already done** and is recorded above — ten harness
assertions, 51/51 passing. The three remaining items have none.

---

## The uncommitted change

Reviewed in isolation, and **verified end-to-end rather than read**: the exact
`Process` + `StdioCollector` shape from `Service.qml:207-231` was run under a
real `qs` harness against a local endpoint streaming 1.31 GiB.

```
NOLIMIT  collected bytes = 1310720000   exit = 0
LIMITED  collected bytes = 1048576      exit = 63
```

So all three operative claims hold:

- `StdioCollector` really does buffer without bound — 1.31 GB in a single 10 s
  poll, delivered as **success** (exit 0). The timeout does not bound memory.
- `--max-filesize` really does bound it, and exit 63 really does reach
  `settle(false)` via `Service.qml:228-230` → `failures++` / `stale = true` →
  the exponential backoff at `Service.qml:117-124`.
- The comment's premise is accurate: the live response has **no
  `Content-Length`** (HTTP/2, `content-type: application/json`), so the
  unknown-length path is the one that matters. The limit aborts mid-stream with
  exit 63 under HTTP/1.1 chunked, HTTP/1.0 close-delimited, and an unframed
  close-delimited stream — 1048576 bytes exactly in each case.
- The size arithmetic: the live payload is exactly **124 bytes**, so "~124 bytes
  today" is exact and "four orders of magnitude" is right (8464×).

**Verdict: keep it.** The comment overstated the protection in two ways, both
now fixed — see [The comment, corrected](#the-comment-corrected) below.

---

## The comment, corrected

The original comment claimed *"curl enforces this per chunk"* and said nothing
about a version floor. Both were wrong, and the second is the kind of wrong that
matters in a security comment: it tells a reader they are protected on a system
where they are not.

**Re-verified from `curl(1)` on 8.22.0:**

```
--max-filesize <bytes>
       ...
       NOTE: before curl 8.4.0, when the file size is not known prior to
       download, for such files this option has no effect even if the file
       transfer ends up being larger than this given limit.

       Starting with curl 8.4.0, this option aborts the transfer if it
       reaches the threshold during transfer.
```

and `63  Maximum file size exceeded.`

**Re-measured the behaviour rather than trusting the prose** — a local server
streaming 64 MiB with no `Content-Length`, chunked:

```
unlimited exit=0
limited   exit=63
unlimited bytes = 67108864
limited   bytes = 1048576
limit            = 1048576
```

Two things fall out of that. `--max-time` alone bounds nothing: without the flag
the whole 64 MiB collects and curl reports success. And the limited run collects
**exactly** 1048576 — a per-chunk ceiling would have overshot by up to a chunk,
so the threshold is on the running total, exactly as the man page words it.

**What the comment now says**, in `Service.qml`:

- the timeout bounds duration and not size, with the 64 MiB measurement as the
  reason;
- the limit is a running total, not a per-chunk ceiling, with the exact-1048576
  measurement as the reason;
- exit 63 reaches `settle(false)` and backs off;
- the protection depends on **curl ≥ 8.4.0**, and a body with no
  `Content-Length` — which is what this endpoint sends — is precisely the case
  that older curl does not cover;
- `maxBodyChars` in `apply()` is named as the backstop for an old curl, since it
  refuses the body before `JSON.parse`;
- the 1 MiB figure is headroom over the measured 124-byte document.

The flag itself is unchanged. This was a comment fix, and a `curl(1)` claim in a
comment about memory safety is worth getting right.

---

## Verified correct

Checked deliberately, so these do not need re-review.

**Subprocess and network security**

- `command` (`Service.qml:219-223`) is a `QStringList` handed to `QProcess` —
  **no shell**, so command injection is impossible.
- `root.apiUrl` is a `readonly` string constant (`Service.qml:28`), neither
  remote- nor user-controlled, so no argument injection either.
- No secrets, tokens, cookies or auth material anywhere in the plugin.
- `-k` / `--insecure` never used. No `-L`, so a redirect cannot move the request
  off `https://esoserverstatus.net` or downgrade it.
- No `--user` / `--netrc` / `--compressed`; no `-b` / `-c`, so the
  `set-cookie: eso_hub_session=…` the endpoint sends is neither stored nor
  replayed.
- Only `stdout` is wired to the collector (`Service.qml:224`), so `-sS`
  diagnostics cannot accumulate in the shell either.
- `Quickshell.execDetached` calls (`Service.qml:201`, `BarWidget.qml:171`,
  `Panel.qml:514`) all use argv arrays.

**Polling and lifecycle**

- The README request-budget table is arithmetically correct and matches the code:
  86400/300 = 288, 86400/60 = 1440, converging to 86400/600 = 144 for the capped
  backoff. `nothingMonitored → 300 s` matches `nextIntervalSeconds()` falling
  through to `healthySeconds()` for `status === ""`.
- Backoff cannot storm. `lastPollAt` is stamped at poll *start*, so the interval
  is start-to-start and a 10 s `--max-time` hang cannot shorten the effective
  period. `maybePoll` guards on `paused || settled || fetch.running`, so polls
  never overlap. `Math.min(backoff, 600)` correctly bounds
  `Math.pow(2, min(failures-1, 10))`.
- No timer, `Connections` or binding leak, and no multiplier. One `pollTimer`
  per service instance, unconditionally running (`Service.qml:235-242`), tied to
  the object's lifetime; no `Connections` anywhere; the four injection calls at
  `BarWidget.qml:141-150` (`onLoaded` + `Qt.callLater` + `onStatusChanged`) are
  idempotent assignments.
- `Panel`'s `KeyboardPanel` is `visible: false` when closed
  (`KeyboardPanel.qml:81`), so the always-loaded hidden panel
  (`BarWidget.qml:138`) costs no mapped surface.

**Data handling**

- Payload parsing matches the real document. Verified against the live endpoint:
  `payload.servers` is a flat object of booleans, so `value === true` /
  `value === 2` / else-offline at `Service.qml:182` and the counts at
  `Service.qml:185-196` are right.
- Both remote-derived `Text` items carry `elide: Text.ElideRight`
  (`Panel.qml:403, 474`), so a hostile long name cannot push the layout around.
- `serverList` / `settings` are reassigned wholesale rather than mutated in
  place, which is the correct way to notify QML (`Service.qml:46, 195`).
- `storedMutedList()` copies before `push`/`splice` (`Panel.qml:136-143`), so the
  stored array — the same object the service holds, and the one QML compares
  references on — is never mutated inside a binding.
- `service.serverList` is sorted on a copy (`Panel.qml:34`).
- The plugin writes nothing itself: `FileView` is read-only (theme palette at
  `BarWidget.qml:129-134`, `Panel.qml:171-176`), and all persistence goes
  through the shell's own `updateEntryInline` → `shell.json`, disclosed at
  `README.md:194` and `README.md:220-221`.

**Shell integration**

- `root.bar.shell` exists on `PluginBarApi` (`PluginBarApi.qml:12`);
  `serviceFor` is scoped but same-id-resolvable (`PluginShellApi.qml:30-32`);
  `shell` is genuinely injected into the service (`shell.qml:929`).
- `updateEntryInline` and `bar.shell.hideTooltip` are both guarded with the
  `typeof === "function"` check the stock widgets use (`Tray.qml:184`,
  `clock/Panel.qml:161`).
- `WidgetButton` drives `implicitWidth`/`implicitHeight`, not
  `width`/`height` (`WidgetButton.qml:68-69`), so `anchors.fill: parent` at
  `BarWidget.qml:155` is correct and matches stock. `Style.bar.statusSlot`
  exists (`Style.qml:347`). `ToggleSwitch.toggled()` carries no argument, so the
  four `onToggled:` handlers are correct.

**Manifest**

- Valid and self-consistent: `schemaVersion: 1`; all six fields required by
  `PluginRegistry.validateManifest` (`PluginRegistry.qml:52`) present;
  `defaultSection: "right"` is in the allowed set (line 75); both entry points
  are relative, `..`-free and inside `sourceDir` (lines 82-88, 118-133); `id` has
  no `/` or `..`. `keepLoaded` is a real key (`shell.qml:1025-1028`).
- All six `defaults` match the code fallbacks at `Service.qml:57, 106, 110, 144`
  and `BarWidget.qml:41`. `mutedServers` correctly appears in `defaults` but not
  in the visible `schema` — it is per-server, not a user-typed field.
- `kinds: ["service","bar-widget"]` is correct: `PluginRegistry.isEnabled`
  (line 148) then requires a `shell.json` reference, which `bar.layout.right`
  provides.

---

## Could not verify

- **Whether the running shell currently loads this plugin at all.**
  `log.qslog` for the live instance (PID 1235, started 19:01) contains zero
  occurrences of `murankar`, `eso-server`, `Service.qml` or `TypeError`. The
  plugin *is* in `bar.layout.right` and its settings *are* in
  `~/.config/omarchy/shell.json`, and the journal shows it loading in earlier
  runs (PID 1227 at 10:33 / 17:15 / 17:28). Most likely the qslog does not
  capture registry/JS-realm messages at the current level — but it could not be
  confirmed, so there is **no runtime evidence for or against** the fixes in
  situ, in the real bar, on a real theme. Everything below was verified in
  isolation.
- **Whether a Quickshell spawn failure emits `onExited`.** The unlatchable-latch
  finding is a design-gap argument; the failing spawn could not be constructed.
  The 15 s watchdog is there precisely because this could not be ruled out.
- **HTTP/2 specifically.** `--max-filesize` was proved on three unknown-length
  framings, none of them HTTP/2. The real endpoint is HTTP/2, where length is
  never declared. curl's threshold check lives in the transfer read path and is
  framing-independent, but HTTP/2 was not tested directly (no HTTP/2 test server
  was available).
- **Whether `updateEntryInline`'s async `shell.json` round-trip can produce the
  stale-base overwrite** described at `Panel.qml:100-104` (a bar widget pushing
  its older `settings` into the service between the panel's write and the file
  coming back). Self-healing — the round-trip overwrites it — but not observed
  live.
- **Third-party marketplace submission mechanics.** The manifest was validated
  against `PluginRegistry.validateManifest` and `entryPointUrl`, which is what
  `omarchy plugin clone` and the registry rely on, but `omarchy plugin validate`
  and a real submission dry-run were not run.

---

## Confirmed by execution

Two harnesses, both run against the real files rather than a reading of them.

**`Service.qml` — 41 assertions, 41 passing.** A `qs` harness that constructs the
plugin's own `Service.qml`, holds it `paused` from birth so the poll timer never
touches the network, and drives `apply()` / `settle()` / `maybePoll()` directly.
It covers the normal reading path, `value === 2` reading orange, a fully-down
fleet, a hostile server name, both new caps, each rejection case, the recovery
predicate in all four directions, clock-based staleness, and the poll-latch
watchdog in both the expiring and the still-in-time case.

**`Panel.qml` — constructs clean, and the LOW-1 finding is confirmed.** The
panel was loaded bare — no `bar`, no `service`, exactly the state the bar
widget's `Loader` creates it in — and the run produced **18 `TypeError`s, all of
them `Cannot read property 'barForeground' of null`**, at post-edit lines

```
349  362  371  390  403  414  581  603  637  648
674  697  716  735  750  761  776  787
```

That is LOW-1, observed rather than inferred, and it is the strongest argument
for pulling that `sed` forward: 18 warnings in the journal every time the panel
is constructed. `barForeground` of `null` was the **only** error kind in the
whole run, so the review edits introduced no new failure of their own.

The same harness also confirmed the settings-coalescing fix behaves as intended:
`queueInterval` holds a value instead of writing, a second key does not evict
the first, the newest value for a key wins, and no field holds focus so a flush
would write.

**Caveat on both.** The harnesses live in `/tmp/opencode/`, not in the plugin,
and they are not committed. The `Service.qml` one in particular reaches into
`apply`/`settle` — it verifies logic, not the wiring the shell does around it.

---

## Applied corrections

Both HIGH findings and all three MEDIUM findings are fixed in the working tree
and left **uncommitted** for review. Line references above are to the pre-fix
revision.

> **The `Service.qml` changes are not live yet.** `manifest.json:58` sets
> `keepLoaded: true`, and the shell deliberately retains such services across a
> plugin hot-reload (`shell.qml:1025-1035` — it exists so that keeping the lock
> or idle service alive does not drop an ext-session-lock client). Saving
> `Service.qml` therefore logs *"Local plugin changed, reloading"* without
> applying anything. Run `omarchy restart shell` to exercise the new code. This
> also means the `--max-filesize` flag in the uncommitted change has never been
> active in the running shell.

### HIGH — rich text

| File | Change |
|---|---|
| `Panel.qml` | `textFormat: Text.PlainText` on the group heading `Text` and the server-name `Text` — the two items that render remote data. |
| `Servers.js` | New `plain()` helper stripping everything outside `[A-Za-z0-9 _.-]`, applied in `label()` and `groupLabel()`. Defence in depth behind `textFormat`; the payload key itself is untouched, so existing `mutedServers` entries keep matching. |

### HIGH — inverted recovery notification

`Service.qml`: new `statusBeforePoll` property, captured in `maybePoll()` at the
moment the fetch starts. `settle()` now tests the pre-poll status, so
`announceRecovery()` fires on down→up and only then. `everReported` still gates
the first successful poll, and a first reading (previous status `""`) stays
silent.

### MEDIUM — unbounded server count and per-row array rebuilds

| File | Change |
|---|---|
| `Service.qml` | `maxServers` (256) rejects an implausible payload; a 64 KiB guard on the response body is applied *before* `JSON.parse`, so the parse is bounded even where `--max-filesize` cannot help. |
| `Panel.qml` | `mutedLookup` builds a null-prototype lookup once per settings change; `isMuted()` is now O(1) with no allocation, so the delegates and `anyMuted` stop being O(rows × muted). |

### MEDIUM — unlatchable poll latch

`Service.qml`: `pollStartedAt` plus a 15 s watchdog (`--max-time` is 10 s) in
`maybePoll()`; an overrunning poll is failed by hand and its `Process` stopped,
so the latch cannot close for the rest of the session. Staleness is now
`failed || overdue` — a plain `overdue` property recomputed on every 2 s tick
against `lastGoodAt`, so a reading goes stale on the clock even if `settle`
never runs. `paused` suppresses `overdue`, keeping the paused and stale UI states
distinct as the existing comments intend. `BarWidget.qml` and `Panel.qml` are
unchanged: they still read `service.stale`.

### MEDIUM — per-keystroke `shell.json` writes

`Panel.qml`: numeric commits are coalesced into `pendingInterval` and flushed by
a 500 ms timer, on focus loss from either field, and when the panel closes. A
flush is *skipped* while a field still has focus, because a mid-edit value clamps
as the user types and committing it would persist a number they never chose —
this is what removes the transient `healthyInterval: 120`. `setSetting` now also
no-ops when the value already matches, so a redundant write is not a redundant
`shell.json` round trip.

### OPTIM — the service's mute lookup

`Service.qml`: `apply()` built the muted-name lookup per server with
`muted.indexOf(name)`, so a poll cost O(servers × muted). It now builds the same
null-prototype lookup the panel uses (`Object.create(null)`, `=== true` read)
once per poll, ahead of the server loop — closing an asymmetry left by the
MEDIUM mute fix above, which had fixed only the panel's copy.

Verified by ten new harness assertions (41 → 51, all passing) covering counts,
the surviving stored keys, the `-1` all-muted sentinel, and — the point of the
null prototype — payload names of `constructor` / `hasOwnProperty` not reading
as muted. Detail and the one miscounted assertion are in
[Performance round](#performance-round--one-applied-three-proposed).

### Remaining after this pass

All outstanding work is consolidated in [Still to address](#still-to-address):
nine LOW findings and the nits, none of which block publication. **LOW-1 is the
one to pull forward** — a one-line `sed`, and it is the only remaining finding
with a measurement behind it rather than an argument.

Separately: a performance round is recorded in
[Performance round](#performance-round--one-applied-three-proposed). **OPTA-3 is
applied and verified** (51/51 harness assertions) — it was the leftover of the
MEDIUM mute-lookup fix. **OPTA-1, OPTA-2 and OPTA-4 are unimplemented and
unmeasured**; they are deferred, not rejected, and OPTA-1/2 become worth
revisiting if the fleet approaches the 256-server cap.
