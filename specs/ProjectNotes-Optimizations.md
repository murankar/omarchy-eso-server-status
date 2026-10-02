# Optimization Review — ESO Server Status

Private working note. Not published: listed in `.gitignore` alongside the other
`ProjectNotes-*` files.

| | |
|---|---|
| **Plugin** | `murankar.eso-server-status` v1.3.0 |
| **Reviewed revision** | `f13906f` plus the uncommitted `Service.qml` / `Panel.qml` / `Servers.js` / `.gitignore` working-tree changes from the [code review](ProjectNotes-CodeReview.md) |
| **Scope** | Performance and structure across `Service.qml`, `Panel.qml`, `BarWidget.qml`, `Servers.js`, `Theme.js`, `manifest.json` — **without breaking functionality** |
| **Codebase size** | 1500 lines: `Panel.qml` 795, `Service.qml` 355, `BarWidget.qml` 177, `Servers.js` 105, `Theme.js` 68 |
| **Date** | 2026-09-30 |

---

## Verdict

The plugin is small and already well-disciplined: one poll per interval for the
whole shell, an O(1) mute lookup, bounded payloads, no leaks, no timer or
binding churn. **There are no dramatic wins left** — most of what a generic
optimization pass would "fix" is already at the floor.

Four changes are genuinely worth making, all behavior-preserving. Two more are
optional and come with caveats. The rest of this note is a list of ideas that
look tempting but would buy nothing, kept on purpose so they are not
reconsidered later.

Baseline for judging every item below: the panel opens on demand, the fleet is
7 servers (cap 256), a healthy poll fires once per 300 s over a 124-byte body,
and the panel holds ~10 row delegates plus 5 settings rows. Anything that does
not measurably reduce work **per poll** or **at shell startup** is not an
optimization here — it is churn.

---

## Worth doing

### 1. Skip the `serverList` reassign when the payload content is unchanged

**`Service.qml:289`** — `serverList = list` runs unconditionally on every
successful poll.

The cost lands downstream. A `Repeater` with a JS array model treats a **new
array reference as a model reset**: it destroys every delegate and recreates all
of them, even when all seven rows are byte-for-byte identical. On a healthy
300-second tick with the panel open, ~10 delegates — each a `Rectangle` + 2
`Text` + dot + `ToggleSwitch` + 3 handlers (`Panel.qml:430-576`) — churn for no
visual change: hover states clear, anchors re-resolve, every row binding
re-evaluates.

**Change.** Compare content before assigning: length, then `name` + `state` per
element. Assign only if something differs. The other outputs of `apply()`
(`status`, `onlineCount`, `totalCount`, `hasReading`) stay unconditional scalar
assignments — they are cheap, and when the list content is identical they are
identical too.

**Why it cannot break anything.** The guard only *skips* a notification QML
would otherwise fire for data equal to what it already holds. Every binding
depending on `serverList` receives the same values. The compare is O(n) per poll
— well inside the cost of the parse that produced the array.

**Gain.** Eliminates a full delegate teardown/rebuild cycle on every
no-change poll: the single most expensive thing the plugin currently does per
tick.

### 2. Precompute sort keys instead of recomputing them per comparison

**`Panel.qml:33-40`** (`orderedServers`) + **`Servers.js:96-106`** (`compare`).

Each `compare()` call runs `region(a)` + `region(b)` + `label(a)` + `label(b)` —
four `split()`s (String conversion, `lastIndexOf`, two `slice`s) plus `plain()`
regex passes — *for the same two names, over and over*. A sort is O(n log n)
comparisons × 4 decompositions.

**Change.** Decorate-sort-undecorate inside the `orderedServers` binding:
compute `{row, rank, label}` once per server (n decompositions), sort on the
precomputed `rank` / `label`, map back to the existing row shape. `Servers.js`
stays untouched for anything that reads `compare`.

**Why it cannot break anything.** The ordering key is the same function of the
same input — `groupRank(region)` then `label` — computed once instead of roughly
four times per comparison. The output array is byte-identical; this is a
textbook order-preserving transform. The existing harness can confirm order
equality directly (`Servers.compare` assertions at n=4 already exist).

**Gain.** Meaningful at the 256-row cap: ≈8k decompositions per sort → 512.
Invisible at today's 7 rows — but the cap exists so a hostile payload cannot
hurt, and this makes the sort honest at that cap too.

### 3. One implementation of status-color picking

**`Panel.qml:265-270`** and **`BarWidget.qml:47-52`** are line-for-line
duplicates: identical `Theme.pick` calls over identical candidate arrays, each
component re-allocating them on every palette change. Both components also carry
their own `FileView` watching the same `colors.toml`
(`Panel.qml:256`, `BarWidget.qml:129`, both `watchChanges: true`).

**Change.** Add `Theme.statusColors(palette)` to `Theme.js`, returning
`{ green, orange, red }`; both components call it once. Keep each component's
own `FileView` — consolidating the watchers would need an injection path and
touch load order for the sake of two file watchers on a small file.

**Why it cannot break anything.** A pure-function extraction of code that is
already identical in both places. If a candidate list ever needs editing — the
exact kind of two-place drift this codebase has already been bitten by — it
changes in one place.

**Gain.** Mostly maintenance: no more dual-list drift, one set of candidate
arrays instead of two per component. Small runtime win on theme change (one
parse chain instead of two per component for the pick stage).

### 4. Collapse the three muted-list readers into one helper

Three near-identical duck-typed array readers:

| Copy | Location | Reads from |
|---|---|---|
| `Service.mutedList()` | `Service.qml:152` | `settings.mutedServers` |
| `Panel.mutedList()` | `Panel.qml:193` | `root.settings.mutedServers` |
| `Panel.storedMutedList()` | `Panel.qml:205` | `service.settings` first, then `root.settings` |

Each reimplements the cross-realm `typeof length === "number"` guard with its
own copy of the rationale — and the comments warn that the copies **have to
agree or a switch stops matching its own row**. Three copies of a
correctness-critical invariant is itself the defect risk.

**Change.** One `readNameList(source, key)` helper (in `Servers.js` or a small
`Settings.js`), called with the settings object as an explicit argument —
preserving the documented asymmetry (Panel writes seed from the service copy;
reads come from the instance's own).

**Why it cannot break anything.** The guard semantics are copied verbatim; only
the loop moves. The behavioral difference among the three becomes an explicit
argument instead of being implied by which file the function sits in. The
rationale comment moves once, with the code that needs it.

**Gain.** Runtime ≈ 0 (each reader runs once per poll or once per user click).
The invariant stops being maintained in triplicate — that is the prize.

---

## Optional — real gains, with caveats

### 5. Lazy-load the panel — `BarWidget.qml:136-137` (`active: true`)

The entire 795-line `Panel.qml` — `FileView`, `KeyboardPanel` window machinery,
both tabs — is instantiated at shell startup, per bar surface, whether or not
the user ever clicks. `active: false` until first interaction would cut
cold-start work.

**Caveat.** `togglePanel()`, `opened`, and `injectPanel()` are mostly
null-guarded already (they check `panelLoader.item`), but first open becomes
asynchronous: one load delay, and `opened` reports `false` until the load lands.
Timing-sensitive on a hot-reloadable shell. Worth it only if shell startup cost
ever matters; otherwise skip.

### 6. Per-tab `Loader` instead of `visible:` flags — `Panel.qml:421`, `Panel.qml:623`

Both tabs are always instantiated; `visible` only hides one. A `Loader` per tab
would halve the instantiated objects in the hidden tab.

**Caveat.** Switching tabs mid-edit would destroy the focused `NumberField`.
The flush-on-focus-loss logic added in the code review makes that *safe*
(a pending value is written before the field goes away), but it converts a
currently-impossible edge case into one that relies on that machinery.
Small memory saving on a panel that is itself hidden most of the time —
skip unless the tabs ever grow heavy.

---

## Tempting, and not worth it

Kept deliberately, so these are not re-litigated.

| Idea | Why not |
|---|---|
| Adaptive / longer `pollTimer` tick (2 s → slower when idle) | The tick is a handful of date math and property reads: microseconds. The complexity buys nothing. |
| Replace the `curl` subprocess with an in-process HTTP client | The subprocess is isolated, argv-safe, timeout-bounded, and already on the backoff path. Rewriting to QML networking is high risk for a 124-byte body every 5 minutes. |
| Cache `subtitle()` / `colorForState()` / `textForState()` | Each evaluates a few times per *state change*, not per frame. They are plain functions over scalar properties. |
| Memoize `Theme.pick` results | Only runs when the theme file changes: 3 components × 3 colors × ≤8 candidates of hex parsing. |
| Optimize `parsePalette` (regex per line) | `colors.toml` is a small file, parsed once per component per theme change. |
| Share one `FileView` across components | Needs an injection path (service or parent widget), coupling the view layer to load order — for two watchers on a small file. Not a win. |
| Micro-optimize `Servers.js` primitives (`String()` calls, `slice`) | Below measurement at n=7–256. Only the decomposition in item 2 scales. |
| Stop the 2 s timer while `paused` | A paused `maybePoll()` returns after two property reads. Binding `running` to `!paused` would actually *delay* the first poll after resume by up to 2 s (the timer would not fire immediately on restart). A regression dressed as an optimization. |
| Content-diff the whole `serverRows` array in the panel | Solves the same problem as item 1, one layer too late — by then the model has already changed reference. Fix at the source. |

---

## Suggested order

1. **Item 1** (content guard) — biggest real runtime effect; three lines in
   `apply()`.
2. **Item 2** (sort keys) — makes the 256-row cap path honest.
3. **Items 3 + 4** (dedup) — one session of mechanical edits, best maintenance
   return.

All four are testable against the existing `Service.qml` harness (41
assertions): item 1 by asserting the list reference *does not* change when
content is identical and *does* when it differs; item 2 by asserting sort order
equality against `Servers.compare` at n=4 and at the cap.

**Verification status: not yet implemented.** This note is a review only; the
working tree still contains exactly the changes from the code review pass.

---

## Related

- [ProjectNotes-CodeReview.md](ProjectNotes-CodeReview.md) — the full defect
  review this pass builds on (2 HIGH, 3 MEDIUM, LOW-7 fixed; 9 LOW open)
- `TODO.md` section 5 — outstanding items, including the LOW findings
- `README.md` — request budget and privacy claims that constrain what may
  change on the network path
